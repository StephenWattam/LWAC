module LWAC

  module KeyValueFormat 
    # The output formatting system for the export tool uses these procedures.
    #
    # They are responsible for:
    #  * Constructing lambda-function filters for data selection
    #  * Constructing lambda-function output formatter scripts
    #  * Running filters on data
    #  * Producing output strings from formatters and data
    #



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
      $log.error "Error producing output: #{e}"
      $log.error "This is probably a bug in your formatting expressions."
      $log.error "Currently formatting '#{current}'." if current
      $log.error "Backtrace: \n#{e.backtrace.join("\n")}"
      $log.error "I'm going to continue because the alternative is giving up entirely"
      return 'ERROR'
      # exit(1)
    end

  end
end
