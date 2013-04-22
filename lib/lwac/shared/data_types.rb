# Sets are used to hold links in an unordered, non-duplicated fashion.
require 'set'

module LWAC

# -----------------------------------------------------------------------------
# Holds a datapoint, which is the return value from querying a link
# Immutable.
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

  # Turns HTTP headers into a ruby hash, by parsing
  # them as a string
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



# -----------------------------------------------------------------------------
# Holds a link.  Immutable.
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



# -----------------------------------------------------------------------------
# Holds all data on a given sample, which covers:
#  * A list of Links that are in the sample
#  * Sample start/end times
#
# Will throw errors if one tries to edit it whilst closed.
class Sample
  attr_reader :id, :sample_start_time, :size, :progress
  attr_accessor :sample_end_time, :last_dp_id, :pending, :approx_filesize

  def initialize(id, size, start_id=0, pending_links=Set.new, permit_sampling=false, sample_start_time=Time.now)
    @id                 = id
    
    @size               = size.to_i       # Number of datapoints in sample (read from db)
    @progress           = 0               # How many links have been done in total

    @pending            = pending_links   # links read from db non-contiguously and simply not used yet
    @last_dp_id         = start_id        # Where to start reading next IDs

    # cumulative filesize of all data in sample
    @approx_filesize    = 0

    @permit_sampling    = permit_sampling 
    @sample_start_time  = sample_start_time
    @sample_end_time    = nil
  end
    
  # Start sampling.
  def open_sample 
    @permit_sampling    = true
    @sample_start_time  = Time.now
  end

  def close_sample
    @permit_sampling    = false
    @sample_end_time    = Time.now
  end

  # Has this sample got any links pending?
  def complete?
    @progress >= @size
  end

  # Has the sample been opened?
  def open?
    @permit_sampling
  end

  def link_complete(filesize)
    @approx_filesize += (filesize || 0)
    @progress += 1
  end

  def remaining
    @size - @progress
  end

  # Nicer output
  def to_s
    "<Sample #{@id}, #{@progress}/#{@size} [#{open? ? "open":"closed"}, #{complete? ? "complete":"incomplete"}]>"
  end
end



# -----------------------------------------------------------------------------
# Holds time-dependent parameters of the server, meaning:
#  * The last sample that was completed, and its duration
#  * The current sample in progress
#  * The time when the next sample is due
class ServerState
  attr_accessor :last_sample_id, :current_sample, :next_sample_due, :last_sample_duration
  attr_reader :version

  def initialize(version, last_sample_id=-1, current_sample=nil, next_sample_due=nil)
    @version                    = version
    @last_sample_id             = last_sample_id
    @current_sample             = current_sample        || Sample.new(-1, 0)
    @next_sample_due            = next_sample_due       || Time.now
    @last_sample_duration       = last_sample_duration  || 1
  end
end

end
