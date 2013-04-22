require 'lwac/client/download_worker'
require 'lwac/client/file_cache'
require 'lwac/client/storage'

require 'lwac/shared/multilog'
require 'lwac/shared/identity'


require 'marilyn-rpc'
require 'eventmachine'
require 'yaml'
require 'timeout'
require 'digest/md5'

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


      # Current working links and download policy
      @policy       = {}
      @links        = []

      $log.info "Creating cache #{(@config[:client][:cache_file] == nil) ? "in RAM" : "at #{@config[:client][:cache_file]}"}"
      @datapoints   = Store.new(@config[:client][:cache_file])

      # Should we really care about being able to contact the server?
      @shutdown     = false

      # Start the log with UUID info.
      $log.info "Client started with UUID: #{@uuid}"
    end

    # Contact the server for work, do it, then send it back ad infinitum.
    #
    # Raise SIGINT to stop.
    def work
      loop do 
        # Get a batch from the server
        acquire_batch

        # Process
        process_links 

        # Send completed points back to the server
        send_batch
      end

    rescue SignalException => se
      $log.fatal "Caught signal!"
      @shutdown = true
      $log.fatal "Contacting the server to cancel links..."
      cancel_batch
      $log.fatal "Done."
      return
    end



  private

    # Actually download the links
    # This starts up a worker pool, and waits until they are done.
    def process_links
      $log.info "Creating worker pool and starting work..."
      $log.warn "Server requested a dry run.  No actual work will be done" if @config[:client][:dry_run]
      pool = WorkerPool.new(@config[:client][:simultaneous_workers], @policy, @datapoints, @uuid, @links)
      pool.init_workers
      pool.work
      @datapoints = pool.wait_and_get_datapoints
      $log.info "Downloaded.  Checking in #{@datapoints.length} completed datapoint[s]..."
      @datapoints.each_key{|link_id| @links.delete(link_id) }
      pool.summarise
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
      $log.info "Applying for a new batch of #{@config[:client][:batch_capacity]} links..."

      loop do
        ret = connect do |s|
          s.check_out(Identity::VERSION, @uuid, @config[:client][:batch_capacity])
        end

        # If the server tells us to back off, so do.
        if(ret.class == Fixnum)
          $log.info "Waiting for #{ret}s until #{Time.now + ret} at the server's request."
          sleep([ret, @config[:network][:maximum_reconnect_time]].min)
        elsif(ret.class == Array and ret.length == 2)
          @policy, @links = ret
          $log.info "Received #{@links.length}/#{@config[:client][:batch_capacity]} links from server."
          return
        else
          $log.warn "Received unrecognised return from server of type: #{@links.class}.  Retrying..."
          $log.debug "Server said: '#{ret}'"
          increment_reconnection_timer
        end
      end
    end

    # Send the batch of datapoints we have currently.
    # Sends in "chunks" of :check_in_rate 
    def send_batch
      while(@datapoints.length > 0) do
        @pending = []

        # Take them out of the pstore up to a given size limit, then send that chunk
        pending_size = 0.0
        $log.debug "Counting data for upload..."
        while(@datapoints.length > 0 and pending_size < @config[:client][:check_in_size]) do
          key = @datapoints.keys[0]
          dp = @datapoints[key]
          pending_size += dp.response_properties[:downloaded_bytes].to_f / 1024.0 / 1024.0 #(Marshal.dump(dp).length.to_f / 1024.0 / 1024.0)
          @pending << dp
          @datapoints.delete_from_index(key)
        end

        # send datapoints
        $log.info "Sending #{@pending.length} datapoints (~#{pending_size.round(2)}MB) to server..."
        connect do |s|
          s.check_in(Identity::VERSION, @uuid, @pending)
        end
        $log.debug "Done."
      end

      # Here datapoints.length == 0, so wipe the cache
      @datapoints.delete_all
    end

    # Cancel the batch of links we currently have checked out.
    # This atomically aborts these links and frees them up for other clients.
    def cancel_batch
      return if(@links.class == Fixnum) # just in case we bail whilst waiting


      if not @datapoints.empty? 
        $log.info "Deleting local datapoints from cache..."
        @datapoints.each_key{|k|
          @links << k
        }
        @datapoints.close
      end

      if @links.empty?
        $log.info "No links to cancel." 
        return
      end

      $log.info "Cancelling at least #{@links.length} links."
      connect do |s|
        s.cancel(Identity::VERSION, @uuid)
      end

    end

    # Connect to the server, using backoff as described in the config file
    def connect(&block)
      $log.debug "Connecting to server #{@config[:server][:address]}:#{@config[:server][:port]}..."

      client = nil
      while(not client) do
        begin

          # Check reconnect timer and delay if it tells us to
          if @rc_time > Time.now.to_i then
            $log.info "Rate limiting self for #{@rc_time - Time.now.to_i}s until #{Time.at(@rc_time)}..."
            sleep(@rc_time - Time.now.to_i)
          end


          # Attempt to connect with the connect_timeout set
          Timeout::timeout(@config[:network][:connect_timeout]){
            client = MarilynRPC::NativeClient.connect_tcp( @config[:server][:address], @config[:server][:port] )
          }

        # On error
        rescue StandardError => e
          
          # Simply quit if we have been told to shut down
          return if @shutdown

          # Network Errors
          case e
          when Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH
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
      download_service = client.for(:lwacdownloader)
      $log.debug "Done.  Yielding to perform actions."

      # Then yield the service to our caller
      response = nil
      begin
        response = yield(download_service)
      rescue SignalException => e
        raise e
      rescue Exception => e
        $log.error "Error during operation: #{e}"
        $log.debug e.backtrace.join("\n")
      ensure
        # When done, disconnect
        client.disconnect
        $log.debug "Disconnected."
      end

      return response
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

  end


end
