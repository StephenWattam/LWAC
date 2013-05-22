Server Configuration
====================
The server's configuration file is a valid ruby Hash object, expressed in YAML.  As such, it starts with a single line containing three dashes, and follows a key-value structure throughout.  It may loosely be separated into a number of sections, forming the top level of this tree.

For help interpreting this document, see [Reading Config Documentation](config_docs.html)

Storage
-------
Storage is defined by the `/storage/` key, and contains details on the corpus and its metadata database.

### Corpus Details

 * `root`            --- The root directory of the corpus, relative to the server binary.
 * `state_file`      --- The name of the file where server state will be stored.  This contains a list of incomplete links for the current sample.
 * `sample_subdir`   --- The name of the directory within the corpus where samples will be stored.
 * `sample_filename` --- The filename where summary details on a particular sample are stored.
 * `files_per_dir`   --- How many files to store in each directory below the `sample_subdir`.  This is set to avoid overloading filesystems that have finite inode tables.
 * `serialiser`      --- The serialisation method used to write to disk.  Supported methods are `:marshal`, `:yaml` or `:json`.  `:marshal` is fastest and recommended unless you desperately need to access the corpus using languages other than ruby.

For example:

    :storage:                       
      :root: corpus                   
      :state_file: state          
      :sample_subdir: samples         
      :sample_filename: sample    
      :files_per_dir: 1000            
      :serialiser:  :marshal          
      :database: 
         ...


### Database Details
The database is configured in `/storage/database` and consists of two main blocks:

 * `engine` --- Either `:sqlite` for the SQLite3 database engine or `:mysql` for mysql.  You must install the appropriate dependency for the engine you select.
 * `engine_conf{}` --- Configuration parameters for a given engine.  See below for examples of each.
 * `table`             --- The table name where links to be downloaded are stored
 * `fields`            --- Contains information on the links table's fields
 * `fields/id`         --- The field name containing the link ID
 * `fields/uri`        --- The field name contain the URI to request from a remote server.

For example:

    :table: links                   
    :fields:                        
      :id: id                         
      :uri: uri                       
    :engine: :mysql
    :engine_conf:                       
      ...


