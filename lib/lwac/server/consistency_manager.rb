require 'yaml'
require 'thread'
require 'set'
require "lwac/shared/data_types"
require "lwac/shared/multilog"
require "lwac/server/storage_manager"

module LWAC

  # Wraps storage and link policies to enforce efficient workflow
  # with regards links
  #
  # Provides facilities for the following:
  #
  # 1) Read current state from files
  # 2) Create a new sample.  Read links from the db for that sample
  # 3) Write datapoints and whilst keeping track of the link IDs to ensure all are done.
  # 4) Close a sample and ensure everything is complete before opening another
  #
  #
  # This can be thought of as the server's API.  It wraps all other server functions.
  class ConsistencyManager

    def initialize(config)
      @storage    = StorageManager.new(config[:storage])
      @state      = @storage.state
      @mutex      = Mutex.new
      @config     = config[:sampling_policy]

      # Two lists to handle link checkout
      @links      = @state.current_sample.pending
      @checked_out_links = {}


      # Print handy messages to people
      if(@state.last_sample_id == -1)
        $log.info "No sampling has occurred yet, this is a new deployment."
        open_sample # Bootstrap the sample
      end

      # Print more handy messages to people
      if(not @state.current_sample.open? and @state.current_sample.complete?)
        $log.info "Current sample is closed and complete.  Opening a new one..."
        open_sample
      end

      $log.info "Current sample: #{@state.current_sample}."
      if(@state.current_sample.open?) 
        # Prevents the server completing a sample even if already open...
        # check_sample_limit
        $log.info "Sample opened at #{@state.current_sample.sample_start_time}, resuming..."
      else
        if(wait <= 0)
          $log.info "Sample is closed but ready to open."
        else
          $log.info "Sample closed: wait #{wait}s before sampling until #{Time.now + wait}."
        end
      end

    end

    def counts
      start_time = (@state.current_sample) ? @state.current_sample.sample_start_time : nil
      return @checked_out_links.values.length, 
             @state.current_sample.size, 
             @state.current_sample.progress, 
             start_time,
             @links.length
    end


    # Retrieve links
    def check_out(number = :all)
      raise "Cannot check out links.  Wait #{wait}s until #{Time.now + wait}." if wait > 0
      if not @state.current_sample.open? then
        @state.current_sample.open_sample 
        @storage.write_sample 
      end

      links = []
      @mutex.synchronize{
        number = @state.remaining if number == :all

        # Check out links and reserve them
        $log.debug "Checking out #{number}/#{@state.current_sample.remaining} links."

        # If the cache isn't large enough, read more from the DB
        if @links.length < number then
          $log.debug "Reading #{number-@links.length} links from database (id > #{@state.current_sample.last_dp_id})"

          # Read from DB
          ids = @storage.read_link_ids(@state.current_sample.last_dp_id.to_i, (number - @links.length))

          # increment the last count or keep it the same if there were no returns
          @state.current_sample.last_dp_id = (ids.max || @state.current_sample.last_dp_id)

          # put in the links list
          @links += ids
        end

        # then assign from @links
        count = 0
        select = @links.classify{ ((count+=1) <= number) }

        # put back the ones we don't want
        @links = select[false] || Set.new

        # grab the ones we do and get them from the db
        links = @storage.read_links( select[true].to_a )

        # then pop them in the checkout list
        links.each{|l|
          @checked_out_links[l.id] = l
        }

        # @links.each{|id|
        #   break if (count+=1) > number
        #   # Read from DB
        #   link = @storage.read_link(id)
        #   # Add to the list of recorded checkec out ones
        #   @checked_out_links[id] = link
        #   # add to the list to return
        #   links << link
        #   # and delete from the pending list
        #   @links.delete(id)
        # }

        $log.debug "Done."
      }

      $log.debug "Total memory cache usage: #{@checked_out_links.length + @links.length} links"

      # TODO: exception handling.
      return links
    end 

    # Check links in without converting them to datapoints.  This doesn't
    # affect data consistency beyond making it possible to guarantee
    # that we don't duplicate or omit
    def uncheck(links = [])
      @mutex.synchronize{
        links.each{|l|
          id = l.id if l.class == Link
          
          raise "Attempt to uncheck a link that is not checked out" if not @checked_out_links.delete(id)
          @links << id 
        }
      }
    end

    # Check links in, write the return to disk
    def check_in(datapoints = [])
      raise "Cannot check in whilst waiting.  Wait #{wait}s until #{Time.now + wait}." if wait > 0

      @mutex.synchronize{
        # Check in each datapoint
        $log.debug "Checking in #{datapoints.length} datapoints."
        datapoints.each{|dp|
          if(@checked_out_links.delete(dp.link.id))
            @storage.write_datapoint(dp)

            # increment the progress counter
            @state.current_sample.link_complete( dp.response_properties[:downloaded_bytes] || 0 )
            
            # They shouldn't even be in the list below, hence it being commented out.
            #@links.delete(dp.link.id)
          else
            $log.warn "Attempted to check in link with ID #{dp.link.id}, but the sample says it's already been done."
          end
        }

        # Close the sample if we detect that we're done
        if(@state.current_sample.complete?)
          $log.info "Current sample complete."
          close_sample
        end
      }
    end

    # Calculate how long we have until the sample is "openable"
    def wait
      @mutex.synchronize{
        (@state.next_sample_due - Time.now.to_i).ceil
      }
    end

    # Close the resource neatly.
    def close
      $log.debug "Closing consistency manager by unchecking #{@checked_out_links.values.length} links."

      # un-check-out all checked-out links
      uncheck(@checked_out_links.values)
      @state.current_sample.pending = @links


      # Close storage manager
      @storage.close
    end

  private

    # Compute the next sample time
    def compute_next_sample_time
      # First, round down to whatever period people want
      time = Time.at(((Time.now.to_i / @config[:sample_time]).floor * @config[:sample_time]) + @config[:sample_alignment])

      # Then jump forward until the next point in the future
      while(time < Time.now)
        time += (@config[:sample_time])
      end
      return time.to_i
    end

    # Close a sample and open a new one.
    def close_sample
      # Write sample end time
      @state.last_sample_duration             = (Time.now - @state.current_sample.sample_start_time).round
      @state.current_sample.close_sample                     

      $log.info "*** Closing sample #{@state.current_sample}"
      $log.info "Sample duration: #{@state.last_sample_duration.round}s, size: #{(@state.current_sample.approx_filesize / 1024 / 1024).round(2)}MB"

      # Write sample to disk
      @storage.write_sample(@state.current_sample)

      # Open the next sample.
      open_sample()
    end

    # Open a new sample with or without closing the old one (used as bootstrap)
    def open_sample
      check_sample_limit

      # Increment sample
      @state.last_sample_id         = @state.current_sample.id
      @state.current_sample         = Sample.new(@state.current_sample.id.to_i + 1, @storage.count_links)
      @links                        = @state.current_sample.pending  # XXX why?... Ensure we take a copy, don't go editing the sample
      @state.next_sample_due        = compute_next_sample_time
      
      # Tell people
      $log.info "*** Opened new sample to commence on #{Time.at(@state.next_sample_due)}"
      $log.info "Estimated completion time: #{Time.at(@state.next_sample_due.to_i + @state.last_sample_duration.to_i)}"
     
      # Ensure we don't lose it if we're forced to close 
      @storage.update_state(@state)
    end

    # Check against the config's sample limit, and raise sigint to stop if so.
    def check_sample_limit
      if @state.current_sample and @config[:sample_limit] and @config[:sample_limit].to_i > 0 and (@state.current_sample.id.to_i + 1) > @config[:sample_limit]  then
        $log.fatal "*** Sample limit (#{@config[:sample_limit]}) reached.  Shutting down..."
        raise SignalException.new('SIGTERM')
      end
    end
  end
  # 
  # # Test script.
  # if(__FILE__ == $0) then
  #   $log = MultiOutputLogger.new($stdout)
  #   $log.set_level(:debug)
  #   config = YAML.load_file("./config/server.yml")
  #   cm = ConsistencyManager.new(config)
  # end
  # 
end
