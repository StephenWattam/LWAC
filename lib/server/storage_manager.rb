require File.join(File.dirname(__FILE__), "../shared/data_types.rb")
require File.join(File.dirname(__FILE__), "../shared/multilog.rb")


require 'yaml'
require 'sqlite3'
require 'fileutils'
require 'set'





# Generically handles an sqlite3 database
class DatabaseConnection
  attr_reader :dbpath

  def initialize(dbpath, transaction_limit=100, pragma={})
    @transaction        = false
    @transaction_limit  = transaction_limit
    @transaction_count  = 0
    connect( dbpath )
    configure( pragma )
  end

  def close
    disconnect
  end

  def results_as_hash= bool
    @db.results_as_hash = bool
  end

  def results_as_hash
    @db.results_as_hash
  end


  # Run an SQL insert call on a given table, with a hash of data.
  def insert(table_name, value_hash)
    raise "Attempt to insert 0 values into table #{table_name}" if value_hash.length == 0

    escaped_values = [] 
    value_hash.each{|k, v| escaped_values << escape(v) }

    return execute("insert into `#{table_name}` (#{value_hash.keys.join(",")}) values (#{escaped_values.join(",")});")
  end


  # Run an SQL insert call on a given table, with a hash of data.
  def update(table_name, value_hash, where_conditions = "")
    # Compute the WHERE clause.
    where_conditions = "where #{where_conditions}" if where_conditions.length > 0

    # Work out the SET clause
    escaped_values = []
    value_hash.each{|k, v| 
      escaped_values << "#{k}='#{escape(v)}'" 
    }

    return execute("update `#{table_name}` set #{escaped_values.join(", ")} #{where_conditions};")
  end


  # Select certain fields from a database, with certain where field == value.
  #
  # Returns a record set (SQlite3)
  # 
  # table_name is the name of the table from which to select.
  # fields_list is an array of fields to return in the record set
  # where_conditions is a string of where conditions. Careful to escape!!
  def select(table_name, fields_list, where_conditions = "")
    where_conditions = "where #{where_conditions}" if where_conditions.length > 0
    return execute("select #{fields_list.join(",")} from `#{table_name}` #{where_conditions};")
  end


  # Delete all items from a table
  def delete(table_name, where_conditions = "")
    where_conditions = "where #{where_conditions}" if where_conditions.length > 0
    return execute("delete from `#{table_name}` #{where_conditions};")
  end


  # Execute a raw SQL statement
  # Set trans = false to force and disable transactions
  def execute(sql, trans=true)
    start_transaction if trans
    end_transaction if @transaction and not trans 

    #puts "DEBUG: #{sql}"

    # run the query
    #puts "<#{sql.split()[0]}, #{trans}, #{@transaction}>"
    res = @db.execute(sql)
    @transaction_count += 1 if @transaction

    # end the transaction if we have called enough statements
    end_transaction if @transaction_count > @transaction_limit

    return res
  end
  
private
  def escape( str ) 
    "'#{SQLite3::Database::quote(str.to_s)}'"
  end

  def connect( dbpath )
    # Reads data from the command line, and loads it
    raise "Cannot access database #{dbpath}" if not File.readable_real?(dbpath)
    
    # If the db file is readable, open it.
    @dbpath = dbpath
    @db = SQLite3::Database.new(dbpath)
  end

  def configure( pragma )
    pragma.each{|pragma, value| 
      execute("PRAGMA #{pragma}=#{value};", false) # execute without transactions
    }
  end

  def disconnect
    end_transaction if @transaction
    @db.close
  end
  
  def start_transaction
    if not @transaction
      @db.execute("BEGIN TRANSACTION;") 
      @transaction = true
    end
  end

  def end_transaction
    if @transaction then
      @db.execute("COMMIT TRANSACTION;") 
      @transaction_count = 0
      @transaction = false
    end
  end
end





