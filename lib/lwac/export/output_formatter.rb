module LWAC

  module OutputFormatter
    # The output formatting system for the export tool uses these procedures.
    #
    # They are responsible for:
    #  * Constructing lambda-function filters for data selection
    #  * Constructing lambda-function output formatter scripts
    #  * Running filters on data
    #  * Producing output strings from formatters and data
    #




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




    # -----------------------------------------------------------------------------
    # Compile formatting procedures
    #
    # Output format procedures are designed to handle output of missing values,
    # formatting such as lower-case or normalised output.
    #
    # The format is described in a hash, as in the config file:
    #  { :key_name => "variable.name", -and/or-
    #    :key_name => {:var => 'variable.name', :condition => 'expression', :missing => 'NA'},
    #    :key_name => {:expr => 'expression returning value'},
    #    ...
    # }
    # 
    # Where 'key_name' is used to form the name of a column in the CSV, and the value can be
    # either a hash or a string.  Where a string is given, it is presumed to be the name
    # of a resource value, i.e. sample.id, or sample.datapoint.id.  Where a hash is given,
    # it can contain either
    #  1) :var, :condition and :missing fields to describe how to get and format data simply
    #  2) :expr, an expression that returns a value and may do more complex formatting
    #
    def self.compile_format_procedures( format )
      $log.info "Compiling formatting procedures..."

      format.each{|f, v|
        $log.info "  Preparing field #{f}..."
        # Make sure it's a hash
        v = {:val => nil, :var => v, :expr => nil, :condition => nil, :missing => nil} if(not v.is_a? Hash)

        # Don't allow people to define both a static value and a variable
        criteria = 0
        %w{val var expr}.each{|method| criteria += 1 if v[method.to_sym] != nil}
        raise "No extraction method given for field '#{f}'."          if(criteria == 0)
        raise "Multiple extraction methods given for field '#{f}' (#{v.keys.join(", ")})." if(criteria > 1)

        # Construct lambdas for active fields
        if v[:var] or v[:expr] then
          $log.debug "Building expression for data extraction (#{f})..."
          begin
            if v[:expr] then
              v[:lambda] = eval("lambda{|data|" + v[:expr] + "}")
            elsif v[:var] then
              v[:lambda] = eval("lambda{|data| return data." + v[:var] + "}")
            end
          rescue StandardError => e
            $log.fatal "Error building expression for field: #{f}."
            $log.fatal "Please review your configuration."
            $log.fatal "The exact error was: \n#{e}"
            $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
            exit(1)
          end
          $log.debug "Success so far..."
        end

        format[f] = v
      }

      $log.info "Done."
    end




    # -----------------------------------------------------------------------------
    # Format data from the 'data' resource according to a set of rules
    # given in the format hash.
    #
    # The hash is, roughly, organised thus:
    #  output_field_name: data.path.to.var
    # - OR -
    #  output_field_name: {:val => static value, (optional) one of these must exist
    #                      :var => path.to.var, (optional)
    #                      :condition => "expression which must be true to be
    #                      non-missing, default is simply true",
    #                      :missing => "value for when it's missing, default is """ }
    def self.produce_output_line( data, format )
      line = {}
     
      current = nil
      format.each{|f, v|
        current = f
        $log.debug "Processing field #{f}..."

        # Look up info
        if v[:lambda] then
          val = v[:lambda].call(data)
        elsif v[:val] then
          val = v[:val]
        else
          $log.fatal "No way of finding var for #{f}!"
          $log.fatal "Please check your config!"
          exit(1)
        end
        
        # Handle the condition of missingness
        if(v[:condition])
          x   = val
          val = v[:missing] if not eval("#{v[:condition]}")
        end

        # add to line
        line[f] = val
      }
      current = nil

      return line 

    rescue StandardError => e
      $log.fatal "Error producing output: #{e}"
      $log.fatal "This is probably a bug in your formatting expressions."
      $log.fatal "Currently formatting '#{current}'." if current
      $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
      exit(1)
    end



    # -----------------------------------------------------------------------------
    # Describe progress through the sample
    def self.announce(count, progress, estimated_lines, period)
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

  end
end
