
Gem::Specification.new do |s|
  # About the gem
  s.name        = 'lwac'
  s.version     = '0.2.0b'
  s.date        = '2013-04-22'
  s.summary     = 'Longitudinal Web-as-Corpus sampling'
  s.description = 'A tool to construct longitudinal corpora from web data'
  s.author      = 'Stephen Wattam'
  s.email       = 'stephenwattam@gmail.com'
  s.homepage    = 'http://stephenwattam.com/projects/LWAC'
  s.required_ruby_version =  ::Gem::Requirement.new(">= 1.9")
  
  # Files + Resources
  s.files         = Dir.glob("resources/schemata/*") + Dir.glob("doc/*") + Dir.glob("example_config/*.yml") + 
                    Dir.glob("lib/*/*/*.rb") +
                    Dir.glob("lib/*/*.rb") +
                    Dir.glob("lib/*.rb") 
  s.require_paths = ['lib']
  
  # Executables
  s.bindir      = 'bin'
  s.executables << 'lwac'

  # Documentation
  s.has_rdoc         = false
  s.extra_rdoc_files = ['README.md'] + Dir.glob("*.md")
  # .map{|f| f.to_s[0..-(File.extname(f).to_s.length+1)] }    # TODO: add user documentation in html form

  # Deps
  s.add_runtime_dependency 'curb',          '~> 0.8'
  s.add_runtime_dependency 'sqlite3',       '~> 1.3'
  s.add_runtime_dependency 'simplerpc',     '~> 0.1'

  # Misc
  s.post_install_message = "Have fun."
end