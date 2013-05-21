require 'lwac/server/storage_manager'
require 'lwac/server/db_conn'

module LWAC

  # Handles the importing of links to a database
  class Importer

    # Create a new Importer object with a given config.  See the import_config docs page for details
    # on the form of this config hash.
    def initialize(config)
      @config = config
      load_server_config

      @dbclass = case(@server_config[:storage][:database][:engine])
        when :mysql
          MySQLDatabaseConnection
        else
          SQLite3DatabaseConnection
        end

      find_schemata
      @enc = @server_config[:client_policy]

    end

    # Create a database at the given path
    def create_db(db_conf)

      # Nice output
      case( db_conf[:engine] )
      when :mysql
        $log.info "Creating MySQL db at using schema from #{@config[:schemata_path]}..."
      else
        $log.info "Creating SQLite3 db at #{db_conf[:engine_conf][:filename]} using schema from #{@config[:schemata_path]}..."
      end

      # Actual stuff---create the db
      @dbclass.create_database( db_conf[:engine_conf] )

      # Apply schema
      db = @dbclass.new( db_conf[:engine_conf] )
      @schemata.each{|s|
        $log.debug "Schema: #{s}"
        schema = File.read(s)
        db.execute(schema, false)
      }
      db.close

      # reporting
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
      @config[:schemata_path] = File.join(LWAC::RESOURCE_DIR, 'schemata', @server_config[:storage][:database][:engine].to_s) if not @config[:schemata_path]
      @schemata     = Dir.glob(File.join(@config[:schemata_path], "*.sql"))
    end

    # Connect to the database with a high level object manager
    def connect_to_db
      # Create db if not already there
      # FIXME: make this conditional work on mysql
      if not @dbclass.database_exists?( @server_config[:storage][:database][:engine_conf] )
        if @config[:create_db] then
          create_db(@server_config[:storage][:database])
        else
          raise "Database does not exist, and current settings do not allow creating it."
        end
      end

      # Create new storage manager with config in read-write mode
      @db = DatabaseStorageManager.new(@server_config[:storage][:database], false) 
    end

    # Close the db connections
    def close
      @db.close 
    end

  end


end
