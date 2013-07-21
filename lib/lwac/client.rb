require 'lwac/client/file_cache'
require 'lwac/client/storage'

require 'lwac/shared/multilog'
require 'lwac/shared/identity'
require 'lwac/shared/serialiser'

require 'timeout'
require 'digest/md5'


require 'simplerpc/client'
require 'lwac/shared/data_types'  # for serialisation
require 'blat'

require 'curb'

module LWAC

  class DownloadClient

    # Construct a new DownloadClient
    def initialize(config)
      # Save the config
      @config = config

      # Generate a unique identifier for this host
      @uuid = generate_uuid

      # Fire up el RPC client...
      @rpc_client = SimpleRPC::Client.new(@config[:server])

      # Don't RPC again until...
      @rpc_delay    = Time.now

      # Construct a new multi-curl thingy
      $log.info "Starting download engine..."
      @dl = Blat::Queue.new(@config[:client][:simultaneous_workers])

      # List of links pending, cached.
      @links        = []
      @cache        = new_cache
      @cache_bytes  = 0

      # Mutices for link access
      @link_mx      = Mutex.new
      @cache_mx     = Mutex.new

      # Don't try to acquire more data until...
      @checkout_delay = Time.now

      # Start the log with UUID info.
      $log.info "Client started with UUID: #{@uuid}"

      # ping for helpfulness
      ping
    end

    # Poll the server and download from the web, maintaining throughput
    # to the web by downloading batches of links.
    def work

      loop do
        @dl.perform do

          sleep(@config[:client][:monitor_rate])

          # Keep the download queue topped up
          while @dl.request_count < @config[:client][:simultaneous_workers] && (new_link = get_curl)
            @dl.add(new_link)
          end

          # Read things safely using a mutex
          link_len          = @link_mx.synchronize { @links.length }
          active_requests   = @dl.request_count
          cache_len, bytes  = @cache_mx.synchronize { [@cache.length, @cache_bytes] }

          # Print nice progress output for folks
          if @config[:client][:announce_progress] && (link_len > 0 || cache_len > 0 || active_requests > 0)
            progress_mb      = bytes.to_f / 1024 / 1024
            limit_mb         = @config[:client][:cache_limit].to_f / 1024 / 1024
            pc_progress      = (progress_mb / limit_mb) * 100

            str =  "#{progress_bar(@config[:client][:cache_limit], bytes)} #{pc_progress.round}%"
            str += " #{progress_mb.round(2)}/#{limit_mb.round(2)}MB"
            str += " (#{link_len} pend, #{active_requests} active, #{cache_len} done)"
            str += " #{(link_len == 0 && Time.now < @checkout_delay) ? "[waiting #{(@checkout_delay - Time.now).round}s]" : ''}"
            
            $log.info(str)
          end

          # Run out of links
          if link_len <= 0 && Time.now > @checkout_delay 
            acquire_links
          end

          # Downloaded enough data already
          if (@dl.idle? || bytes > @config[:client][:cache_limit]) && cache_len > 0
            # (@pool.cache_size.to_f / 1024.0 / 1024.0) > @config[:client][:cache_limit] then
            # Send completed points back to the server
            send_cache
          end
        end

        $log.debug "Downloader is idle."

      end

    rescue SignalException => se
      $log.fatal "Caught signal - #{se}"
    ensure
      # Cancel web requests
      cancelled = @dl.request_count
      if @dl.request_count > 0
        $log.info "Cancelling #{@dl.request_count} web requests..."
        @dl.cancel
      else
        $log.info "No web requests active."
      end

      # Tell the server we're dying
      if @links.length > 0 || @cache.length > 0 || @dl.request_count > 0
        $log.info "Releasing lock on approx. #{@links.length + @cache.length + cancelled} links..."
        rpc(5) do |s|
          s.cancel(LWAC::VERSION, @uuid)
        end
      else
        $log.info "No links to clean up."
      end
      
      # Quit
      $log.info "Done.  Client has closed cleanly."
    end

  private

    # Pings the server to test RPC methods
    def ping
      $log.info "Pinging server..."
      nonce = Random.rand(82349849)
      reply = rpc(1) do |s|
        s.ping(LWAC::VERSION, @uuid, nonce)
      end
      
      unless nonce == reply
        $log.warn "Failed to ping server!  Please check your network properties."
      else
        $log.info "Your network setup seems to work, that's good news :-)"
      end
    end

    # Returns a cURL::Easy object for downloading
    def get_curl
      link = @link_mx.synchronize { @links.pop }

      return nil unless link

      # Construct new curl from the link
      curl      = Curl::Easy.new(link[:link].uri)

      # configure curl using config
      link[:config][:curl_workers].each do |k, v|
        if v.is_a?(Array)
          curl.send(k.to_s + '=', *v)
        else
          curl.send(k.to_s + '=', v)
        end
      end

      # Set completion handler
      curl.on_complete do |res|
        datapoint = nil
        begin
          datapoint = LWAC::DataPoint.from_request(link[:config], link[:link], res, @uuid, nil) # TODO: set error if needed.
        rescue StandardError => e
          $log.error "Error during request standardisation: #{e}"
          $log.debug "#{e.backtrace.join("\n")}"
        
          # Insert error if the above failed
          datapoint = LWAC::DataPoint.new(link[:link], {}, '', '', {}, @uuid, e) if !datapoint
        ensure
          @cache_mx.synchronize do
            @cache[link[:link].id] = datapoint
            @cache_bytes += res.downloaded_bytes
          end
        end
        $log.debug "Link #{link[:link].id} downloaded."
      end

      $log.debug "Link #{link[:link].id} sent for download."

      # Return curl
      return curl
    end

    # Acquire links from the server.
    def acquire_links

      $log.info "Requesting #{@config[:client][:batch_capacity]} links..."

      loop do
        ret = rpc do |s|
          s.check_out(LWAC::VERSION, @uuid, @config[:client][:batch_capacity])
        end

        # If the server tells us to back off, so do.
        if ret.class == Fixnum
          $log.info "Server says to ask again at #{Time.now + ret}"
          @checkout_delay = Time.now + [ret, @config[:network][:maximum_reconnect_time]].min
          return 
        elsif ret.class == Array && ret.length == 2

          # Load the worker config into the list
          policy, links = ret
          @link_mx.synchronize do
            links.each do |l|
              @links << {:link => l, :config => policy}
            end
          end

          $log.info "Received #{links.length}/#{@config[:client][:batch_capacity]} links from server."
          return links.length
        else
          $log.warn "Received unrecognised return from server of type: #{ret.class}.  Retrying..."
          $log.debug "Server said: '#{ret}'"
        end
      end
    end


    def send_cache

      # Create a new cache and keep the old one for uploading
      cache_to_send, bytes_to_send = nil, nil
      @cache_mx.synchronize do
        # Retain handles to old ones
        cache_to_send = @cache
        bytes_to_send = @cache_bytes

        # And create new ones
        @cache          = new_cache
        @cache_bytes    = 0
      end

      while cache_to_send.length > 0 do

        # Take them out of the pstore up to a given size limit, then send that chunk
        pending = []
        pending_size = 0.0
        $log.debug "Counting data for upload..."
        while(cache_to_send.length > 0 and pending_size < @config[:client][:check_in_size]) do
          key             = cache_to_send.keys[0]
          dp              = cache_to_send[key]
          pending_size    += dp.response_properties[:downloaded_bytes].to_f
          pending         << dp
          cache_to_send.delete_from_index(key)
        end

        # send datapoints
        $log.info "Sending #{pending.length} datapoints (~#{(pending_size.to_f / 1024 / 1024).round(2)}MB) to server..."
        ret = rpc do |s|
          s.check_in(LWAC::VERSION, @uuid, pending)
        end
        if ret.is_a?(Array)
          $log.info "Done (server reported #{ret[0]} failures)"
          $log.info "Server reports work rate as #{ret[1].to_f.round(2)} links/s" if ret[1]
        else
          $log.warn "Server returned something unexpected when checking in."
        end
      end

      # Here cache_to_send.length == 0, so wipe the cache
      cache_to_send.delete_all
    end

    # Yields to perform RPC tasks with a backoff
    def rpc(retries = -1)
      $log.debug "Connecting to server #{@rpc_client.hostname}:#{@rpc_client.port}..."
      # TODO: update this to match new SimpleRPC exception format (as soon as one is implemented)
      
      failed = true
      ret    = nil
      rpc_delay_increment = @config[:network][:minimum_reconnect_time]
      while (retries -= 1) != -1 && failed do

        # Delay until the point we were asked to
        if @rpc_delay > Time.now
          $log.info "Rate limit: delaying for #{(@rpc_delay - Time.now).round}s until #{@rpc_delay}..."
          sleep(@rpc_delay - Time.now) + 0.1 
        end

        begin

          ret = yield(@rpc_client.get_proxy)
          failed = false

        # This looks funny, and is, but I double-catch in order
        # to handle remote exceptions, which extend exception but not
        # standarderror
        rescue SignalException => se
          raise se
        rescue Exception => e

          if e.is_a?(SimpleRPC::RemoteException)
            $log.error "Server reported error: #{e}"
          else
            $log.error "Local error during RPC call: #{e}"
          end

          $log.debug "#{e.backtrace.join("\n")}"
          failed = true

          $log.warn "#{retries} retries remaining before disconnection..." if retries > 0

          # Delay longer on failure
          @rpc_delay = Time.now + [rpc_delay_increment, @config[:network][:maximum_reconnect_time]].min
          rpc_delay_increment += @config[:network][:connect_failure_penalty]
        end
      end

      return ret
    end

    # Create this client's ID.
    # Must be persistent across instances, but not across machines.
    def generate_uuid
      require 'socket'
      # TODO: make this ID based more on IP address, and/or make it more readable
      @config[:client][:uuid_salt] + "_" + Digest::MD5.hexdigest("#{Socket.gethostname}#{@config[:client][:uuid_salt]}").to_s 
    end

    # Get a new cache to replace the one in the pool
    def new_cache
      # Create cache in a random filename in the dir specified
      filename = nil
      filename = File.join(@config[:client][:cache_dir], rand.hash.abs.to_s) if @config[:client][:cache_dir]

      $log.debug "Creating cache #{(@config[:client][:cache_dir] == nil) ? "in RAM" : "at #{filename}"}..."
      return Store.new(filename)
    end

    # Returns a string progress bar for use in output
    def progress_bar(total, progress, length=25)
      bar_len = ((progress.to_f / total.to_f) * length).round
      str = '['
      str += '=' * [bar_len, length].min
      str[-1] = '>' if bar_len > length
      str += ' ' * (length - [bar_len, length].min)
      str += ']'
    end

  end

end
