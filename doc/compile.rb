#!/usr/bin/env ruby

# 
# Compiles all nearby markdown into HTML, and pops it in ./docs
#

require 'markdown'
require 'fileutils'
require 'erb'

input_dir = "./user/*"
output_dir = "./html_docs"
TEMPLATE = "template.rhtml"

if File.exist?(output_dir) then
    $stderr.puts "Output directory exists (#{output_dir}) --- please delete and run again."
    exit(1)
end


def template(filename, content, pages)
  return ERB.new(File.read(TEMPLATE)).result(binding)
end

# create output dir
FileUtils.mkdir_p(output_dir)

# create list of pages
pages = Dir.glob(input_dir).to_a.delete_if{|f| File.extname(f)[1..-1] != "md" or File.directory?(f)}.map{|f| File.basename(f).to_s[0..-(File.extname(f).length + 1)]}

puts "LIST: #{pages.to_s}"

Dir.glob(input_dir){|f|
  if not File.directory?(f) and File.extname(f) == ".md" then
    puts "Compiling #{f}..."

    File.open(File.join(output_dir, File.basename(f)[0..-(File.extname(f).length + 1)] + ".html"), 'w'){|of|      
      of.write( template(f, Markdown.new(File.read(f)).to_html, pages ))
    }
  elsif f != $0 and File.basename(f) != File.basename(output_dir)
    puts "Copying #{f}..."
    FileUtils.cp_r(f, File.join(output_dir, File.basename(f)))
  end
}

puts "Done."

