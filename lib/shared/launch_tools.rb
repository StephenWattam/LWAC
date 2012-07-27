def gem_available?(name)
   Gem::Specification.find_by_name(name)
rescue Gem::LoadError
   false
rescue
   Gem.available?(name)
end


def verify_and_launch

  # First, check arguments are fine.
  if ARGV.length == 0 or not File.readable?(ARGV[0]) then
    $stderr.puts "USAGE: #{$0} PATH_TO_CONFIG"
    exit(1)
  end




  # Then, check gems
  if not gem_available?('marilyn-rpc') then
    $stderr.puts "You must install Marilyn RPC gem to proceed."
    $stderr.puts "gem install -r marilyn-rpc"
    exit(1)
  end

  # Requirt things we need for the below
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
  $log.summarise_logging

  
  
  # Handle signals nicely.
  $log.debug "Installing signal handlers."
  %w{INT HUP KILL ABRT}.each{|s|
    trap(s) { raise SignalException.new(s) }
  }


  # Return the config we've loaded.
  return config
end
