# Storage/cache library for clients
# This is a simple key-value store either on disk or in memory, designed for storing datapoints before they're shipped off to the server

require 'pstore'

class Store 
  # Create a new store with a given file.
  #
  # If a filepath is given, PStore is used for on-disk, persistent storage.
  # if thread_safe is true then:
  #  - Hashes will be made thread-safe
  #  - PStores will be switched to thread-safe mode
  def initialize(filepath=nil, thread_safe=true)
    # Record the filepath
    @filepath = filepath

    # Create the store
    if @filepath then
      @store = PStore.new(@filepath, thread_safe)
      @index = []
    else
      @store = Hash.new
      @index = nil 
    end

    # Create a mutex if using a hash
    @mutex = ((thread_safe and not @filepath) ? Mutex.new : nil)
  end

  # Assign a value to the store.
  # 
  #FIXME: improve return values.  This isn't critical but might be wise
  def []=(key, value)
    if type == :hash and @mutex then
      @mutex.synchronize{ @store[key] = value }
    elsif type == :pstore 
      @store.transaction{ 
        @index << key 
        @store[key] = value }
    else
      return @store[key] = value
    end
  end

  # Access a value at a given key
  def [](key)
    if type == :hash and @mutex then
      @mutex.synchronize{ return @store[key] }
    elsif type == :pstore
      @store.transaction{ 
        @index << key 
        return @store[key] }
    else
      return @store[key]
    end
  end

  #FIXME: improve return values.  This isn't critical but might be wise
  def delete(key)
    if type == :hash and @mutex then
      @mutex.synchronize{ @store.delete(key) }
    elsif type == :pstore
      @index.delete(key)  # FIXME: mutex me
      @store.transaction{ @store.delete(key) }
    else
      return @store.delete(key)
    end
  end

  # Loop over keys, calling the block given for each
  def each_key(&block)
    if type == :hash and @mutex then
      @mutex.synchronize{
        @store.each_key{|k|
          yield(k)
        }
      }
    elsif type == :pstore
      @index.each{|k|
        yield(k)
      }
    else
      @store.each_key{|k|
        yield(k)
      }
    end
    # TODO
  end

  # Get the number of items in the store
  def length
    if type == :pstore
      return @index.length
    else
      return @store.length
    end
  end

  # Returns true if the store is empty
  def empty?
    length == 0
  end

  # Returns an array of keys currently used in the store
  def keys
    if type == :hash and @mutex then
      @mutex.synchronize{ return @store.keys }
    elsif type == :pstore
      return @index
    else
      return @store.keys
    end
  end

  # Returns the type of store currently being used.
  #  :hash for Hash-based,
  #  :pstore for PStore-based.
  def type
    return :hash if not @filepath
    return :pstore
  end
end
