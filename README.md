LWAC Downloader
===============
The system comprises two parts: a server which manages sample consistency and data storage, and a client which makes requests to remote resources and reports the results.

Clients and servers are not persistently connected during this process: a client will connect to a server, receive a job, disconnect, execute it, then reconnect to return the results.  Multiple clients thus compete for the single connection, and compete to consume links from the server.  Clients are expected to return to a server repeatedly until told to wait.  They will then back off until more work  is available.

Time is not necessarily expected to be synchronised between server and client, but we recommend the use of NTP to esure that times reported in the results of clients are reliable.


Dependencies
------------
The client and server components have slightly different dependencies: the client need not perform any database lookups or complex storage operations, but it must be capable of performing HTTP and FTP requests.

### Common dependencies

  * Ruby 1.9.1+ (String#encode is required)
  * Marilyn RPC system (gem install -r marilyn-rpc)
  * Eventmachine (should come with Marilyn)

### Client

  * cURL Ruby bindings (gem install -r curb)
  * The 'gethostname' syscall

### Server

  * SQLite3 and Ruby bindings (gem install -r sqlite3)


Configuring
-----------
Both client and server can be configured from their respective configuration file in the config/ directory.  

Each client should have a unique name, as this name is used (along with the  hostname) as its unique ID.  Refer to the inline documentation for more information on configuring the tools.

Executing
---------

### Client
To run the client, 

    $ ./client path/to/config.yml

The client will attempt to contact the server immediately, and continue to run until given a hang-up or halt signal.

### Server
The server must have a directory with a links database in it.  It will fail to start if this links database is not accessible (read-only), or if the directory into which it must write samples is not writable.

The schema for this database is in the resources/ directory.  The import script may be used to import links to a database (it will also create the database if requested).

To run the server:

 1. Generate a links database with all the target URIs for this study
 2. Configure the root directory and database name in config.yml
 3. execute
     
        $ ./server /path/to/config.yml

The server will start up, announce its settings, attempt to resume any existing sample, and then proceed to accept connections in accordance with the sampling policy set in its configuration file.

### Export Tool
The export tool connects to a corpus and extracts information from it, placing it in an output CSV file.  It uses both its own configuration file and the storage definitions of the server config.  To run:
 
        $ ./export /path/to/config.yml

### Import Tool
The import tool can be used to import links to the metadata format from a flatfile.  It will also create the database itself, if requested, from an SQL file stored in ./resources/.


