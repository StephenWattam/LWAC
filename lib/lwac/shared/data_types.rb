# Sets are used to hold links in an unordered, non-duplicated fashion.
require 'set'



module LWAC

  # -----------------------------------------------------------------------------
  # Holds a datapoint, which is the return value from querying a link
  # Immutable.
  class DataPoint
    attr_reader :link, :headers, :head, :body, :response_properties, :client_id, :error

    # Methods to extract from Curl::Easy
    INTERESTING_CURL_EASY_METHODS = %w{
        body_str
        cacert
        cert
        cert_key
        certtype
        connect_time
        connect_timeout
        content_type
        cookiefile
        cookiejar
        cookies
        dns_cache_timeout
        download_speed
        downloaded_bytes
        downloaded_content_length
        enable_cookies?
        encoding
        fetch_file_time?
        file_time
        follow_location?
        ftp_commands
        ftp_entry_path
        ftp_filemethod
        ftp_response_timeout
        header_in_body?
        header_size
        header_str
        headers
        http_auth_types
        http_connect_code
        ignore_content_length?
        interface
        last_effective_url
        local_port
        local_port_range
        low_speed_limit
        low_speed_time
        max_redirects
        multipart_form_post?
        name_lookup_time
        num_connects
        os_errno
        password
        post_body
        pre_transfer_time
        primary_ip
        proxy_auth_types
        proxy_port
        proxy_tunnel?
        proxy_type
        proxy_url
        proxypwd
        redirect_count
        redirect_time
        redirect_url
        request_size
        resolve_mode
        response_code
        ssl_verify_host
        ssl_verify_peer?
        ssl_version
        start_transfer_time
        status
        timeout
        total_time
        unrestricted_auth?
        upload_speed
        uploaded_bytes
        uploaded_content_length
        url
        use_netrc?
        use_ssl
        useragent
        username
        userpwd
        verbose?
    }


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
      header_string.each_line do |ln|
        if ln.index(':')
          key = ln[0..(ln.index(':') - 1)].strip
          val = ln[(ln.index(':') + 1)..-1].strip
          headers[key] = val
        end
      end
      return headers
    end

    # Converts a Curl result and an originating link
    # into a datapoint with a standard character encoding, etc.
    def self.from_request(config, link, res, client_id, error)
      # DataPoint.new(link, headers, head, body, response_properties, @client_id, nil)
      require 'curl'  # 

      # Fix encoding of head if required
      $log.debug "Fixing header encoding..."
      body                = fix_encoding(res.body_str.to_s, config)

      # Fix encoding of head if required
      $log.debug "Fixing header encoding..."
      head                = fix_encoding(res.header_str.to_s, config)

      # Generate a hash of headers
      $log.debug "Parsing headers..."
      header_hash = DataPoint.headers_to_hash(head)


      # Per-regex MIME handling 
      $log.debug "Passing MIME filter in #{config[:mimes][:policy]} mode..."
      allow_mime = (config[:mimes][:policy] == :blacklist)
      encoding   = header_hash["Content-Type"].to_s
      config[:mimes][:list].each{|mime_rx|
        if encoding.to_s =~ Regexp.new(mime_rx, config[:mimes][:ignore_case]) then
          allow_mime = (config[:mimes][:policy] == :whitelist)
          $log.debug "Link #{link.id} matched MIME regex #{mime_rx}"
        end
      }
      body                  = '' unless allow_mime

      # Load stuff out of response object.
      $log.debug "Extracting #{INTERESTING_CURL_EASY_METHODS.length} details from result..."
      response_properties = {}
      INTERESTING_CURL_EASY_METHODS.map { |m| response_properties[m.to_sym] = res.send(m.to_sym) }
      response_properties[:mime_allowed] = allow_mime

      DataPoint.new(link,
                    header_hash,
                    head,
                    body,
                    response_properties,
                    client_id,
                    error
                   )
    end

    private

    # On user request, set the string encoding to something and provide policy for its fixes
    def self.fix_encoding(str, config)
      return str if not config[:fix_encoding]
      return str.encode(config[:target_encoding], config[:encoding_options])
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
