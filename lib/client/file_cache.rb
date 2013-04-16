
require 'fileutils'
require 'thread'

class FileCache

  def initialize(filename, max_size = nil)
    # thread safety
    @mutex = Mutex.new
    
    raise "No filename given" if filename == nil
    @filename = filename
    reset # pullup

    # index system for lookup
    @index = {}
    @orphan_keys = []

    # TODO: Max size in bytes
    # @max_filesize = max_size
  end

  # read a value
  def [](key)
    @mutex.synchronize{
      return if not @index.include?(key)

      @file.seek( @index[key][:start] )
      return Marshal.load( @file.read( @index[key][:len] ) )
    }
  end

  # Write a value
  def []=(key, value)
    @mutex.synchronize{
      # keep record of the old version if already a value
      delete_from_index(key) if @index[key]

      # Keep a note of where we're writing
      @index[key] = {:start => @end_of_file}

      # Write
      @file.seek(@end_of_file)
      @file.write( Marshal.dump(value) )
      @file.flush
      @end_of_file = @file.pos

      # then read off position as a length
      @index[key][:len] = @end_of_file - @index[key][:start]
    }
  end

  # Wipe the store entirely
  def wipe
    @mutex.synchronize{
      @file.close if @file and not @file.closed?
      FileUtils.rm(@filename) if File.exist?(@filename)
      @file = File.open(@filename, 'wb+')
      @end_of_file = 0
    }
  end
  alias :delete_all :wipe
  alias :reset :wipe

  # Remove something from the index
  def delete_from_index(key)
    @mutex.synchronize{
      @orphan_keys << {:key => key, :value => @index.delete(key)} if @index.include?(key)
    }
  end

  def keys
    @mutex.synchronize{
      @index.keys
    }
  end

  # Read orphan keys
  # norably non-unique.
  def orphan_keys
    @mutex.synchronize{
      @orphan_keys.map{|o| o[:key] }
    }
  end

  # Enable sync mode
  def sync=(s)
    @mutex.synchronize{
      @file.sync = s
    }
  end

  # Status of sync mode
  def sync
    @mutex.synchronize{
      @file.sync
    }
  end

  # Flush to disk
  def flush 
    @mutex.synchronize{
      @file.flush
    }
  end

  # Loop over each key
  def each_key(&block)
    @mutex.synchronize{
      @index.each_key{|k| yield(k) }
    }
  end

  # How many items
  def length
    @mutex.synchronize{
      @index.length
    }
  end

  def empty?
    length == 0
  end

  # filesize in bytes
  def filesize
    @end_of_file
  end

  # Close and remove file
  def close
    @mutex.synchronize{
      @file.close
      FileUtils.rm(@filename)
    }
  end

  # Currently closed?
  def closed?
    @mutex.synchronize{
      @file.closed?
    }
  end
end
# 
# if __FILE__ == $0 then
#   # create new store
#   x = FileCache.new("test")
# 
#   100000.times{|i|
#     x[i] = i
#   }
# 
#   puts "x[20] = #{x[20]}"
# 
#   x.close
# end