#### SQLite3
The SQLite3 engine is rather heavily optimised for read speed from the database, and is recommended if you want speed or have a smaller corpus.  Its configuration parameters are thus:

 * `database/transaction_limit` --- How many queries to run per transaction.  Larger numbers speed up access at the expense of data security.
 * `database/pragma{}`          --- A key-value list of pragma statements to configure the SQLite3 database.  These configure the database, and take the form of a list of key-value strings.  A full list of SQLite3 pragma statements is available on [their website](http://www.sqlite.org/pragma.html)
 * `transaction_limit` --- The number of calls to make per transaction.  May provide a minor speed increase if large, but most database access is read only anyway.
 * `filename` --- The position of the database file, relative to `pwd`

For example:

    :engine: :mysql              
    :engine_conf:
      :filename: corpus/links.db      
      :transaction_limit: 100         
      :pragma:                        # Custom pragmas.  See SQLite's docs.
        "locking_mode": "EXCLUSIVE"     # Do not allow others to access the db when the server is running
        "cache_size": 20000             # Allow a large cache
        "synchronous": 0                # Asynchronous operations speed things up a lot
        "temp_store": 2                 # Use temp storage

#### MySQL
The MySQL engine's configuration parameters are largely defined by the gem.  Full documentation is available on the [github page](https://github.com/brianmario/mysql2), and common parameters are listed below:

 * `username` --- The uername to log in with
 * `password` --- The password to use when connecting to the mysql server
 * `host` --- The hostname at which the mysql server is listening (omit this if using a socket)
 * `port` --- The port on which the mysql server is listening (omit this if using a socket)
 * `socket` --- The filepath of a socket over which to talk to the mysql server
 * `database` --- The name of the database where the links table will be stored
 * `encoding` --- The character encoding to use.  'utf8' is _strongly_ recommended.

For example:

    :engine: :sqlite
    :engine_conf:                       # Options from https://github.com/brianmario/mysql2
      :username: lwac
      :password: lwacpass
      # :host: localhost
      # :port: 3345
      :socket: /var/run/mysqld/mysqld.sock
      :database: lwac
      :encoding: 'utf8'
      :read_timeout: 10                 #seconds
      :write_timeout: 10                #seconds
      :connect_timeout: 10              #seconds
      :reconnect: true                  #/false
      :local_infile: true               #/false


Sampling Policy
---------------
The sampling policy used by the server is defined by three parameters, *count*, *duration* and *alignment*.  

 * `sample_limit` --- Sample at most this number of samples.  Note that the IDs start from 0, so the last sample will have the ID `sample_limit - 1`.  The server will quit when trying to open the `n+1`th sample.
 * `sample_time` --- A sample's *duration* is the minimum time a sample may take.  For example, if this is a daily sample, it should be set to 84600 (the number of seconds in a day) in order to sample once at midnight each day.
 * `sample_alignment` --- A sample's *alignment* defines whereabouts within each sample time the sample may start.  Using the above example, setting this to 7200 would cause samples to begin at 2am each day.

Note that if a sample takes more than `sample_time` to run, it will overlap and cancel the next sample.  This is to prevent misalignment with the other datapoints in the sample, and is preferrable in many analyses to a series of messily-timed run-on samples.  The code that selects the samples thus follows this algorithm:

 * Round down to the last valid sample time (`time = Time.at(((Time.now.to_i / @config[:sample_time]).floor * @config[:sample_time]) + @config[:sample_alignment])`)
 * While `time < Time.now`
   * increment the prospective time by the `sample_time`

If you wish to edit the sample computation algorithm, it resides in `lib/server/consistency_manager.rb`, under the method `compute_next_sample_time`.

For example:

    :sampling_policy:               
      :sample_limit:  0               
      :sample_time: 60
      :sample_alignment: 0



Client Policy
-------------
This section describes the properties each client must inherit from its server.  It describes things such as how the client appears to external websites, and how it normalises and packages its data before upload to the server.

 * `dry_run` --- Boolean.  Set to `true` to disable web access on the client, so that it samples empty datapoints.
 * `max_body_size` --- Stop downloading when this number of bytes have been downloaded.  Used to prevent aberrantly large files from filling RAM or disk storage.
 * `fix_encoding` --- Boolean. Should the encoding be normalised to `target_encoding`?
 * `target_encoding` --- The name of an encoding to normalise to.  Default is 'UTF-8', but anything supported by Ruby's String#encode method will work
 * `encoding_options` --- Options hash passed to String#encode, may include:
   * `encoding_options\invalid` --- If value is `:replace` , replaces undefined chars with the `:replace` char
   * `encoding_options\undef` --- If value is `:replace` , replaces undefined chars with the `:replace` char
   * `encoding_options\replace` --- The char to use in replacement, defaults to uFFFD for unicode and '?' for other targets
   * `encoding_options\fallback{}` --- A key-value table of characters to replace
   * `encoding_options\xml` --- Either `:text` or `:attr`.  If `:text`, replaces things with hex entities, if `:attr`, it also quotes the entities "&amp;quot;"
   * `encoding_options\cr_newline` --- Boolean. Replaces LF(\n) with CR(\r) if true
   * `encoding_options\lf_newline` --- Boolean. Replaces LF(\n) with CRLF(\r\n) if true
   * `encoding_options\universal_newline` --- Boolean.  Replaces CRLF(\r\n) and CR(\r) with LF(\n) if true

Clients use cURL to download links, using the `curb` library, and may thus be configured with custom request parameters and other options.  The options below are applied by setting properties on the cURL object, and as such anything may be provided as a key that is in the [curb documentation](https://rubygems.org/gems/curb), such as 'verbose' or control over SSL.  By default, SSL options are overridden to accept connections without verifying certificates.

 * `curl_workers{}` --- Defines properties of the CURl workers that contact web servers.
   * `max_redirect` --- How many HTTP redirects should be followed before giving up?
   * `useragent` --- The user agent to show to the remote server
   * `follow_location` --- Should the agent follow location headers?
   * `timeout` --- Overall timeout, in seconds, for the whole request.
   * `connect_timeout` --- TCP connect timeout
   * `dns_cache_timeout` --- DNS lookup timeout

MIME type handling can be controlled in a rudimentary manner to prevent superfluous saving of binary data.  This is controlled using the `Content-type` field of the response headers, and takes the form of a whitelist or blacklist based on regular expressions.  Any link that is 'denied' has its body content wiped and a flag set in its datapoint metadata, but otherwise remains intact. It is configured by the structure called `:mimes`.

 * `mimes{}` --- Defines mime-type acceptance handling
   * `policy` --- Either `:whitelist` to only accept the items matching the list, or `:blacklist` to only decline the items on the list.
   * `ignore_case` --- Should the regexp matching be case-insensitive?
   * `list[]` --- A list of regular expressions.  If one matches, depending on white/blacklist configuration, the body will be blanked.

For example:

    :client_policy:
      :dry_run: false
      :fix_encoding: true
      :target_encoding: UTF-8
      :encoding_options:
        :invalid: :replace
        :undef: :replace                         
        #:replace: '?'                            
        #:fallback:                               
          #'from': 'to'
          #'from2': 'to2'
        #:xml: :attr                              
        #:cr_newline: true                        
        #:crlf_newline:                           
        :universal_newline: true
      :max_body_size:  20971520
      :mimes:
        :policy: :whitelist
        :ignore_case: true
        :list:
          - ^text\/?.*$       # text-only mimes
         #- ^.+$              # anything with a valid content-type
      :curl_workers:
        :max_redirects: 5
        :useragent: ! '"Mozilla/5.0 (Windows; U; Windows NT 6.0; en-US; rv:1.9.2.11) Gecko/20101012 Firefox/3.6.11"'
        :enable_cookies: true
        # :headers: "Header: String"
        :verbose: false 
        :follow_location: true
        :timeout: 60
        :connect_timeout: 10
        :dns_cache_timeout: 10
        :ftp_response_timeout: 10

Client Management
-----------------
The server's responsibilities for managing clients as they connect and process work mean that it must present meaningful time limits on these connections (lest clients crash or misbehave).  These settings govern the rate at which clients are presumed to work, before the server starts re-assigning their work to other clients.


The client is given only a finite time to complete its work before the server will assume it has died and re-assign its links elsewhere.  This is controlled by two parameters---one for clients that have not been deen before, and one that modifies the dynamic timeout computed by the server.

 * `time_per_link` --- How long, in seconds, a new client is given per link to download a batch.  Clients typically download fairly fast, so this should be quite low (below 5).
 * `dynamic_time_overestimate` --- How much to multiply the client's last performance by when computing a timeout i.e. value of "1.2" will give 20% overhead.

These next to parameters define how long clients are told to wait when they contact the server but find no work available (for example, no sample is open right now).

 * `empty_client_backoff` --- If no links are available but a sample is open, tell clients to retry after this time.
 * `delay_overestimate` --- When a sample is closed, clients are told to wait until after the sample opening time.  A small amount is added to this to prevent clients from hitting the final seconds before the sample is open.  This should be less than `empty_client_backoff` for it to make any difference.  I recommend below 10 seconds.

For example:

    :client_management:
      :time_per_link: 5
      :dynamic_time_overestimate: 1.3
      :empty_client_backoff: 60
      :delay_overestimate: 10


Server
------
These settings govern the network properties of the server, as used for data transfer to and from clients.

 * `interface` --- The hostname or IP address of an interface on which to listen
 * `port` --- The port on which to listen for this interface
 * `serialiser` --- The serialisation system used for communications with the client.  `:marshal`, `:yaml` and `:json` are supported.  `:marshal` is by far the fastest of these and is strongly recommended.  This must match the client's configuration.

For example:

    :server:
      :interface:
      :port: 27401
      :serialiser:  :marshal

Logging
-------
The logging system is the same for client, server, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)
