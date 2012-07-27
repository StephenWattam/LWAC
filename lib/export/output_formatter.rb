


def compile_filters( filters )
  filters.each{|level, fs|
    $log.info "Compiling #{level}-level filters..."

    if(fs) then
      fs.each{|f, v|
        $log.info "  Preparing filter #{f}..."
        v = {:expr => v, :lambda => nil}

        $log.debug "Building expression for filter (#{f})..."
        begin
          v[:lambda] = eval("lambda{|data|" + v[:expr] + "}")
        rescue Exception => e
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

# Runs filters for a given level
def filter( data, filters )
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

rescue Exception => e
  $log.fatal "Error filtering data: #{e}"
  $log.fatal "This is probably a bug in your filtering expressions."
  $log.fatal "Current state: filtering #{f}." if defined? f
  $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
  exit(1)
end

# Compile formatting procedures
def compile_format_procedures( format )
  $log.info "Compiling formatting procedures..."

  format.each{|f, v|
    $log.info "  Preparing field #{f}..."
    # Make sure it's a hash
    v = {:val => nil, :var => v, :expr => nil, :condition => nil, :missing => nil} if(not v.is_a? Hash)

    # Don't allow people to define both a static value and a variable
    criteria = 0
    %w{val var expr}.each{|method| criteria += 1 if v[method.to_sym] != nil}
    raise "No extraction method given for field '#{f}'."          if(criteria == 0)
    raise "Multiple extraction methods given for field '#{f}' (#{v.keys.join(", ")})."   if(criteria > 1)

    # Construct lambdas for active fields
    if v[:var] or v[:expr] then
      $log.debug "Building expression for data extraction (#{f})..."
      begin
        if v[:expr] then
          v[:lambda] = eval("lambda{|data|" + v[:expr] + "}")
        elsif v[:var] then
          v[:lambda] = eval("lambda{|data| return data." + v[:var] + "}")
        end
      rescue Exception => e
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
def produce_output_line( data, format )
  line = []
  
  format.each{|f, v|
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
    line << val
  }

  return line 

rescue Exception => e
  $log.fatal "Error producing output: #{e}"
  $log.fatal "This is probably a bug in your formatting expressions."
  $log.fatal "Current state: formatting #{f}." if defined? f
  $log.fatal "Backtrace: \n#{e.backtrace.join("\n")}"
  exit(1)
end




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


