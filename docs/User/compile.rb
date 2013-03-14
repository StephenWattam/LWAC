#!/usr/bin/env ruby

# 
# Compiles all nearby markdown into HTML, and pops it in ./docs
#

require 'markdown'
require 'fileutils'

output_dir = "./docs"
MARKDOWN_EXTENSIONS = %w{markdown mdown mkdn md mkd mdwn mdtxt mdtext text} 


if File.exist?(output_dir) then
    $stderr.puts "Output directory exists (#{output_dir}) --- please delete and run again."
    exit(1)
end

# create output dir
FileUtils.mkdir_p(output_dir)

Dir.glob("*"){|f|
  if MARKDOWN_EXTENSIONS.include?(File.extname(f).to_s[1..-1]) then
    puts "Compiling #{File.basename(f)}..."

    File.open(File.join(output_dir, File.basename(f)[0..-(File.extname(f).length + 1)] + ".html"), 'w'){|of|      
      of.write( Markdown.new(File.read(f)).to_html )
    }
  elsif f != $0 and File.basename(f) != File.basename(output_dir)
    puts "Copying #{f}..."
    FileUtils.cp_r(f, File.join(output_dir, f))
  end
}

puts "Done."

