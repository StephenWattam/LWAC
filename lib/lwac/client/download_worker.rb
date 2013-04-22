
require 'thread'
require 'curl'
# Load the library for producing UUIDs
require 'digest/md5'
require 'lwac/client/storage'

module LWAC

  # -----------------------------------------------------------------------------------------------------
  class Worker
    def initialize(id, config)
      @id     = id
      @config = config
      @abort = false
    end

    # Should be run in a thread.  Performs work until the dispatcher runs out of data.
    def work(dispatcher)
      while(link = dispatcher.get_link) do
        $log.debug "W#{@id}: Downloading link #{link.id}: #{link.uri}"

        dispatcher.complete_request(@id, link, new_curl(link.uri))

        return if(@abort)
        #puts "STUB: worker #{@id} given job from dispatcher #{dispatcher}"
      end
    end

    # Closes the connection to the server
    def close
      @abort = true
    end

  private
    def new_curl(uri)
      # Set up curl
      c = Curl::Easy.new

      # TODO: make this configurable (it already is, but still...)
      c.unrestricted_auth = true
      c.ssl_verify_peer = false
      c.ssl_verify_host = false

      @config.each{|k, v|
        eval("c.#{k} = #{v}")
      }

      # Set URI
      c.url = uri

      return c
    end
  end











  # -----------------------------------------------------------------------------------------------------
  class WorkerPool
    def initialize(size, config, cache, client_id, links)
      @m    = Mutex.new # Data mutex for "producer" status
      @t    = [] #threads
      @w    = [] # workers
      @size = size.to_i # number of simultaneous workers
      @client_id = client_id      # Who am I working on behalf of?

      # Keep a copy of the config object
      @config = config

      @l    = links   # links
      @dp   = cache      # datapoints

      # stat]
      # Counts for the session.
      # These are mere metadata, and are stored in parallel
      # to the main http response results (written to disk)
      @count_200   = 0
      @count_404   = 0
      @count_other = 0
      @complete    = 0
      @errors      = 0
      @bytes       = 0
      @start_time  = 0
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
      @start_time = Time.now
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
      @end_time = Time.now
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

      if @start_time and @end_time then
        rate = @bytes*8 / (@end_time - @start_time)
        $log.info "Downloaded #{(@bytes.to_f / 1024.0 / 1024.0).round(2)}MB in #{(@end_time - @start_time).round}s (#{(rate / 1024 / 1024).round(2)}Mbps)"
      end
    end

    def kill_workers
      $log.debug "Forcing #{@t.length} worker threads to die..."
      @t.each{|t|
        t.kill
      }
      @end_time = Time.now
      $log.info "Worker threads killed."
    end

    # Close all workers' connections to the servers
    def close
      $log.debug "Requesting closure of #{@w.length} worker[s]."
      @w.each{|w|
        w.close
      }
      @end_time = Time.now
      $log.info "Workers closed by request."
    end
     
    # Create and connect the workers to servers 
    def init_workers
      $log.debug "Creating #{@size} worker object[s]."
      @w = []
      @size.times{|s|
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

        # Somewhere to store the body in a size-aware way
        body = ""
        ignore = false

        res.on_body{|str|
          # Read up to the limit of bytes
          if not ignore and (body.length + str.length) > @config[:max_body_size] then
            body += str[0..(body.length + str.length) - @config[:max_body_size]]
            $log.warn "W#{worker_id}: Link #{link.id} exceeded byte limit (#{@config[:max_body_size]}b)"
            ignore = true
          elsif not ignore
            body += str
          else
            # ignore data
          end

          # Have to return number of bytes to curb
          str.length
        }

        # Perform a request prepared elsewhere,
        # can run alongside other requests
        res.perform if not @config[:dry_run]

        # Output the result to debug log
        $log.debug "W#{worker_id}: Completed request #{link.id}, response code #{res.response_code}."

        # Fix encoding of head if required
        $log.debug "Fixing header encoding..."
        head                = fix_encoding(res.header_str.to_s)

        # Generate a hash of headers
        $log.debug "W#{worker_id}: Parsing headers..."
        headers = DataPoint.headers_to_hash(head)


        # Per-regex MIME handling 
        $log.debug "W#{worker_id}: Passing MIME filter in #{@config[:mimes][:policy]} mode..."
        allow_mime = (@config[:mimes][:policy] == :blacklist)
        encoding   = headers["Content-Type"].to_s
        @config[:mimes][:list].each{|mime_rx|
          if encoding.to_s =~ Regexp.new(mime_rx, @config[:mimes][:ignore_case]) then
            allow_mime = (@config[:mimes][:policy] == :whitelist)
            $log.debug "W#{worker_id}: #{link.id} matched MIME regex #{mime_rx}"
          end
        }
        body                  = "" if not allow_mime


        # Normalise encoding (unless turned off)
        $log.debug "W#{worker_id}: Fixing body encoding..."
        body                = fix_encoding(body)


        # Load stuff out of response object.
        response_properties = {:round_trip_time   => res.total_time,
                               :redirect_time     => res.redirect_time,
                               :dns_lookup_time   => res.name_lookup_time,
                               :effective_uri     => fix_encoding(res.last_effective_url.to_s),
                               :code              => res.response_code,
                               :download_speed    => res.download_speed,
                               :downloaded_bytes  => res.downloaded_bytes || 0,
                               :encoding          => encoding,
                               :truncated         => ignore == true,
                               :mime_allowed      => allow_mime,
                               :dry_run           => @config[:dry_run]
                               }


        # write to datapoint list
        @dp[link.id] = DataPoint.new(link, headers, head, body, response_properties, @client_id, nil)
        
        # Update stats counters.
        @global_stats_mutex.synchronize{
          case res.response_code
            when 200 then @count_200   += 1
            when 404 then @count_404   += 1
            else          @count_other += 1
          end
          @complete += 1
          @bytes += res.downloaded_bytes.to_i
        }


      rescue SignalException => se
        $log.fatal "Signal caught: #{e.message}"
        $log.fatal "Since I'm sampling right now, I will kill workers before shutdown."
        kill_workers
        raise se
      rescue Exception => e
        if e.class.to_s =~ /^Curl::Err::/ then
          $log.debug "W#{worker_id}: Link #{link.id}: #{e.to_s[11..-1]}"
        else
          $log.error "W#{worker_id}: Exception retrieving #{link.id}: #{e.to_s}."
          $log.debug "#{e.backtrace.join("\n")}"
        end

        # write to datapoint list
        @dp[link.id] = DataPoint.new(link, "", "", "", {}, @client_id, "#{e}") 

        # update the counter.
        @global_stats_mutex.synchronize{ @errors += 1 }
    end
  end


end
