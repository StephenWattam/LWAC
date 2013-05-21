

require 'lwac/shared/serialiser'
require 'lwac/shared/identity'
require 'lwac/shared/multilog'
require 'lwac/shared/data_types'
require 'lwac/server/db_conn'

require 'fileutils'
require 'set'

module LWAC



  # Database engine for links only.  
  #
  # By default this is read-only, as all but the import tool should not be able
  # to edit the database.
  class DatabaseStorageManager
    def initialize(config, read_only=true)
      
      
      $log.debug "Connecting to #{config[:engine]} database..."
      klass = case(config[:engine])
              when :mysql
                MySQLDatabaseConnection
              else
                SQLite3DatabaseConnection
              end
      @db = klass.new( config[:engine_conf] )
      $log.debug "Connected to database."

      # Set config, hash as default      
      @config             = config

      # Read-only mode designed for servers.
      @read_only          = read_only
    end

    # Insert a link
    def insert_link(uri)
      raise "Attempt to insert link whilst in read-only mode." if @read_only
      @db.insert(@config[:table], {"uri" => uri})
    end

    # Retrieve a list of links from the db
    def read_links(range_low=nil, range_high=nil)
      where = ""
      where = "#{@config[:fields][:id]} < #{range_high} AND #{@config[:fields][:id]} > #{range_low}" if range_low and range_high

      links = @db.select(@config[:table], @config[:fields].values, where)
      links.map!{|id, uri| Link.new(id, uri) }
    end

    # Read all the link IDs
    # TODO --- what if lowest ID is below 0?
    def read_link_ids(from=0, n=nil)
      where = "id > #{from.to_i}" 
      where += " limit #{n}" if n
      
      ids = @db.select(@config[:table], [@config[:fields][:id]], where).flatten
      return Set.new(ids)
    end

    # Retrieve a single link with a given ID
    def read_link(id)
      link = @db.select(@config[:table], @config[:fields].values, "#{@config[:fields][:id]} == #{id}")
      return Link.new(link[0][0], link[0][1])
    end

    # Retrieve many links from an array of IDs
    def read_links_from_array(ids = [])
      links = []
      @db.select(@config[:table], @config[:fields].values, "#{@config[:fields][:id]} in (#{ids.join(',')})").each{|l|
        links << Link.new(l[0], l[1])
      }

      return links
    end

    # Count the number of links
    def count_links(min_id = nil)

      where = nil
      if min_id != nil then
        where = "#{@config[:fields][:id]} > #{min_id}"
      end

      count = @db.select(@config[:table], ["count(*)"], where)
      return count[0][0].to_i
    end

    def close
      @db.close
    end
  end







  # Handles storage, both file and database based
  class StorageManager

    # Allow the user to access the server state
    attr_reader :state

    def initialize(config)
      @config         = config
      @root           = config[:root]
      @files_per_dir  = config[:files_per_dir]

      # Debug info
      $log.debug "Storage manager starting, serialising using #{config[:serialiser]}"
      @serialiser = Serialiser.new(config[:serialiser])

      # Database storage
      @db = DatabaseStorageManager.new(config[:database])

      # Try to load the current server state
      @state_filename = File.join(@root, config[:state_file])
      if(File.exist?(@state_filename))
        @state = @serialiser.load_file(@state_filename)

        # Version check on the state file that describes the corpus
        if not @state.respond_to?(:version) or not Identity::storage_is_compatible?(@state.version) then
          if @state.respond_to?(:version)
            $log.fatal "The corpus you are trying to load was written by LWAC version #{@state.version}" 
          else 
            $log.fatal "No version info---the corpus was written by a prerelease version of LWAC"
          end
          $log.fatal "This server is only compatible with versions: #{Identity::COMPATIBLE_VERSIONS.sort.join(", ")}"
          raise "Incompatible storage format"
        end

      else
        $log.debug "No state.  Creating a new state file at #{@state_filename}"
        @state = ServerState.new(LWAC::VERSION)
        @serialiser.dump_file(@state, @state_filename)
      end

      # Create the sample subdir
      FileUtils.mkdir_p(get_sample_filepath()) if not File.exist?(get_sample_filepath)
    end

    # Read some links from the database using either a range, 
    # or an array, depending on the first argument
    def read_links(range_low = nil, range_high = nil)
      return @db.read_links_from_array(range_low) if range_high == nil and range_low.is_a?(Array)
      @db.read_links(range_low, range_high)
    end

    # Read a single ID
    def read_link(id)
      @db.read_link(id)
    end

    # Read all IDs as a set
    def read_link_ids(from=nil, n=nil)
      @db.read_link_ids(from, n)
    end

    # Count links
    # optionally min_id is the lowest id to count from
    def count_links(min_id=0)
      @db.count_links(min_id)
    end

    ## Datapoint read/write
    # Write a datapoint to disk
    def write_datapoint(dp, sample = @state.current_sample)
      $log.debug "Writing datapoint #{dp.link.id} (sample #{sample.id}) to disk."
      dp_path = get_dp_filepath(dp, sample.id)
      @serialiser.dump_file( dp, dp_path)
    end

    # Read a datapoint from disk
    def read_datapoint(dp_id, sample = @state.current_sample)
      $log.debug "Reading datapoint #{dp_id} (sample #{sample.id}) from disk."
      dp_path = get_dp_filepath(dp_id, sample.id)
      @serialiser.load_file( dp_path )
    end

    ## Datapoint disk lookup


    ## Sample read/write
    # Write a finalised sample to disk in its proper location.
    def write_sample(sample = @state.current_sample)
      sample_path = File.join( get_sample_filepath(sample.id), @config[:sample_filename])
      @serialiser.dump_file( sample, sample_path )
    end

    # Read a finalised sample ID from disk.
    # raises Errno::ENOENT if not there
    def read_sample(sample_id = @state.last_sample_id)
      sample_path = File.join( get_sample_filepath(sample_id), @config[:sample_filename])
      @serialiser.load_file( sample_path )
    end


    ## Sample disk lookup

    # Ensure a sample has all of its files on disk,
    # and that they are readable
    def validate_sample(sample_id, verify_datapoints=true)
      $log.debug "Validating sample #{sample_id}..."
      # Check the file exists
      begin
        sample = read_sample(sample_id)
      rescue StandardError => e
        raise "Error loading sample metadata: #{e.to_s}"
      end

      # Load all links and work out which files should
      # actually be in the dir
      all_link_ids = read_link_ids
      sampled = all_link_ids.delete_if{|x| x > sample.last_dp_id} - sample.pending # FIXME

      # Now check they all exist
      if(verify_datapoints) then
        $log.debug "Validating datapoints for #{sample}..."
        sampled.each{ |link_id|
          path = get_dp_filepath( link_id, sample_id )


          raise "Datapoint #{link_id} is missing."          if not File.readable? path
          raise "Cannot read datapoint with ID #{link_id}"  if not File.readable? path
        }
      end

      $log.info "Sample #{sample} passed validation (datapoints checked? #{verify_datapoints})"
      return true
    end


    # Update the server state
    def update_state(state)
      @state = state
      write_state
    end

    # Close the resource and make sure everything is dumped to disk
    def close
      $log.fatal "Closing storage manager, writing state to #{@state_filename}"
      write_state
      @db.close
    end

    # Get a sample filepath, parent of a datapoint filepath
    def get_sample_filepath(sample_id=nil, dir=nil, ensure_exists=false)
      filepath = File.join( @root, @config[:sample_subdir] )
      filepath = File.join( filepath, sample_id.to_s )            if sample_id
      filepath = File.join( filepath, dir.to_s )                  if dir

      FileUtils.mkdir_p(filepath) if not File.exist?(filepath)

      return filepath
    end

    # Get a datapoint filepath
    def get_dp_filepath(id_or_dp, sample_id = @state.current_sample.id)
      # Get the numeric link ID from a datapoint, link or raw ID
      id = id_or_dp.to_i        if(id_or_dp.is_a? Integer)
      id = id_or_dp.id          if(id_or_dp.is_a? Link)
      id = id_or_dp.link.id     if(id_or_dp.is_a? DataPoint)
    
      # Break it up into blocks of @files_per_dir
      dir = (id.to_i/@files_per_dir).floor

      # Ensure dir exists
      filepath = get_sample_filepath( sample_id, dir, true)

      # Join the datapoint ID
      return File.join(filepath, "#{id.to_s}")
    end

    # Write the server state to disk
    def write_state
      @serialiser.dump_file( @state, @state_filename)
    end

  end

end
