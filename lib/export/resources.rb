
# -----------------------------------------------------------------------------
# Provide a nice truncated output for summaries
class String
  def truncate(lim, ellipsis='...', pad=' ')
    ellipsis = '' if self.length <= lim
    return ellipsis[ellipsis.length - lim..-1] if lim <= ellipsis.length
    return self[0..(lim - ellipsis.length)-1] + ellipsis + (pad * [lim - self.length, 0].max)
  end
end

# -----------------------------------------------------------------------------
# This is similar to ruby's Struct system, in that it creates an object based on
# the input parameters, with the exception that it can be efficiently and
# recursively described.
class Resource

  # Construct a resource from a hash of parameters and a name.
  def initialize(name, params = {})
    @params = []
    params.each{ |p, v|
      if(p) then
        # Parse param
        param   = sanitise_paramname(p)
        raise "Duplicate parameters for resource #{name}: #{param}." if @params.include? param
        val     = (v.is_a? Hash) ? Resource.new(param, v) : v

        eval("@#{param} = val")
        self.class.__send__(:attr_accessor, param)
        @params << param
      end
    }
    @name     = name
  end

  # Describe this resource in a nice terminal-friendly way
  #  * trunc --- how to truncate the keys[0] and values[1]
  #  * indent --- base indent
  #  * notitle --- Don't output a header
  def describe(trunc = [17, 50], indent=0, notitle=false)
    str = "{\n"
    str = "#{" "*indent}#{@name}#{str}" if not notitle
    @params.each{|p|
      # Load the value
      val = eval("@#{p}")

      # Output the string
      str += "#{" "*indent}  #{p.truncate(trunc[0])}: "
      if val.is_a? Resource
        str += "#{val.describe(trunc, indent + 2, true)}" 
      else
        str += "#{val.to_s.truncate(trunc[1]).gsub("\n", '\n').gsub("\r", '\r').gsub("\t", '\t')}"
      end
      str += "\n"
    }
    str += "#{" "*indent}}"
    return str
  end

private

  # Store a clean internal parameter name
  def sanitise_paramname(p)
    p.to_s.gsub(/[\s]/, "_").gsub(/[^a-zA-Z0-9_]/, "_")
  end
end




