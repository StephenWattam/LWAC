
require 'lwac/server/storage_manager'
require 'lwac/export/resources'
require 'lwac/export/format'

module LWAC

  module OutputFilter

    # -----------------------------------------------------------------------------
    # Loads filters from the config file, in the following format:
    #  {:level => {:filter_name => "expression", :name => "expr", :name => "expr"},
    #   :level => {...}
    #  }
    #
    # Where :level describes one of the filtering levels supported by the export
    # script:
    #  :server --- All data from a server's download process (mainly summary stats)
    #  :sample --- Data for a given sample (cross-sect)
    #  :datapoint --- Data for a given link
    #
    # Filter names are arbitrary identifiers for your referernce.
    #
    # Expressions can refer to any properties of the resource they use, or any
    # resources from higher levels, for example, sample levels can refer to sample.id,
    # but not datapoint.id.
    #
    def self.compile_filters( filters )
      filters.each{|level, fs|
        $log.info "Compiling #{level}-level filters..."

        if(fs) then
          fs.each{|f, v|
            $log.info "  Preparing filter #{f}..."
            v = {:expr => v, :lambda => nil}

            $log.debug "Building expression for filter (#{f})..."
            begin
              v[:lambda] = eval("lambda{|data|" + v[:expr] + "}")
            rescue StandardError => e
              $log.fatal "Error building expression for field: #{f}."
              $log.fatal "Please review your configuration."
              $log.fatal "The exact error was: \n#{e}"
              $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
              exit(1)
            end
            $log.debug "Success so far..."

            # pop back into original list
            fs[f] = v
          }
        end
      
        filters[level] = fs
        $log.info "Done."
      }
    end





    # -----------------------------------------------------------------------------
    # Runs filters for a given level
    def self.filter( data, filters )
      return true if not filters # Accept if no constraints given

      $log.debug "Filtering line..."
      # Run all constraints, fail fast
      filters.each{|f, v|
        if not v[:lambda].call(data)
          $log.debug "Rejecting due to filter: #{f}"
          return false 
        end
      }

      # We got this far, accept!
      $log.debug "Accepting."
      return true

    rescue StandardError => e
      $log.fatal "Error filtering data: #{e}"
      $log.fatal "This is probably a bug in your filtering expressions."
      $log.fatal "Current state: filtering #{f}." if defined? f
      $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
      exit(1)
    end

  end







  class Exporter

    # Points at the various formatter objects available
    AVAILABLE_FORMATTERS = {
      :csv            => CSVFormatter,
      :multicsv       => MultiCSVFormatter,
      :json           => JSONFormatter,
      :multitemplate  => MultiTemplateFormatter,
      :multixml       => MultiXMLFormatter
    }

    def initialize(config)
      @config = config

      # Create a new formatter
      @formatter = AVAILABLE_FORMATTERS[@config[:output][:formatter]].new( @config[:output][:formatter_opts] )
      
      prepare_filters
      
      load_server_config

      load_storage_resources

      validate_samples


      summarise
    end

    # Export according to config
    def export
      # -----------------------------------------------------------------------------
      # At this point we have a list of samples that are valid
      # We should now probably do something with them :-)
      # They all go in the structure below
      data                  = Resource.new(Data, {:server => nil, :sample => nil, :datapoint => nil})

      # Fire up some accounting variables
      count     = 0
      progress  = [count, Time.now]


      # Open the output system 
      $log.debug "Opening formatter for writing..."
      @formatter.open_output

      # Write headers
      if @config[:output][:headers]
        $log.debug "Writing headers (line #{count+=1}/#{@estimated_lines})."
        @formatter.write_header
        progress = announce(count, progress, @estimated_lines, @config[:output][:announce])
      end 

      
      # -----------------------------------------------------------------------------
      # Construct the server (static) resource
      $log.debug "Constructing server resource..."
      server = {:links                  => @storage.read_link_ids.to_a,
                :complete_sample_count  => @available_samples.length,
                :complete_samples       => @available_samples.map{|as| as.id},
                :next_sample_date       => @storage.state.next_sample_due,
                :current_sample_id      => @storage.state.current_sample.id,
                :config                 => @server_config,
                :version                => @storage.state.version
               }
      data.server = Resource.new("server", server)
      #puts server.describe


      
      # If we wish to output at the server level, do so.
      if(@config[:output][:level] == :server) then
          # output at server level
          $log.debug "Writing output at server level (line #{count+=1}/#{@estimated_lines})."
          @formatter << data
          progress = announce(count, progress, @estimated_lines, @config[:output][:announce])
          #.values
      else
        # ...continue to sample at a lower level
        # -----------------------------------------------------------------------------
        # One level deep, loop through samples and construct their resource
        $log.debug "Constructing sample resources..."
        @available_samples.each{|as|
          sample = {:id                   => as.id,
                    :start_time           => as.sample_start_time,
                    :end_time             => as.sample_end_time,
                    :complete             => as.complete?,
                    :open                 => as.open?,
                    :size                 => as.size,
                    :duration             => (as.sample_end_time && as.sample_start_time) ? as.sample_end_time - as.sample_start_time : 0,
                    :start_time_s         => as.sample_start_time.to_i,
                    :end_time_s           => as.sample_end_time.to_i,
                    # :num_pending_links    => as.pending.length,
                    # Either form takes way too long to compute on large servers
                    # :pending_links        => data.server.links - (data.server.links.clone.delete_if{|x| x > as.last_dp_id} - as.pending.to_a),
                    # :pending_links        => data.server.links.clone.to_a.delete_if{|id| (not as.pending.to_a.include?(id)) or (id > as.last_dp_id) },
                    :size_on_disk         => as.approx_filesize,
                    :last_contiguous_id   => as.last_dp_id,
                    :dir                  => @storage.get_sample_filepath(as.id),
                    :path                 => File.join(@storage.get_sample_filepath(as.id), @server_config[:storage][:sample_filename]) 
                   }
          data.sample = Resource.new("sample", sample)
          # puts data.describe




          # If this sample is filtered out, ignore it regardless of sampling level
          if(OutputFilter::filter(data, @config[:output][:filters][:sample])) then
            # If we wish to sample at the sample level, do so
            if(@config[:output][:level] == :sample) then
                # output at server level
                $log.debug "Writing output at sample level (line #{count+=1}/#{@estimated_lines})."
                @formatter << data
            else
              # ...continue and build more info
              # -----------------------------------------------------------------------------
              # Two levels deep, loop through datapoints and construct their resources.
              $log.debug "Constructing datapoint resources..."
              data.server.links.each{|link_id|
                # Load from disk
                dp = @storage.read_datapoint( link_id, as )

                datapoint = {:id            => dp.link.id     || "",
                             :uri           => dp.link.uri    || "",
                             :dir           => File.dirname(@storage.get_dp_filepath(link_id, data.sample.id)), 
                             :path          => @storage.get_dp_filepath(link_id, data.sample.id),
                             :client_id     => dp.client_id   || "",
                             :error         => dp.error       || "",
                             :headers       => dp.headers     || {},
                             :head          => dp.head        || "",
                             :body          => dp.body        || "",
                             :response      => dp.response_properties || {}
                            }
              
                data.datapoint = Resource.new("datapoint", datapoint)
                # puts data.describe


                # Filter out individual datapoints if necessary
                if(OutputFilter::filter(data, @config[:output][:filters][:datapoint])) then
                  # At this point we are at the finest-grained output possible, so
                  # just output!
                  $log.debug "Writing output at datapoint level (line #{count+=1}/#{@estimated_lines})."
                  @formatter << data
                  progress = announce(count, progress, @estimated_lines, @config[:output][:announce] ) 
                else
                  @estimated_lines -= 1
                  $log.debug "Discarded datapoint #{data.datapoint.id} due to filter (revised estimate: #{@estimated_lines} lines)."
                end
              } # end per-datapoint loop
            end # end sample if


          else # else filter out this sample
            @estimated_lines -= data.sample.size
            $log.debug  "Discarded sample #{data.sample.id} due to filter (revised estimate: #{@estimated_lines} lines)."
          end # end filter IF


        } # end per-sample loop 
        end # end server if

      @formatter.close_output
      $log.info "Done."
    end

  private


    # -----------------------------------------------------------------------------
    # Describe progress through the sample
    def announce(count, progress, estimated_lines, period)
      return progress if(count % period) != 0

      # Extract stuff from the progress info
      last_count, time = progress

      # Compute estimated links remaining
      links_remaining = estimated_lines - count
      # Compute time per link since last time
      time_per_link = (Time.now - time).to_f/(count - last_count).to_f
      # Compute percentage
      percentage = ((count.to_f / estimated_lines) * 100).round(2)

      $log.info "#{count}/#{estimated_lines} (#{percentage}%) complete at #{(1.0/time_per_link).round(2)}/s ETA: #{Time.now + (time_per_link * links_remaining)}"

      # Return a new progress list
      return [count, Time.now]
    end


    # Load server configuration file into ram
    def load_server_config
      # Attempt to load server config
      if not File.exist?(@config[:server_config]) then
        $log.fatal "Server config file does not exist at #{@config[:server_config]}"
        exit(1)
      end
      @server_config = YAML.load_file( File.open(@config[:server_config]) )
    end

    # Start up the two storage managers to inform us of the progress made
    def load_storage_resources
      @storage               = StorageManager.new(@server_config[:storage])
      @state                 = @storage.state

      # -----------------------------------------------------------------------------
      # Print handy messages to people
      $log.warn "No samples have completed yet, this is a new deployment." if(@state.last_sample_id == -1)
      $log.info "Current sample: #{@state.current_sample}."

      cs = @state.current_sample
      $log.info "The latest sample we can export in full is #{(cs.open? or not cs.complete?) ? @state.last_sample_id : @state.current_sample.id}" 
    end

    # Attempt to account for samples
    def validate_samples
      @available_samples = []
      available_sample_ids  = (0..(@state.current_sample.id)).to_a
      available_sample_ids.each{|sample_id|
        begin
          # Ensure the sample has all its files
          @storage.validate_sample(sample_id)

          # Load the sample metadata
          sample = @storage.read_sample(sample_id)

          # check it's closed and complete
          raise "sample is open" if sample.open?
          raise "sample is incomplete" if not sample.complete?

          # Pop in the "valid" list.
          @available_samples << sample
        rescue StandardError => e
          $log.warn "Problem reading sample #{sample_id}: #{e.to_s}"
          $log.debug e.backtrace.join("\n")
        end
      }
      $log.info "Opened #{@available_samples.length} samples successfully."
      $log.debug "Samples: #{@available_samples.join(", ")}"

    end

    # Check and compile filters
    def prepare_filters
      @config[:output][:filters] = {} if not @config[:output][:filters]
      OutputFilter::compile_filters( @config[:output][:filters] )
    end

    # Estimate the time this is going to take and print to sc and print to screenn
    def summarise

      $log.info "Sampling at the #{@config[:output][:level].to_s} level."
      @estimated_lines = 0
      @estimated_lines = @available_samples.length if(@config[:output][:level] == :sample)
      @estimated_lines = @available_samples.length * @storage.read_link_ids.length if(@config[:output][:level] == :datapoint)
      $log.info "Estimated output actions: #{@estimated_lines}"


    end


  end

end