# Database engine for links only, retrieval only.
class DatabaseStorageManager < DatabaseConnection
  def initialize(config)
    $log.debug "Connecting to database at #{config[:filename]}"
    super(config[:filename], config[:transaction_limit], config[:pragma])
    $log.debug "Connected to database at #{config[:filename]}"

    # Set config, hash as default      
    @config             = config
    results_as_hash     = true

  end

  # Retrieve a list of links from the db
  def read_links(range_low=nil, range_high=nil)
    where = ""
    where = "#{@config[:fields][:id]} < #{range_high} AND #{@config[:fields][:id]} > #{range_low}" if range_low and range_high

    links = select(@config[:table], @config[:fields].values, where)
    links.map!{|id, uri| Link.new(id, uri) }
  end

  # Read all the link IDs
  def read_link_ids()
    Set.new(select(@config[:table], [@config[:fields][:id]]).flatten)
  end

  # Retrieve a single link with a given ID
  def read_link(id)
    link = select(@config[:table], @config[:fields].values, "#{@config[:fields][:id]} == #{id}")
    return Link.new(link[0][0], link[0][1])
  end
end





# Serialise direct to a file using YAML.
module YAML
  def self.dump_file(obj, fn)
     self.dump(obj, File.open(fn, 'w')).close
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

    # Database storage
    config[:database][:filename] = File.join(config[:root], config[:database][:filename])
    @db = DatabaseStorageManager.new(config[:database])

    # Try to load the current server state
    @state_filename = File.join(@root, config[:state_file])
    if(File.exist?(@state_filename))
      @state = YAML.load_file(@state_filename)
    else
      $log.debug "No state.  Creating a new state file at #{@state_filename}"
      @state = ServerState.new()
      YAML.dump_file(@state, @state_filename)
    end

    # Create the sample subdir
    FileUtils.mkdir_p(get_sample_filepath()) if not File.exist?(get_sample_filepath)
  end

  # Read some links from the database
  def read_links(range_low = nil, range_high = nil)
    @db.read_links(range_low, range_high)
  end

  # Read a single ID
  def read_link(id)
    @db.read_link(id)
  end

  # Read all IDs as a set
  def read_link_ids()
    @db.read_link_ids
  end

  ## Datapoint read/write
  # Write a datapoint to disk
  def write_datapoint(dp, sample = @state.current_sample)
    $log.debug "Writing datapoint #{dp.link.id} (sample #{sample.id}) to disk."
    dp_path = get_dp_filepath(dp, sample.id)
    YAML.dump_file( dp, dp_path)
  end

  # Read a datapoint from disk
  def read_datapoint(dp_id, sample = @state.current_sample)
    $log.debug "Reading datapoint #{dp_id} (sample #{sample.id}) from disk."
    dp_path = get_dp_filepath(dp_id, sample.id)
    YAML.load_file( dp_path )
  end

  ## Datapoint disk lookup


  ## Sample read/write
  # Write a finalised sample to disk in its proper location.
  def write_sample(sample = @state.current_sample)
    sample_path = File.join( get_sample_filepath(sample.id), @config[:sample_filename])
    YAML.dump_file( sample, sample_path )
  end

  # Read a finalised sample ID from disk.
  # raises Errno::ENOENT if not there
  def read_sample(sample_id = @state.last_sample_id)
    sample_path = File.join( get_sample_filepath(sample_id), @config[:sample_filename])
    YAML.load_file( sample_path )
  end


  ## Sample disk lookup

  # Ensure a sample has all of its files on disk,
  # and that they are readable
  def validate_sample(sample_id, verify_datapoints=true)
    $log.debug "Validating sample #{sample_id}..."
    # Check the file exists
    begin
      sample = read_sample(sample_id)
    rescue Exception => e
      raise "Error loading sample metadata: #{e.to_s}"
    end

    # Load all links and work out which files should
    # actually be in the dir
    all_link_ids = read_link_ids
    sampled = all_link_ids - sample.pending_links

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
    return File.join(filepath, "#{id.to_s}.yml")
  end

  # Write the server state to disk
  def write_state
    YAML.dump_file( @state, @state_filename)
  end

end


private


# Test script
if __FILE__ == $0 then

  $log = MultiOutputLogger.new($stdout)
  $log.set_level(:default, Logger::DEBUG)

  config = YAML.load_file("../config/server.yml")

  sm = StorageManager.new(config[:storage])
  sm.read_links.each{|link|
    puts "LINK: #{link}"
  }

end

