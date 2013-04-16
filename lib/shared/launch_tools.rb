# -----------------------------------------------------------------------------
# These procedures are designed as helpers for launching the various utilities
# in LWAC.  They cover:
#  * Loading configs
#  * Checking dependencies at runtime for helpful error output
#  * Instantiating global log objects



# -----------------------------------------------------------------------------
# Test if a gem is available, without throwing an exception
def gem_available?(name)
   Gem::Specification.find_by_name(name)
rescue Gem::LoadError
   false
rescue
   Gem.available?(name)
end


# -----------------------------------------------------------------------------
# Check gems exist and load them if possible.
def check_gems(*gems)
  gems.each{|g|
    if not gem_available?(g) then
      $stderr.puts "Missing gem: #{g}"
      exit(1)
    else
      gem g
    end
  }
end



# -----------------------------------------------------------------------------
# Load configs from ARGV[0] and output usage info.
def load_config 

  # First, check arguments are fine.
  if ARGV.length == 0 or not File.readable?(ARGV[0]) then
    $stderr.puts "USAGE: #{$0} PATH_TO_CONFIG"
    exit(1)
  end


  # Require things we need for the below
  require 'yaml'
  require 'logger'



  # Then check filesystem is in shape
  #require_relative ...


  # Then load the config
  config = YAML.load_file(ARGV[0])



  # Then, create global log
  logdevs = []
  config[:logging][:logs].each{|name, ldopts| 
    # Construct the log
    ld            = {:name => name}
    ld[:dev]      = %w{STDOUT STDERR}.include?(ldopts[:dev]) ? eval(ldopts[:dev]) : ldopts[:dev] || STDOUT
    ld[:level]    = ldopts[:level]

    # Add to the list of logs
    logdevs << ld
  }
  $log = MultiOutputLogger.new(logdevs, config[:logging][:progname])

  
  
  # Handle signals nicely.
  $log.debug "Installing signal handlers..."
  %w{INT HUP KILL ABRT}.each{|s|
    trap(s) { raise SignalException.new(s) }
  }


  # Return the config we've loaded.
  return config
end
