# -----------------------------------------------------------------------------
# These procedures are designed as helpers for launching the various utilities
# in LWAC.  They cover:
#  * Loading configs
#  * Checking dependencies at runtime for helpful error output
#  * Instantiating global log objects

require 'lwac/shared/multilog'

module LWAC

  def self.print_usage
    $stderr.puts "USAGE: #{$0} TOOL CONFIG"
    $stderr.puts ""
    $stderr.puts " TOOL   : one of 'server', 'client', 'import' or 'export'"
    $stderr.puts " CONFIG : A path to the config file for the tool"
    $stderr.puts ""
  end


  # -----------------------------------------------------------------------------
  # Load configs from ARGV[0] and output usage info.
  def self.load_config 

    # First, check arguments are fine.
    if ARGV.length < 2 or not File.readable?(ARGV[1]) then
      print_usage()
      exit(1)
    end

    # Check the tool is a valid one
    if not %w{server client import export}.include?(ARGV[0]) then
      $stderr.puts "Not a valid command: #{ARGV[0]}"
      print_usage()
      exit(1)
    end

    # Require things we need for the below
    require 'yaml'
    require 'logger'



    # Then check filesystem is in shape
    #require_relative ...


    # Then load the config
    tool   = ARGV[0].to_sym
    config = YAML.load_file(ARGV[1])



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
    return tool, config
  end

end