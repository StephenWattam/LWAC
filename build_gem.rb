#!/usr/bin/env ruby
#
# Builds the gem and includes the user documentation in the extra rdoc files, whilst
# hopefully retaining some form of functioning link structure...
#
require 'fileutils'

puts "Moving docs..."
docs = []
Dir.glob("doc/user/*.md").each{|f|
  puts " - #{File.basename(f)}"
  docs << File.basename(f)
  FileUtils.cp(f, File.basename(f))
}

puts "Building gem...."
`gem build lwac.gemspec`

puts "Removing docs..."
docs.each{|d|
  puts " - #{d}"
  FileUtils.rm(d)
}


puts "Done."
