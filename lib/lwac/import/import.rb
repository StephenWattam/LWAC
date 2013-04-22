# FIXME: this is an inelegant way of managing load paths
$:.unshift( File.join( File.dirname(__FILE__), "../", "server" ) )
$:.unshift( File.join( File.dirname(__FILE__), "../", "shared" ) )
$:.unshift( File.dirname(__FILE__) )

require 'storage_manager'
require 'sqlite3'

class Importer
  def initialize(config)
    @config = config
    find_schemata
    load_server_config
    @enc = @server_config[:client_policy]
  end

  # Create a database at the given path
  def create_db(path)
    $log.info "Creating db at #{path} using schema from #{@config[:schemata_path]}..."
    SQLite3::Database.new(path) do |db|

      @schemata.each{|s|
        $log.debug "Schema: #{s}"
        schema = File.read(s)
        db.execute(schema)
      }
    end
    $log.info "Done!"
  end

  # Import links from a filename
  def import(list)
    begin
      $log.info "Connecting to database..."
      connect_to_db
      $log.info "Importing links..."
      count = 0
      last_notify = Time.now
      File.read(list).force_encoding('UTF-8').each_line{|line|

        # Fix encoding based on config
        line = fix_encoding(line)

        line.chomp!
        if line.length > 0 then
          count += 1
          @db.insert_link(line)
        end

        # Print some progress
        if (count % @config[:notify]) == 0
          notify_progress(count, Time.now - last_notify)
          last_notify = Time.now
        end

      }
      close
      print "\n" if $stdout.tty?
      $log.info "\nAdded #{count} link[s]."
    rescue StandardError => e
      $log.fatal "#{e}"
      $log.debug "#{e.backtrace.join("\n")}"
    end
  end

  # Notify the user of progress
  def notify_progress(count, time_since_last)
    str = "#{count} (#{(@config[:notify].to_f / time_since_last).round}/s)"

    if $stdout.tty? 
      print "\r#{str}" 
    else
      $log.info str
    end
  end

private

  # On user request, set the string encoding to something and provide policy for its fixes
  def fix_encoding(str)
    return str if not @enc[:fix_encoding]
    return str.encode(@enc[:target_encoding], @enc[:encoding_options])
  end

  # Load server configuration file into ram
  def load_server_config
    # Attempt to load server config
    if not File.exist?(@config[:server_config]) then
      raise "Server config file does not exist at #{@config[:server_config]}"
    end
    @server_config = YAML.load_file( File.open(@config[:server_config]) )
  end

  # Looks in the schema directory and finds SQL files
  def find_schemata
    @schemata     = Dir.glob(File.join(@config[:schemata_path], "*.sql"))
  end

  # Connect to the database with a high level object manager
  def connect_to_db
    # Same footwork as in the StorageManager
    @server_config[:storage][:database][:filename] = File.join(@server_config[:storage][:root], @server_config[:storage][:database][:filename])

    # Create db if not already there
    if not File.exist?(@server_config[:storage][:database][:filename])
      if @config[:create_db] then
        create_db(@server_config[:storage][:database][:filename])
      else
        raise "Database file #{@server_config[:storage][:database][:filename]} does not exist, and current settings do not allow creating it."
      end
    end

    # Create new storage manager with config
    @db = DatabaseStorageManager.new(@server_config[:storage][:database])
  end

  # Close the db connections
  def close
    @db.close 
  end

end



# -----------------------------------------------------------------------------------------------------

# 
# # Generically handles an sqlite3 database
# class DatabaseConnection
#   attr_reader :dbpath
# 
#   def initialize(dbpath, transaction_limit=100, pragma={})
#     @transaction        = false
#     @transaction_limit  = transaction_limit
#     @transaction_count  = 0
#     connect( dbpath )
#     configure( pragma )
#   end
# 
#   def close
#     disconnect
#   end
# 
#   def results_as_hash= bool
#     @db.results_as_hash = bool
#   end
# 
#   def results_as_hash
#     @db.results_as_hash
#   end
# 
# 
#   # Run an SQL insert call on a given table, with a hash of data.
#   def insert(table_name, value_hash)
#     raise "Attempt to insert 0 values into table #{table_name}" if value_hash.length == 0
# 
#     escaped_values = [] 
#     value_hash.each{|k, v| escaped_values << escape(v) }
# 
#     return execute("insert into `#{table_name}` (#{value_hash.keys.join(",")}) values (#{escaped_values.join(",")});")
#   end
# 
# 
#   # Run an SQL insert call on a given table, with a hash of data.
#   def update(table_name, value_hash, where_conditions = "")
#     # Compute the WHERE clause.
#     where_conditions = "where #{where_conditions}" if where_conditions.length > 0
# 
#     # Work out the SET clause
#     escaped_values = []
#     value_hash.each{|k, v| 
#       escaped_values << "#{k}='#{escape(v)}'" 
#     }
# 
#     return execute("update `#{table_name}` set #{escaped_values.join(", ")} #{where_conditions};")
#   end
# 
# 
#   # Select certain fields from a database, with certain where field == value.
#   #
#   # Returns a record set (SQlite3)
#   # 
#   # table_name is the name of the table from which to select.
#   # fields_list is an array of fields to return in the record set
#   # where_conditions is a string of where conditions. Careful to escape!!
#   def select(table_name, fields_list, where_conditions = "")
#     where_conditions = "where #{where_conditions}" if where_conditions.length > 0
#     return execute("select #{fields_list.join(",")} from `#{table_name}` #{where_conditions};")
#   end
# 
# 
#   # Delete all items from a table
#   def delete(table_name, where_conditions = "")
#     where_conditions = "where #{where_conditions}" if where_conditions.length > 0
#     return execute("delete from `#{table_name}` #{where_conditions};")
#   end
# 
# 
#   # Execute a raw SQL statement
#   # Set trans = false to force and disable transactions
#   def execute(sql, trans=true)
#     start_transaction if trans
#     end_transaction if @transaction and not trans 
# 
#     #puts "DEBUG: #{sql}"
# 
#     # run the query
#     #puts "<#{sql.split()[0]}, #{trans}, #{@transaction}>"
#     res = @db.execute(sql)
#     @transaction_count += 1 if @transaction
# 
#     # end the transaction if we have called enough statements
#     end_transaction if @transaction_count > @transaction_limit
# 
#     return res
#   end
# private
#   def escape( str )
#     "'#{SQLite3::Database::quote(str.to_s)}'"
#   end
# 
#   def connect( dbpath )
#     # Reads data from the command line, and loads it
#     raise "Cannot access database #{dbpath}" if not File.readable_real?(dbpath)
#     
#     # If the db file is readable, open it.
#     @dbpath = dbpath
#     @db = SQLite3::Database.new(dbpath)
#   end
# 
#   def configure( pragma )
#     pragma.each{|pragma, value| 
#       execute("PRAGMA #{pragma}=#{value};", false) # execute without transactions
#     }
#   end
# 
#   def disconnect
#     end_transaction if @transaction
#     @db.close
#   end
#   
#   def start_transaction
#     if not @transaction
#       @db.execute("BEGIN TRANSACTION;") 
#       @transaction = true
#     end
#   end
# 
#   def end_transaction
#     if @transaction then
#       @db.execute("COMMIT TRANSACTION;") 
#       @transaction_count = 0
#       @transaction = false
#     end
#   end
# end




