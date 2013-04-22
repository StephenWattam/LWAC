require 'lwac/server/storage_manager'
require 'sqlite3'

module LWAC
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
      @config[:schemata_path] = File.join(LWAC::RESOURCE_DIR, 'schemata') if not @config[:schemata_path]
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


end
