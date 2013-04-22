
require 'lwac/shared/multilog'
require 'lwac/shared/identity'
require 'lwac/server/consistency_manager'
require 'lwac/server/serialiser'
require 'lwac/server/storage_manager'

# Load marilyn, eventmachine gems
require 'marilyn-rpc'
require 'eventmachine'

module LWAC

  class DownloadServer
    def initialize(config)
      @config       = config
      @dispatched   = {}  # links checked out to clients
      @cm           = ConsistencyManager.new(config)

      @timeouts     = {}  # timeout threads for clients
      @rates        = {}  # estimates for how fast clients are
    end

    # Returns either a list of Link objects or a delay to wait for (FixNum)
    def check_out(client_id, request)
      links = nil

      $log.info "Client #{client_id} wishes to check out #{request} links."

      # Tell the client to wait if the CM says to wait.
      if(@cm.wait > 0)
        $log.info "Telling client to wait #{@cm.wait + @config[:client_management][:delay_overestimate]} seconds."
        return @cm.wait + @config[:client_management][:delay_overestimate]
      end

      # Check it has a hash to make everything else easier
      @dispatched[client_id]  = {} if not @dispatched[client_id]  

      # If the client has already been allocated links
      if(@dispatched[client_id].values.length > 0)
        $log.debug "Client #{client_id} already has some links checked out.  Will re-issue these instead."
        links = @dispatched[client_id].values
      else
        # Else, check out some new ones
        links = @cm.check_out(request)
        links.each{|l|
          @dispatched[client_id][l.id] = l
        }
      end

      # If we found no links
      if(links.length == 0)
        # We found no links, so tell the client to wait until one of the others may have failed.
        $log.info "Found no links for the client.  Told it to wait #{@config[:client_management][:empty_client_backoff]}s."
        return @config[:client_management][:empty_client_backoff]
      end


      # Kill any old timeouts if the client tries to check out twice
      @timeouts[client_id].kill if @timeouts[client_id]

      # Register the new timeout and start a thread to call its cancel method
      timeout = estimate_client_timeout(client_id, @dispatched[client_id].length)
        # (@config[:client_management][:time_per_link] * @dispatched[client_id].length)
      @timeouts[client_id] = Thread.new{ 
        sleep(timeout)
        cancel_timeout(client_id)
      }

      # Ensure the rate computer knows it's got work
      register_checkout_rate(client_id)

      $log.info "Dispatched #{@dispatched[client_id].length} link[s], timeout #{timeout.round(1)}s (#{Time.now + timeout})"

      summary

      return [@config[:client_policy], links]
    end

    # Returns either a list of link objects or nil to delete them
    def check_in(client_id, datapoints)
      $log.info"Client #{client_id} checking in #{datapoints.length} datapoint[s]..."

      # Check we have actually checked them out
      check_in_list = []
      erroneous     = 0
      datapoints.each{|dp|
        if(@dispatched[client_id] and @dispatched[client_id].values.map{|l| l.id}.include? dp.link.id) then
          $log.debug "Adding #{dp} to check-in list"
          check_in_list << dp
          @dispatched[client_id].delete(dp.link.id)
        else
          erroneous += 1 
        end
      }

      $log.error "Failed to check in #{erroneous} datapoint[s] which were not checked out to him." if erroneous > 0

      # Prevent the timeout firing
      if(@dispatched[client_id] and @dispatched[client_id].length == 0) then
        @timeouts[client_id].kill if @timeouts[client_id]
        @timeouts[client_id] = nil
      end

      # Estimate client's work rate based on the amount it's done.
      compute_client_rate(client_id, check_in_list.length)

      # then check them in
      @cm.check_in(check_in_list)

      $log.debug "Check in complete"
      
      summary
    end

    # Returns nil
    def cancel(client_id)
      if(@dispatched[client_id]) then
        $log.info "Client #{client_id} is cancelling #{@dispatched[client_id].values.length} link[s]..." 

        # Uncheck the item from the consistency manager
        @cm.uncheck(@dispatched[client_id].values) if(@dispatched[client_id])

        # Then blank this client's list
        @dispatched[client_id] = {} 

        # Prevent any timeout firing
        @timeouts[client_id].kill if @timeouts[client_id]
        @timeouts[client_id] = nil


        $log.debug "Cancel complete"
      else
        $log.error "Client #{client_id} attempted to cancel links it does not have checked out."
      end
      
      summary
    end


    # Close all resources and get ready to quit
    def close
      $log.fatal "Closing DownloadServer cleanly..."
      @cm.close
      $log.fatal "Done."
    end

  private

    # Record the last time the client asked for work
    def register_checkout_rate(client_id)
      @rates[client_id] = Time.now
    end

    # Transform the time in the rates listing to a rate,
    # based on the time the client last asked for work
    def compute_client_rate(client_id, num_links)
      if @rates[client_id].is_a?(Time) then
        @rates[client_id] = num_links / (Time.now - @rates[client_id]).to_f
        $log.debug "Client #{client_id} is working at #{@rates[client_id].round(2)} links/s"
      end
    end

    # Use past experience to compute a timeout for a given client
    def estimate_client_timeout(client_id, link_count)
      $log.debug "Estimating client timeout..."
      if @rates[client_id].is_a?(Numeric) then
        return (@rates[client_id] * link_count) * @config[:client_management][:dynamic_time_overestimate].to_f
      end

      # Fall back on the old system
      return (@config[:client_management][:time_per_link] * link_count)
    end

    # The client has not got back to us, so revoke its links
    def cancel_timeout(client_id)
      if(@dispatched[client_id]) then
        # Alert the user
        $log.warn "Client #{client_id} hasn't been heard from for a while..."
        $log.warn "Cleaning up link assignments for dead client #{client_id}."

        # Uncheck the item from the consistency manager
        @cm.uncheck(@dispatched[client_id].values) if(@dispatched[client_id])

        # Then blank this client's list
        @dispatched[client_id] = {} 
        $log.debug "Done."
      else
        $log.warn "Client #{client_id} cleaned its own links before disconnecting.  This is usually a sign it has caught a signal."
      end
    
      @timeouts[client_id] = nil
    end

    # Present a list of clients and their checked out links.
    def summary
      co, sample, done, stime, cached = @cm.counts
      remain = sample - done


      # Debug info
      str = ["CM: #{co}/#{sample} checked out (#{remain} remaining)."]
      str << "Summary of Clients:"
      c = 0
      @dispatched.each{|client, links|
        str << "  (#{c+=1}/#{@dispatched.keys.length}) #{client} => #{links.values.length} links."
      }
      str.each{|s| $log.debug s }


      # Say progress
      $log.info "#{co} / #{cached} / #{done} / #{sample} links checked out/cached/complete/total (#{((done).to_f/sample.to_f * 100.0).round(2)}%)."

      # Compute ETA
      if stime and done > 0
        tdiff = Time.now.to_i - (stime || Time.at(0)).to_i
        if tdiff > 0 then
          rate  = done.to_f / tdiff.to_f 
          eta   = Time.now + (remain / rate).to_i
          $log.info "ETA for this sample: #{eta} (#{rate.round(1)} links/s, #{(rate * 60*60).round} links/hr)"
        end
      end

    end


  end


  # FIXME: avoid using a global for the server.

  class DownloadService < MarilynRPC::Service
    # TODO: make this configurable
    register :lwacdownloader
    
    # Ensure we handle only one thing at once
    MUTEX = Mutex.new

    #def test(client_id, payload)
      #MUTEX.synchronize{
        #$log.info "Received test from #{client_id}"
        #$log.info "Payload: #{payload.to_s}"
      #}
    #rescue StandardError => e
      #$log.error "Exception: #{e}"
      #$log.debug e.backtrace.join("\n")
    #end

    # Send links to a user, and keep track of who asked for them
    def check_out(version, client_id, number_requested)
      version_check(version)
      MUTEX.synchronize{
        $server.check_out(client_id, number_requested)
      }
    rescue StandardError => e
      $log.error "Exception: #{e}"
      $log.debug e.backtrace.join("\n")
      return []
    end
    
    # Accept datapoints back from the user
    def check_in(version, client_id, datapoints)
      version_check(version)
      MUTEX.synchronize{
        $server.check_in(client_id, datapoints)
      }
    rescue StandardError => e
      $log.error "Exception: #{e}"
      $log.debug e.backtrace.join("\n")
      return nil
    end

    # Cancel links ahead of time
    def cancel(version, client_id)
      version_check(version)
      MUTEX.synchronize{
        $server.cancel(client_id)
      }
    rescue StandardError => e
      $log.error "Exception: #{e}"
      $log.debug e.backtrace.join("\n")
      return nil
    end

  private

    # Check version is compatible
    def version_check(ver)
      raise "Client rejected: incompatible version '#{ver}'" if not Identity::network_is_compatible?(ver)
    end
  end



end

