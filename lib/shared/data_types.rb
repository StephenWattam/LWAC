require 'set'

# Holds a datapoint, which is the return value from querying a link
# Once created, should be immutable
class DataPoint
  attr_reader :link, :headers, :head, :body, :response_properties, :client_id, :error

  def initialize(link, headers, head, body, response_properties, client_id, error=nil)
    @link                 = link
    @headers              = headers
    @headers              = DataPoint.headers_to_hash(@headers) if not @headers.is_a?(Hash)
    @head                 = head
    @body                 = body
    @response_properties  = response_properties
    @error                = error
    @client_id            = client_id
  end

  def to_s
    "<DataPoint #{@link.to_s}>"
  end

  def self.headers_to_hash(header_string)
    headers = {}
    header_string.each_line{|ln|
      if(ln.index(':')) then
        key = ln[0..(ln.index(':')-1)].strip
        val = ln[(ln.index(':')+1)..-1].strip
        headers[key] = val
      end
    }
    return headers
  end

end


# Holds a link.  Immutable and should not be changed ever
class Link
  attr_reader :id, :uri

  def initialize(id, uri)
    @id = id
    @uri = uri
  end

  def to_s
    "<#{@id}|#{@uri}>"
  end
end


class Sample
  attr_reader :id, :pending_links, :sample_start_time, :size
  attr_accessor :sample_end_time

  def initialize(id, pending_links=[], permit_sampling=false, sample_start_time=Time.now)
    @id             = id
    @pending_links  = pending_links || Set.new
    @size           = @pending_links.length
    @pending_links = Set.new(@pending_links) if not @pending_links.is_a?(Set)

    @permit_sampling    = permit_sampling 
    @sample_start_time  = sample_start_time
    @sample_end_time    = nil
  end

  # Start sampling.
  def open_sample 
    @permit_sampling    = true
    @sample_start_time  = Time.now
  end

  # Has this sample got any links pending?
  def complete?
    @pending_links.length == 0
  end

  # Has the sample been opened?
  def open?
    @permit_sampling
  end

  # Remove a link from the pending queue
  def remove_link(id)
    raise "Sampling without opening the sample first!" if not @permit_sampling
    @pending_links.delete(id)
  end

  # Nicer output
  def to_s
    "<Sample #{@id}, #{@pending_links.length}/#{@size} [#{open? ? "open":"closed"}, #{complete? ? "complete":"incomplete"}]>"
  end

  ## Output to a nicer YAML format
  #def to_hash
    #hash                      = {}
    #hash[:id]                 = @id
    #hash[:pending_link_ids]   = @pending_links.map{|l| l.id}
    #hash[:permit_sampling]    = @permit_sampling
    #hash[:sample_start_time]  = @sample_start_time
    #return hash
  #end

  #def to_yaml
    #return to_hash.to_yaml
  #end

  ## Load a Sample object from a hash as loaded by a YAML file
  #def self.from_hash(hash, db)
    ## Read links from the database
    #links = []
    #$log.debug "Loading #{hash[:pending_link_ids].length} links from the database."
    #hash[:pending_link_ids].each{|lid|
      #links << db.read_link(lid)
    #}
    #$log.debug "Done."

    #return Sample.new(hash[:id], links, hash[:permit_sampling], hash[:sample_start_time])
  #end
end


# Holds time-dependent parameters of the server
class ServerState
  attr_accessor :last_sample_id, :current_sample, :next_sample_due, :last_sample_duration

  def initialize(last_sample_id=-1, current_sample=nil, next_sample_due=nil)
    @last_sample_id             = last_sample_id
    @current_sample             = current_sample        || Sample.new(-1, [])
    @next_sample_due            = next_sample_due       || Time.now
    @last_sample_duration       = last_sample_duration  || 1
  end

  #def to_hash
    #hash = { :last_sample_id => @last_sample_id,
             #:current_sample => @current_sample.to_hash,
             #:next_sample_due => @next_sample_due }
    #return hash
  #end

  #def to_yaml
    #return to_hash.to_yaml
  #end

  #def from_hash(hash, db)
    #ServerState.new(hash[:last_sample_id], 
                    #Sample.from_hash(hash[:current_sample], db), 
                    #hash[:next_sample_due])
    
  #end
end
