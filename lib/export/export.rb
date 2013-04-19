# FIXME: this is an inelegant way of managing load paths
$:.unshift( File.join( File.dirname(__FILE__), "../", "server" ) )
$:.unshift( File.join( File.dirname(__FILE__), "../", "shared" ) )
$:.unshift( File.dirname(__FILE__) )

require 'storage_manager'
require 'output_formatter'
require 'resources'
require 'csv'

class Exporter

  def initialize(config)
    @config = config
    
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


    # Open the CSV
    $log.debug "Opening #{@config[:output][:filename]} for writing..."
    CSV.open(@config[:output][:filename], 'w') do |csv_out|



      # Write headers
      if @config[:output][:headers]
        $log.debug "Writing headers (line #{count+=1}/#{@estimated_lines})."
        csv_out << @config[:output][:format].keys
        progress = announce(count, progress, @estimated_lines, @config[:output][:announce])
      end 

      
      # -----------------------------------------------------------------------------
      # Construct the server (static) resource
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
          csv_out << produce_output_line( data, @config[:output][:format] )
          progress = announce(count, progress, @estimated_lines, @config[:output][:announce])
      else
        # ...continue to sample at a lower level
        # -----------------------------------------------------------------------------
        # One level deep, loop through samples and construct their resource
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
                    :num_pending_links    => as.pending.length,
                    :pending_links        => @storage.read_link_ids.to_a.delete_if{|id| (not as.pending.to_a.include?(id)) or (id > as.last_dp_id) },
                    :size_on_disk         => as.approx_filesize,
                    :last_contiguous_id   => as.last_dp_id,
                    :dir                  => @storage.get_sample_filepath(as.id),
                    :path                 => File.join(@storage.get_sample_filepath(as.id), @server_config[:storage][:sample_filename]) 
                   }
          data.sample = Resource.new("sample", sample)
          #puts sample.describe




          # If this sample is filtered out, ignore it regardless of sampling level
          if(filter(data, @config[:output][:filters][:sample])) then
            # If we wish to sample at the sample level, do so
            if(@config[:output][:level] == :sample) then
                # output at server level
                $log.debug "Writing output at sample level (line #{count+=1}/#{@estimated_lines})."
                csv_out << produce_output_line( data, @config[:output][:format] )
            else
              # ...continue and build more info
              # -----------------------------------------------------------------------------
              # Two levels deep, loop through datapoints and construct their resources.
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
                #puts data.describe




                # Filter out individual datapoints if necessary
                if(filter(data, @config[:output][:filters][:datapoint])) then
                  # At this point we are at the finest-grained output possible, so
                  # just output!
                  $log.debug "Writing output at datapoint level (line #{count+=1}/#{@estimated_lines})."
                  csv_out << produce_output_line( data, @config[:output][:format] )
                  progress = announce(count, progress, @estimated_lines, @config[:output][:announce] )
                else
                  @estimated_lines -= 1
                  $log.info "Discarded datapoint #{data.datapoint.id} due to filter (revised estimate: #{@estimated_lines} lines)."
                end
              } # end per-datapoint loop
            end # end sample if


          else # else filter out this sample
            @estimated_lines -= data.sample.size
            $log.info  "Discarded sample #{data.sample.id} due to filter (revised estimate: #{@estimated_lines} lines)."
          end # end filter IF


        } # end per-sample loop 
        end # end server if

    $log.debug "Closing CSV"
    end # end CSV block
    $log.info "Done."
  end

private

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
    $log.info "Sample is open, the latest sample we can export in full is #{@state.last_sample_id}" 
  end

  # Attempt to account for samples
  def validate_samples
    @available_samples = []
    available_sample_ids  = (0..(@state.last_sample_id)).to_a
    available_sample_ids.each{|sample_id|
      begin
        # Ensure the sample has all its files
        @storage.validate_sample(sample_id)

        # Load the sample metadata
        sample = @storage.read_sample(sample_id)

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

  # Compile formatting procedures
  def compile_formatters
    compile_format_procedures( @config[:output][:format] )
  end

  # Check and compile filters
  def compile_filters
    @config[:output][:filters] = {} if not @config[:output][:filters]
    compile_filters( @config[:output][:filters] )
  end

  # Estimate the time this is going to take and print to sc and print to screenn
  def summarise

    $log.info "Sampling at the #{@config[:output][:level].to_s} level."
    @estimated_lines = 0
    @estimated_lines = @available_samples.length if(@config[:output][:level] == :sample)
    @estimated_lines = @available_samples.length * @storage.read_link_ids.length if(@config[:output][:level] == :datapoint)
    @estimated_lines += 1 if @config[:output][:headers]
    $log.info "Estimated output lines: #{@estimated_lines}"


  end


end

