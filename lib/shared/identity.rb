# Contains version and identification information for people to use when reporting


module Identity

  # Overall LWAC version, as in the git tags
  VERSION = "0.2.0b"

  # Versions that may be loaded by the storage manager
  # If it ain't in this list, it ain't coming off disk into RAM.
  COMPATIBLE_CORPUS_VERSIONS  = [VERSION]
  COMPATIBLE_NETWORK_VERSIONS = [VERSION]

  # Date of last significant edit
  DATE = "16-04-13"

  # Authors
  AUTHORS = [
              {:name => "Stephen Wattam", :contact => "http://stephenwattam.com"},
             #{:name => "", :contact => ""}  # Add yourself here if you contribute to LWAC
            ]

  # Print the author string?
  POMPOUS_MODE = true 

  # Checks if a given version of a corpus is compatible 
  def self.storage_is_compatible?(ver)
    COMPATIBLE_CORPUS_VERSIONS.include?(ver)
  end
  
  # Checks if a given version of a client is compatible
  def self.network_is_compatible?(ver)
    COMPATIBLE_NETWORK_VERSIONS.include?(ver)
  end

  # Present the version to the log
  def self.announce_version
    msgs = []
    msgs << "LWAC v#{VERSION} (#{DATE})"

    if POMPOUS_MODE
      auth_string = "by #{AUTHORS[0..3].map{|a| "#{a[:name]} <#{a[:contact]}>"}.join(", ")}"
      auth_string += " and #{AUTHORS.length - 5} more." if AUTHORS.length > 5
      msgs << auth_string
    end

    if $log
      msgs.each{|m| $log.info(m) }
    else
      msgs.each{|m| puts m }
    end
  end

end


