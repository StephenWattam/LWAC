#!/usr/bin/env ruby

# 
# Compiles all nearby markdown into HTML, and pops it in ./docs
#

require 'markdown'
require 'fileutils'
require 'erb'

output_dir = "./docs"
MARKDOWN_EXTENSIONS = %w{markdown mdown mkdn md mkd mdwn mdtxt mdtext text} 
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
pages = Dir.glob("*").to_a.delete_if{|f| not MARKDOWN_EXTENSIONS.include?(File.extname(f).to_s[1..-1]) }.map{|f| f.to_s[0..-(File.extname(f).length + 1)]}

puts "LIST: #{pages.to_s}"

Dir.glob("*"){|f|
  if MARKDOWN_EXTENSIONS.include?(File.extname(f).to_s[1..-1]) then
    puts "Compiling #{File.basename(f)}..."

    File.open(File.join(output_dir, File.basename(f)[0..-(File.extname(f).length + 1)] + ".html"), 'w'){|of|      
      of.write( template(f, Markdown.new(File.read(f)).to_html, pages ))
    }
  elsif f != $0 and File.basename(f) != File.basename(output_dir)
    puts "Copying #{f}..."
    FileUtils.cp_r(f, File.join(output_dir, f))
  end
}

puts "Done."
