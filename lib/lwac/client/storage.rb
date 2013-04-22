# Storage/cache library for clients
# This is a simple key-value store either on disk or in memory, designed for storing datapoints before they're shipped off to the server

require 'fileutils'

module LWAC

  class Store 
    # Create a new store with a given file.
    #
    # If a filepath is given, PStore is used for on-disk, persistent storage.
    # if thread_safe is true then:
    #  - Hashes will be made thread-safe
    #  - PStores will be switched to thread-safe mode
    def initialize(filepath=nil)
      # Create a mutex if using a hash
      @mutex = Mutex.new

      if filepath == nil or filepath.to_s == ""
        @store = Hash.new
        @type = :hash
      else
        @store = FileCache.new(filepath)
        @type = :file
      end
    end

    # ---------------------------------------------------------------------------
    # Method_missing handles most things...

    def method_missing(m, *args, &block)
      @store.send(m, *args, &block)
    rescue NoMethodError => e
      super
    end

    # Handle disparity between APIs
    # ---------------------------------------------------------------------------

    # Closes the file system, missing from Hash
    def close
      return if @type == :hash
      @store.close
    end

    def delete_from_index(key)
      if @type == :hash
        @mutex.synchronize{
          return @store.delete(key)
        }
      end
      @store.delete_from_index(key)
    end

    # Removes all items
    def delete_all
      # GC's probably quicker than looping and removing stuff
      if @type == :hash   
        @mutex.synchronize{
          @store = Hash.new 
        }
      else
        @store.delete_all
      end
    end
  end 


end
