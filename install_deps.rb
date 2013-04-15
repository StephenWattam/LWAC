#!/usr/bin/env ruby

# This script installs dependencies for the LWAC tools.
# It's a bit more permissive than bundler, and can relax version
# requirements optimistically

# Where to log
LOG = "install.log"

# What to install in bundles
GEMS = { :common => [{:gem => 'marilyn-rpc', :ver => '0.0.4' },
                     {:gem => 'eventmachine', :ver => '0.12.10'}],
         :client => [{:gem => 'curb', :ver => '0.8.3'}],
         :server => [{:gem => 'sqlite3', :ver => '1.3.7'}]
}
GEMS[:all] = GEMS[:client] + GEMS[:server]


# -----------------------------------------------------------------------------
# Functions

# Install a gem
def install_gem(g, v)
  str = "gem install #{g[:gem]} #{(v) ? "-v '#{v} #{g[:ver]}'" : ''}"
  puts " *** Installing #{g[:gem]}..."
  result = `#{str} 2>&1`
  puts "     Done."
  return "\n\n*** #{str}\n#{result}"
end


# -----------------------------------------------------------------------------
# Argument handling/UI 

# Check args
if ARGV.length == 0 then
  $stderr.puts "This script installs prerequisite gems for LWAC"
  $stderr.puts ""
  $stderr.puts "USAGE: #{$0} BUNDLE [VERSION]"
  $stderr.puts ""
  $stderr.puts "  BUNDLE: 'client', 'server' or 'all': which set of gems"
  $stderr.puts "           should be installed?"
  $stderr.puts " VERSION: 'strict', 'optimistic', or 'lazy' version handling:"
  $stderr.puts "            - strict will install tested gem versions"
  $stderr.puts "            - optimistic will install tested or newer versions"
  $stderr.puts "            - lazy will install any available version of a gem"
  $stderr.puts ""
  exit(1)
end

# Read which bit people want
bundle = ARGV[0].to_s.downcase
if not %w{client server all}.include?(bundle) then
  $stderr.puts "Invalid set of gems: #{bundle}."
  exit(1)
end

# Read the version handling policy
version_policy = (ARGV[1] || 'strict').to_s.downcase
v = case(version_policy)
    when 'strict'
     '='
    when 'optimistic'
      '>='
    when 'lazy'
      nil
    else
      $stderr.puts "Invalid version policy"
      exit(1)
    end


# -----------------------------------------------------------------------------
# Then go through and do stuff.
#
# To anyone using this code, this deliberately doesn't use
# the 'gems' gem since it's an install script and shoudln't
# rely on much...

puts "*** Opening log at #{LOG}"
log = File.open(LOG, 'w+')
log.sync = true

# Log summary for later debugging.
log.puts "LWAC installer"
log.puts "--------------"
log.puts "   Date: #{Time.now}"
log.puts " System: #{`uname -a`}"
log.puts "     WD: #{Dir.pwd}"
log.puts "   ARGS: #{ARGV.join(", ")}"
log.puts "--------------"

# Install common things
puts "*** Installing common components...\n"
GEMS[:common].each{|g|
  log.puts(install_gem(g, v))
}

# Then what people ask for
puts "*** Installing bundle: #{bundle}...\n"
GEMS[bundle.to_sym].each{|g|
  log.puts(install_gem(g, v))
}

# Close logfile
log.close

# Print humourous message
puts "\nComplete!  You can now go and enjoy the wonder that is LWAC :-)"
