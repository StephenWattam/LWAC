



module LWAC


  # Basic DB connection superclass
  class DatabaseConnection
    def initialize( config = {} )
    end

    # Close the DB connection
    def close
    end

    def insert(table_name, value_hash)
    end

    def update(table_name, value_hash, where_conditions = "")
    end

    def select(table_name, fields_list, where_conditions = "" )
    end

    def delete(table_name, where_conditions = "")
    end

    def execute(sql, immediate=false)
    end

    def self.create_database( config )
    end

    def self.database_exists?( config )
    end
  end


  # TODO
  class MySQLDatabaseConnection < DatabaseConnection

    def initialize(config = {})

      begin
        require 'mysql2'
      rescue LoadError
        $log.fatal "Your current configuration is trying to use the 'mysql2' gem, but it is not installed."
        $log.fatal "To install, run 'gem install mysql2 --version \"~> 0.3\"'"
        raise "Gem not found."
      end


      @transaction        = false
      @transaction_limit  = config[:transaction_limit] || 0
      @transaction_count  = 0
      
      
      @db = Mysql2::Client.new( config )
      @db.query_options.merge!(:as => :array)

    end

    def close
      @db.close
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

      $log.debug "MySQL: #{sql}"


      # run the query
      #puts "<#{sql.split()[0]}, #{trans}, #{@transaction}>"
      res = @db.query(sql)
      @transaction_count += 1 if @transaction

      # end the transaction if we have called enough statements
      end_transaction if @transaction_count > @transaction_limit

      return res.to_a
    end
    
    # MUST yield for schema to be applied
    def self.create_database( config )

      # Backup...
      base = config[:database]
      raise "No database name set in MySQL database configuration" if not base
      config[:database] = nil

      # Connect
      db = Mysql2::Client.new( config )

      # Create and use
      db.query("CREATE DATABASE `#{db.escape(base.to_s)}`;")
      db.query("USE `#{db.escape(base.to_s)}`;")

      # Restore
      config[:database] = base  

      # And quit.
      db.close
    end

    def self.database_exists?( config )
      exists = false;

      # Backup
      base = config[:database]
      config[:database] = nil;

      # Connect
      db = Mysql2::Client.new(config)

      begin
        db.query("USE `#{db.escape(base.to_s)}`;");
        exists = true
      rescue Mysql2::Error => e
        raise e if not e.to_s =~ /Unknown database/
      end

      # Restore
      config[:database] = base

      # Close
      db.close

      return exists
    end

  private
    def escape( str ) 
      return "'#{@db.escape(str.to_s)}'"
    end

    def disconnect
      end_transaction if @transaction
      @db.close
    end
    
    def start_transaction
      if not @transaction
        @db.query("START TRANSACTION;", false) 
        @transaction = true
      end
    end

    def end_transaction
      if @transaction then
        @db.query("COMMIT;", false) 
        @transaction_count = 0
        @transaction = false
      end
    end

  end






  # ---------------------------------------------------------------------------
  class SQLite3DatabaseConnection < DatabaseConnection

    # Create a new connection to a database at dbpath.
    def initialize(config = {})

      begin
        require 'sqlite3'
      rescue LoadError
        $log.fatal "Your current configuration is trying to use the 'sqlite3' gem, but it is not installed."
        $log.fatal "To install, run 'gem install sqlite3 --version \"~> 1.3\"'"
        raise "Gem not found."
      end


      raise "SQLite3 database not found" if not File.exist?( config[:filename].to_s )

      @transaction        = false
      @transaction_limit  = config[:transaction_limit] || 0
      @transaction_count  = 0
      connect( config[:filename] )
      configure( config[:pragma] || {} )
    end

    # Disconnect from the database.
    def close
      end_transaction if @transaction
      @db.close
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

      # Return if no sql given
      return unless sql

      $log.debug "SQLite3: #{sql}"


      # run the query
      #puts "<#{sql.split()[0]}, #{trans}, #{@transaction}>"
      res = @db.execute(sql)
      @transaction_count += 1 if @transaction

      # end the transaction if we have called enough statements
      end_transaction if @transaction_count > @transaction_limit

      return res
    end
   

    # Create database
    def self.create_database( config )

      begin
        require 'sqlite3'
      rescue LoadError
        $log.fatal "Your current configuration is trying to use the 'sqlite3' gem, but it is not installed."
        $log.fatal "To install, run 'gem install sqlite3 --version \"~> 1.3\"'"
        raise "Gem not found."
      end

      SQLite3::Database.new(config[:filename]) do |db|
      end
    end

    # Check database exists
    def self.database_exists?( config )
      # TODO: check it's a database, not just some random file :-)
      File.exist?(config[:filename]) and not File.directory?(config[:filename])
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

    def start_transaction
      if not @transaction
        $log.debug "SQLite3: BEGIN TRANSACTION;"
        @db.execute("BEGIN TRANSACTION;")
        @transaction = true
      end
    end

    def end_transaction
      if @transaction then
        $log.debug "SQLite3: COMMIT TRANSACTION;"
        @db.execute("COMMIT TRANSACTION;") 
        @transaction_count = 0
        @transaction = false
      end
    end
  end

end

