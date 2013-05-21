

module LWAC

  # ------------------------------------------------------------
  # Defines how output is written from the exporter tool
  class Formatter
    def initialize(config={})
      @config = config
    end

    ## --------------------------------------------
    # Open all output for writing
    def open_output()
    end

    # Close output after all items have been written
    def close_output()
    end

    # Write one line
    def <<(data)
      open_point()
      add_data(data)
      close_point()
    end

    ## --------------------------------------------
    # Write keys if appropriate
    def write_header
    end

    ## --------------------------------------------
    # Open a single datapoint for writing, i.e. 
    # one line of a CSV or a new file for XML output
    def open_point()
      $log.debug "Opening new point"
      @data = nil
    end

    # Add a key-value set for a given line
    def add_data(data)
      $log.debug "Adding data: #{data}"
      @data = data
    end

    # Close the current point
    def close_point()
      $log.debug "Closing point."
    end
  end


  # ------------------------------------------------------------
  # Formatters that support key-value pairs as selected
  # by a 'fields' config item
  class KeyValueFormatter < Formatter
    require 'lwac/export/key_value_format'
   
    def initialize(config = {})
      super(config)
      raise "No fields in field listing" if (not (@config[:fields] and @config[:fields].length > 0) )
      KeyValueFormat::compile_format_procedures( @config[:fields] )
    end


    def open_point()
      $log.debug "KV: Opening new point"
      @data = nil
      @line = {}
    end

    def add_data(data)
      $log.debug "KV: Adding data: #{data}"
      @data = data
      @line.merge! KeyValueFormat::produce_output_line( data, @config[:fields] )
    end
  end




  # ------------------------------------------------------------
  # Output to a single JSON file
  class JSONFormatter < KeyValueFormatter 
    require 'json'
    # TODO: - sync after every write
    #       - use formatter system]
    #
    #
    def open_output()
      $log.info "Opening #{@config[:filename]} for writing..."
      @f = File.open( @config[:filename], 'w' )
    end

    def close_output()
      $log.info "Closing output CSV..."
      @f.close
    end

    def write_header
      $log.info "Writing header"
      @f.write( @config[:fields].keys )
      @f.flush
    end

    def close_point()
      super
      @f.write(JSON.generate(@line.values))
      @f.write("\n")
      @f.flush
    end
  end



  # ------------------------------------------------------------
  # Output to a single CSV file
  class CSVFormatter < KeyValueFormatter 
    require 'csv'

    def open_output()
      $log.info "Opening #{@config[:filename]} for writing..."
      $log.debug "Options for CSV: #{@config[:csv_opts]}"
      @csv = CSV.open(@config[:filename], 'w', @config[:csv_opts] || {})
    end

    def close_output()
      $log.info "Closing output CSV..."
      @csv.close
    end

    def write_header
      $log.info "Writing header"
      @csv << @config[:fields].keys
    end

    def close_point()
      super
      @csv << (@line.values)
    end
  end





  # ------------------------------------------------------------
  # Output to individual CSVs
  class MultiCSVFormatter < KeyValueFormatter 
    require 'csv'
    require 'fileutils'

    def write_header
      @config[:headers] = true
    end

    def close_point()
      filename = get_filename( @data )
      $log.debug "Writing point to file #{filename}..."
      file_exists = File.exist?( filename )

      # FIXME: don't keep opening/closing file
      CSV.open( filename, "a" ){|cout|
        cout << @line.keys if not file_exists and @config[:headers] 
        cout << @line.values
      }
    end

    private
    def get_filename(data)
      filename = eval( "\"#{@config[:filename]}\"" ).to_s
      FileUtils.mkdir_p( File.dirname( filename ) ) if not File.exist?( File.dirname( filename ) )
      return filename
    rescue Exception => e
      $log.error "Failed to generate filename."
      $log.error "This data point will be skipped."
      $log.debug "#{e.backtrace.join("\n")}"
      return nil
    end
  end






  # ------------------------------------------------------------
  # Output to an erb template
  class MultiTemplateFormatter < Formatter  # FIXME: should not use KeyValueFormatter
    require 'erb'

    def initialize( config )
      super(config)
      
      raise "Template not found" if not File.exist?(@config[:template])
      @template = File.read(@config[:template])
    end

    def close_point()
      # FIXME: expression-based filename...
      filename = get_filename( @data )
      $log.debug "Writing point to file #{filename}..."
      $log.warn "Overwriting (#{filename}) (you might have selected a non-unique key field)" if File.exist?(filename)

      File.open(filename, 'w'){ |f|
        f.write(apply_template(filename, @data))
      }
    end

    private
    def apply_template(filename, data)
      return ERB.new(@template).result(binding)
    rescue StandardError => e
      $log.warn "Error running template #{@config[:template]}: #{e}"
      $log.debug "#{e.backtrace.join("\n")}"
    end


    def get_filename(data)
      filename = eval( "\"#{@config[:filename]}\"" ).to_s
      FileUtils.mkdir_p( File.dirname(filename) ) if not File.exist?( File.dirname(filename) )
      return filename
    rescue Exception => e
      $log.error "Failed to generate filename."
      $log.error "This data point will be skipped."
      $log.debug "#{e.backtrace.join("\n")}"
      return nil
    end
  end

end
