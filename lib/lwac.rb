
# LWAC namespace
module LWAC
  # Overall LWAC version, as in the git tags
  VERSION = '0.2.0b'
  # Date of last significant edit
  DATE    = '31-05-13'

  # Authors
  AUTHORS = [
              {:name => "Stephen Wattam", :contact => "http://stephenwattam.com"},
             #{:name => "", :contact => ""}  # Add yourself here (and in the gemspec) if you contribute to LWAC
            ]

  # Location of resources
  RESOURCE_DIR = File.join( File.dirname( File.expand_path(__FILE__) ), '../resources/') 
end
