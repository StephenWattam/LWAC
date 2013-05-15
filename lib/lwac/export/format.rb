

module LWAC

  # Defines how output is written from the exporter tool
  class Formatter
    def initialize(filename, config={})
      @filename = filename
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
    def <<(hash)
      open_point()
      add_data(hash)
      close_point()
    end

    ## --------------------------------------------
    # Write keys if appropriate
    def write_header(keys)
    end

    ## --------------------------------------------
    # Open a single datapoint for writing, i.e. 
    # one line of a CSV or a new file for XML output
    def open_point()
      $log.debug "Opening new point"
      @line = {}
    end

    # Add a key-value set for a given line
    def add_data(hash)
      $log.debug "Adding data: #{hash}"
      @line.merge!(hash)
    end

    # Close the current point
    def close_point()
      $log.debug "Closing point."
    end
  end


  # Output to a single CSV file
  class CSVFormatter < Formatter
    require 'csv'

    def open_output()
      $log.info "Opening #{@filename} for writing..."
      @csv = CSV.open(@filename, 'w')
    end

    def close_output()
      $log.info "Closing output CSV..."
      @csv.close
    end

    def write_header(keys)
      $log.info "Writing header"
      @csv << keys
    end

    def close_point()
      super
      @csv << (@line.values)
    end
  end

  # Output to individual CSVs
  class MultiCSVFormatter < CSVFormatter
    require 'csv'
    require 'fileutils'

    def open_output()
      FileUtils.mkdir_p(@filename) if not File.exist?(@filename)
      raise "Output directory exists but is a file" if not File.directory?(@filename)
    end

    def close_output()
    end

    def write_header(headers)
      @config[:headers] = true
    end

    def close_point()
      filename = File.join(@filename, @line[@config[:filename]].to_s)
      $log.debug "Writing point to file #{filename}..."
      file_exists = File.exist?(filename)

      CSV.open( filename, "a"){|cout|
        cout << @line.keys if not file_exists and @config[:headers] 
        cout << @line.values
      }
    end
  end

  # Output to an erb template
  class MultiTemplateFormatter < CSVFormatter
    require 'erb'

    def initialize( filename, config )
      super(filename, config)
      
      raise "Template not found" if not File.exist?(@config[:template])
      @template = File.read(@config[:template])
    end

    def write_header(headers)
    end

    def open_output()
      FileUtils.mkdir_p(@filename) if not File.exist?(@filename)
      raise "Output directory exists but is a file" if not File.directory?(@filename)
    end

    def close_point()
      filename = File.join(@filename, @line[@config[:filename]].to_s)
      $log.debug "Writing point to file #{filename}..."
      $log.warn "Template output presumes the filename is a unique key." if File.exist?(filename)

      File.open(filename, 'w'){ |f|
        f.write(apply_template(filename, @line))
      }
    end

    private
    def apply_template(filename, line)
      return ERB.new(@template).result(binding)
    rescue StandardError => e
      $log.warn "Error running template #{@config[:template]}: #{e}"
      $log.debug "#{e.backtrace.join("\n")}"
    end
  end

end
