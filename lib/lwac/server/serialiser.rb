
require 'yaml'

module LWAC

  # Serialisation sysetm used for data
  module Serialiser

    # Change to :yaml to use YAML
    METHOD = :marshal

    # Load an object from disk
    def self.load_file(fn)
      return File.open(fn, 'r'){ |f| Marshal.load(f) } if METHOD == :marshal
      YAML.load_file(File.read(fn)) # or yaml
    end

    # Write an object to disk
    def self.dump_file(obj, fn)
      return File.open(fn, 'w'){ |f| Marshal.dump(obj, f) } if METHOD == :marshal
      YAML.dump(obj, File.open(fn, 'w')).close # or yaml
    end
  end

end
