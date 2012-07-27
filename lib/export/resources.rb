
# Provide a nice truncated output for summaries
class String
  def truncate(lim, ellipsis = "...", pad = " ")
    raise "Cannot truncate to negative or zero length." if ellipsis.length >= lim

    ellipsis = "" if self.length < lim
    return (self + pad*((lim-ellipsis.length).to_f / pad.length).ceil)[0..(lim-ellipsis.length)] + ellipsis
  end
end

TRUNCATE_LENGTH = 15

class Resource
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
        str += "#{val.to_s.truncate(trunc[1])}"
      end
      str += "\n"
    }
    str += "#{" "*indent}}"
    return str
  end


  #def method_missing(m, *args)
    ## Convert to a string
    #m = m.to_s

    #if m =~ /(.*)=$/ then
      ## Assignment statement
      #param = $1
      #raise ArgumentError.new("wrong number of arguments(#{args.length} for 1)")     if not args.length == 1
      #raise NoMethodError.new("undefined method `#{m}' for #{self}:#{self.class}")   if not @params.include?(param)        

      #return eval("@#{param} = args[0]")
    #end

    ## Simple return statement
    #raise NoMethodError.new("undefined method `#{m}' for #{self}:#{self.class}")     if not @params.include?(m)
    #return eval("@#{m}")
  #end



private
  def sanitise_paramname(p)
    p.to_s.gsub(/[\s\-]/, "_")
  end
end




