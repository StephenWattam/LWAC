require 'lwac/client/download_worker'
require 'lwac/client/file_cache'
require 'lwac/client/storage'

require 'lwac/shared/multilog'
require 'lwac/shared/identity'
require 'lwac/shared/serialiser'


require 'timeout'
require 'digest/md5'


require 'simplerpc/client'
require 'lwac/shared/data_types'  # for serialisation


module LWAC

  class DownloadClient
    def initialize(config)
      # Start up the client
      @config = config

      # Generate a UUID and ensure the workers know it
      generate_uuid

      # Reset the reconnection timer to minimum delay, then
      # compute the time before which we must not retry
      reset_reconnection_timer
      compute_reconnection_time
      @batch_request_delay  = Time.now  # don't recontact the server before this

      # Fire up el RPC client...
      @rpc_client = SimpleRPC::Client.new( @config[:server] ) 

      # Current working links and download policy
      @links        = {}
      @link_mutex   = Mutex.new


      # Create worker pool
      $log.info "Creating worker pool and starting work..."
      @pool = WorkerPool.new(@config[:client][:simultaneous_workers], new_pool_cache, 
                             @config[:client][:cache_limit] * 1024 * 1024, 
                             @config[:client][:strict_cache_limit], @uuid)
      @pool_thread = Thread.new(self){ |dispatcher| maintain_worker_pool(dispatcher) }

      # Should we really care about being able to contact the server?

      # Start the log with UUID info.
      $log.info "Client started with UUID: #{@uuid}"
    end

    # Contact the server for work, do it, then send it back ad infinitum.
    #
    # Raise SIGINT to stop.
    def work
      last_batch_size = 0

      loop{ 

        # Delay to stop us eating CPU when spinning
        sleep(@config[:client][:monitor_rate])

        if @config[:client][:announce_progress] then
          # TODO: major thread safety issue with links refs.
          progress = (@pool.cache_size.to_f / 1024.0 / 1024.0 ).round(2)
          pc_progress = ((progress / @config[:client][:cache_limit]) * 100)
          $log.info "*** #{progress_bar(@config[:client][:cache_limit], progress)} #{pc_progress.round}% #{progress}/#{@config[:client][:cache_limit]}MB (#{@links.length} pend, #{@pool.count_datapoints} cache, #{@pool.count_idle} idle) #{(@links.length == 0 && Time.now < @batch_request_delay) ? '[waiting]' : ''}"
        end

        # Run out of links
        if @links.length == 0 and Time.now > @batch_request_delay then
            # reports the number of links acquired
            acquire_batch
        end

        # Downloaded enough data already
        if (@pool.all_idle? and @pool.count_datapoints > 0) or @pool.cache_limit_reached? then
          # (@pool.cache_size.to_f / 1024.0 / 1024.0) > @config[:client][:cache_limit] then
          # Send completed points back to the server
          send_batch(@pool.get_datapoints( new_pool_cache ) )
        end

      }

    rescue SignalException => se
      $log.fatal "Caught signal!"

      $log.info "Contacting the server to cancel links..."
      cancel_batch

      @pool.summarise
      $log.info "Shutting down pool..."

      # Wait for the worker pool to die
      $log.info "Cleanly closing workers (may take a while)..."
      @pool.close
      @pool.wait

      # Remove the cache
      $log.info "Closing pool cache..."
      cache = @pool.get_datapoints( Store.new() )   #memory cache as a dummy object
      cache.close

      # Close caches
      $log.info "Done."
      return
    end

    # Returns an available link for one of the workers if requested
    # or nil if we're fresh out.
    def get_link
      l = nil
      @link_mutex.synchronize{
        id, l = @links.shift
      }
      return l
    end

  private

    # Actually download the links
    # This starts up a worker pool, and waits until they're done.
    def maintain_worker_pool(dispatcher)
      @pool.init_workers
      @pool.work(dispatcher)
    rescue SignalException => se
      $log.fatal "Caught signal!"

      # Clear up any worker threads and close their connections.
      if pool then
        $log.fatal "Currently processing links.  Killing workers..."
        pool.kill_workers
        $log.fatal "Done."
      end

      # Pass the exception up to halt the whole thing
      raise se
    end

    # Grab a batch of links from the server
    def acquire_batch
      $log.info "Requesting a new batch of #{@config[:client][:batch_capacity]} links..."

      loop do
        ret = connect do |s|
          s.check_out(LWAC::VERSION, @uuid, @config[:client][:batch_capacity])
        end

        # If the server tells us to back off, so do.
        if(ret.class == Fixnum)
          $log.info "Waiting for #{ret}s until #{Time.now + ret} at the server's request before requesting new batch"
          @batch_request_delay = Time.now + [ret, @config[:network][:maximum_reconnect_time]].min
          return 
        elsif(ret.class == Array and ret.length == 2)

          # Load the worker config into the list
          policy, links = ret
          @link_mutex.synchronize{
            links.each{ |l|
              @links[l.id] = {:link => l, :config => policy}
            }
          }
          $log.info "Received #{links.length}/#{@config[:client][:batch_capacity]} links from server."
          return links.length
        else
          $log.warn "Received unrecognised return from server of type: #{ret.class}.  Retrying..."
          $log.debug "Server said: '#{ret}'"
          increment_reconnection_timer
        end
      end

      return nil
    end

    # Send the batch of datapoints we have currently.
    # Sends in "chunks" of :check_in_rate 
    def send_batch(datapoints)
      while(datapoints.length > 0) do
        @pending = []

        # Take them out of the pstore up to a given size limit, then send that chunk
        pending_size = 0.0
        $log.debug "Counting data for upload..."
        while(datapoints.length > 0 and pending_size < @config[:client][:check_in_size]) do
          key = datapoints.keys[0]
          dp = datapoints[key]
          pending_size += dp.response_properties[:downloaded_bytes].to_f / 1024.0 / 1024.0 
          @pending << dp
          datapoints.delete_from_index(key)
        end

        # send datapoints
        $log.info "Sending #{@pending.length} datapoints (~#{pending_size.round(2)}MB) to server..."
        connect do |s|
          s.check_in(LWAC::VERSION, @uuid, @pending)
        end
        $log.debug "Done."
      end

      # Here datapoints.length == 0, so wipe the cache
      datapoints.delete_all

      
    rescue SignalException => se
      $log.fatal "Caught signal during upload."
      $log.info "Closing upload cache..."
      # remove the cache
      datapoints.close
      raise se
    end

    # Cancel the batch of links we currently have checked out.
    # This atomically aborts these links and frees them up for other clients.
    def cancel_batch
      # return if(@links.class == Fixnum) # just in case we bail whilst waiting
   
      if @links.empty?
        $log.info "No links to cancel." 
        return
      end

      $log.info "Cancelling at least #{@links.length} links."
      connect do |s|
        s.cancel(LWAC::VERSION, @uuid)
      end

    end

    # Connect to the server, using backoff as described in the config file
    def connect(&block)
      $log.debug "Connecting to server #{@config[:server][:address]}:#{@config[:server][:port]}..."

      while(not @rpc_client.connected?) do
        begin

          # Check reconnect timer and delay if it tells us to
          if @rc_time > Time.now.to_i then
            $log.info "Rate limiting self for #{@rc_time - Time.now.to_i}s until #{Time.at(@rc_time)}..."
            sleep(@rc_time - Time.now.to_i)
          end


          # Attempt to connect with the connect_timeout set
          Timeout::timeout(@config[:network][:connect_timeout]){
            @rpc_client.connect
          }

        # On error
        rescue StandardError => e
          
          # Network Errors
          case e
          when SimpleRPC::AuthenticationError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH
            increment_reconnection_timer
          else
            # Continue to pass error up
            raise e
          end
          
          # Compute reconnection time
          compute_reconnection_time

          # Warn the user and wait until it's time to try again
          $log.warn "Failed to connect (#{e})."
        end
      end

      compute_reconnection_time

      # Start doing things!  Register as a client
      $log.debug "Done.  Yielding to perform actions."

      # Then yield the service to our caller
      response = nil
      begin
        response = yield(@rpc_client)
      rescue StandardError => e
        $log.error "Error during operation: #{e}"
        $log.debug e.backtrace.join("\n")
      ensure
        # When done, disconnect
        @rpc_client.disconnect
        $log.debug "Disconnected."
      end

      # success means...
      reset_reconnection_timer

      return response
    end


    # Get a new cache to replace the one in the pool
    def new_pool_cache
      # Create cache in a random filename in the dir specified
      filename = nil
      filename = File.join(@config[:client][:cache_dir], rand.hash.abs.to_s) if @config[:client][:cache_dir]

      $log.info "Creating cache #{(@config[:client][:cache_dir] == nil) ? "in RAM" : "at #{filename}"}"
      return Store.new(filename)
    end


    # Create this client's ID.  
    # Must be persistent across instances, but not across machines.
    def generate_uuid
      require 'socket'
      # TODO: make this ID based more on IP address, and/or make it more readable
      @uuid = @config[:client][:uuid_salt] + "_" + Digest::MD5.hexdigest("#{Socket.gethostname}#{@config[:client][:uuid_salt]}").to_s 
    end

    # Increase reconnect timer gradually up to the limit set in the config file
    # Called when any call fails
    def increment_reconnection_timer
      @reconnect_timer = [@reconnect_timer + @config[:network][:connect_failure_penalty], @config[:network][:maximum_reconnect_time]].min
    end

    # Reset the reconnection timer
    def reset_reconnection_timer
      @reconnect_timer = @config[:network][:minimum_reconnect_time]
    end

    # Calculate the time we are next allowed to contact the server
    def compute_reconnection_time 
      # Reset the backoff timer now we have connected successfully
      @rc_time    = Time.now.to_i + @reconnect_timer
    end

    # Returns a string progress bar for use in output
    def progress_bar(total, progress, length=25)
      bar_len = ((progress.to_f / total.to_f) * length).round
      str = '['
      str += '=' * [bar_len, length].min
      str[-1] = ">" if bar_len > length
      str += ' ' * (length - [bar_len, length].min)
      str += ']' 
    end

  end


end
