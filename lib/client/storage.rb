# Storage/cache library for clients

require 'pstore'

class Store 
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

  def []=(key, value)
    if type == :hash and @mutex then
      @mutex.synchronize{ @store[key] = value }
    elsif type == :pstore 
      @index << key ## FIXME: mutex me
      @store.transaction{ @store[key] = value }
    else
      return @store[key] = value
    end
  end

  def [](key)
    if type == :hash and @mutex then
      @mutex.synchronize{ return @store[key] }
    elsif type == :pstore
      @store.transaction{ return @store[key] }
    else
      return @store[key]
    end
  end

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

  def length
    if type == :pstore
      return @index.length
    else
      return @store.length
    end
  end

  def keys
    if type == :hash and @mutex then
      @mutex.synchronize{ return @store.keys }
    elsif type == :pstore
      return @index
    else
      return @store.keys
    end
  end

  # def method_missing(m, *args, &block)
  #   @store.send(m, *args, &block)
  # end

  # def respond_to_missing(m, include_private=false)
  #   @store.respond_to_missing(m, include_private)
  # end

  def type
    return :hash if not @filepath
    return :pstore
  end
end
