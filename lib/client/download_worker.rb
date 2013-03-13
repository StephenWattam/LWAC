
require 'thread'
require 'curl'
# Load the library for producing UUIDs
require 'digest/md5'




# -----------------------------------------------------------------------------------------------------
class Worker
  def initialize(id, config)
    @id     = id

    # Set up curl
    @c = Curl::Easy.new
    @c.unrestricted_auth = true

    # TODO: make this configurable (it already is, but still...)
    @c.ssl_verify_peer = false
    @c.ssl_verify_host = false
    config.each{|k, v|
      eval("@c.#{k} = #{v}")
    }

    @abort = false
  end

  # Should be run in a thread.  Performs work until the dispatcher runs out of data.
  def work(dispatcher)
    while(link = dispatcher.get_link) do
      $log.debug "W#{@id}: Downloading link #{link.id}: #{link.uri}"
      @c.url = link.uri
      dispatcher.complete_request(@id, link, @c)

      return if(@abort)
      #puts "STUB: worker #{@id} given job from dispatcher #{dispatcher}"
    end
  end

  # Closes the connection to the server
  def close
    @abort = true
  end
end











# -----------------------------------------------------------------------------------------------------
class WorkerPool
  def initialize(config, links)
    @m    = Mutex.new # Data mutex for "producer" status
    @t    = [] #threads
    @w    = [] # workers

    # Keep a copy of the config object
    @config = config

    @l    = links   # links
    @dp   = []      # datapoints
    @dpm  = Mutex.new # databse mutex for datapoint list

    # stat]
    # Counts for the session.
    # These are mere metadata, and are stored in parallel
    # to the main http response results (written to disk)
    @count_200   = 0
    @count_404   = 0
    @count_other = 0
    @complete    = 0
    @errors      = 0
    @global_stats_mutex = Mutex.new
  
  end

  # Gets a single point from the list, and deletes it.  Thread safe.
  def get_link
    l = nil
    @m.synchronize{
      l = @l[0]
      @l.delete_at(0)
    }
    return l
  end

  # Run a worker over every point competitively
  def work
    # Make things do the work
    $log.debug "Starting threads..."
    @w.each{|w|
      # Give each worker a handle back to the dispatcher to get data.
      @t << Thread.new(w, self){|w, d|
        w.work(d)
      }
    }
    $log.info "#{@w.length} download thread[s] started."
  end

  # Wait for threads to complete.
  def wait
    $log.debug "Waiting for #{@t.length} worker[s] to close."
    @t.each{|t| t.join}
    $log.info "Workers all terminated naturally."
  end

  def wait_and_get_datapoints
    wait
    return @dp
  end


  # Summarise the progress after a sample.
  def summarise
    $log.info "Queue complete."
    $log.info "  Response:"
    $log.info "    200    : #{@count_200}"
    $log.info "    404    : #{@count_404}"
    $log.info "    other  : #{@count_other}"
    $log.info "  Errors   : #{@errors}"
    $log.info "  Complete : #{@complete}"
  end

  def kill_workers
    $log.debug "Forcing #{@t.length} worker threads to die..."
    @t.each{|t|
      t.kill
    }
    $log.info "Worker threads killed."
  end

  # Close all workers' connections to the servers
  def close
    $log.debug "Requesting closure of #{@w.length} worker[s]."
    @w.each{|w|
      w.close
    }
    $log.info "Workers closed by request."
  end
   
  # Create and connect the workers to servers 
  def init_workers
    $log.debug "Creating #{@config[:simultaneous_workers]} worker object[s]."
    @w = []
    @config[:simultaneous_workers].times{|s|
      @w << Worker.new(s, @config[:curl_workers])
    }
    $log.info "#{@w.length} worker[s] created."
  end

  # On user request, set the string encoding to something and provide policy for its fixes
  def fix_encoding(str)
    return str if not @config[:fix_encoding]
    return str.encode(@config[:target_encoding], @config[:encoding_options])
  end

  # Some kind of callback.
  def complete_request(worker_id, link, res)
      # Perform a request prepared elsewhere,
      # can run alongside other requests
      res.perform

      # Output the result to debug log
      $log.debug "W#{worker_id}: Completed request #{link.id}, response code #{res.response_code}."

      # Generate a hash of headers
      headers = DataPoint.headers_to_hash(fix_encoding(res.header_str))

      # Load stuff out of response object.
      encoding            = headers["Content-Type"].to_s
      response_properties = {:round_trip_time   => res.total_time,
                             :redirect_time     => res.redirect_time,
                             :dns_lookup_time   => res.name_lookup_time,
                             :effective_uri     => fix_encoding(res.last_effective_url.to_s),
                             :code              => res.response_code}
      body                = @config[:body_not_text_placeholder] if encoding.length > 0 and not ((encoding =~ /^text\/?.*$/i) != nil)


      body                = fix_encoding(res.body_str)
      head                = fix_encoding(res.header_str)


      # write to datapoint list
      @dpm.synchronize{
        @dp << DataPoint.new(link, headers, head, body, response_properties, @config[:client_uuid], nil)
      }
      
      # Update stats counters.
      @global_stats_mutex.synchronize{
        case res.response_code
          when 200 then @count_200   += 1
          when 404 then @count_404   += 1
          else          @count_other += 1
        end
        @complete += 1
      }


    rescue SignalException => se
      $log.fatal "Signal caught: #{e.message}"
      $log.fatal "Since I'm sampling right now, this will be cancelled and passed back."
      kill_workers
      raise se
    rescue Exception => e
      $log.error "W#{worker_id}: Error in link #{link.id}: #{e.to_s}."

      # write to datapoint list
      @dpm.synchronize{ 
        @dp << DataPoint.new(link, "", "", "", {}, @config[:client_uuid], "#{e}") 
      }

      # update the counter.
      @global_stats_mutex.synchronize{ @errors += 1 }
  end
end



