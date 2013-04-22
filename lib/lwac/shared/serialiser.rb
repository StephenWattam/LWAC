
require 'yaml'
require 'msgpack'



module LWAC



  # Serialisation sysetm used for data
  module Serialiser

    # Change to :yaml to use YAML
    METHOD = :marshal

    # Serialise to a string
    def self.serialise(obj, method=METHOD)
      return Marshal.dump(obj)    if method == :marshal
      return YAML.dump(obj)       if method == :yaml
      return obj.to_msgpack
    end

    # Deserialise from a string
    def self.unserialise(bits, method=METHOD)
      return Marshal.load(bits)   if method == :marshal
      return YAML.load(bits)      if method == :yaml
      return MessagePack.unpack(bits)
    end

    # Load an object from disk
    def self.load_file(fn, method=METHOD)
      return File.open(fn, 'r'){ |f| Marshal.load(f) }      if method == :marshal
      return YAML.load_file(File.read(fn))                  if method == :yaml
      return File.open(fn, 'r'){ |f| MessagePack.unpack( f.read ) } # efficientify me
    end

    # Write an object to disk
    def self.dump_file(obj, fn, method=METHOD)
      return File.open(fn, 'w'){ |f| Marshal.dump(obj, f) }   if method == :marshal
      return YAML.dump(obj, File.open(fn, 'w')).close         if method == :yaml
      return File.open(fn, 'w'){ |f| obj.to_msgpack }
    end
  end


end
