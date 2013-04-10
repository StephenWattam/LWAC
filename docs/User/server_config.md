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

### Database Details

 * `database/filename`          --- The path to the metadata database, relative to the corpus root.
 * `database/table`             --- The table name where links to be downloaded are stored
 * `database/fields`            --- Contains information on the links table's fields
 * `database/fields/id`         --- The field name containing the link ID
 * `database/fields/uri`        --- The field name contain the URI to request from a remote server.
 * `database/transaction_limit` --- How many queries to run per transaction.  Larger numbers speed up access at the expense of data security.
 * `database/pragma{}`          --- A key-value list of pragma statements to configure the SQLite3 database.  These configure the database, and take the form of a list of key-value strings.  A full list of SQLite3 pragma statements is available on [their website](http://www.sqlite.org/pragma.html)


Sampling Policy
---------------
The sampling policy used by the server is defined by two parameters, *duration* and *alignment*.  

 * `sample_time` --- A sample's *duration* is the minimum time a sample may take.  For example, if this is a daily sample, it should be set to 84600 (the number of seconds in a day) in order to sample once at midnight each day.
 * `sample_alignment` --- A sample's *alignment* defines whereabouts within each sample time the sample may start.  Using the above example, setting this to 7200 would cause samples to begin at 2am each day.

Note that if a sample takes more than `sample_time` to run, it will overlap and cancel the next sample.  This is to prevent misalignment with the other datapoints in the sample, and is preferrable in many analyses to a series of messily-timed run-on samples.  The code that selects the samples thus follows this algorithm:

 * Round down to the last valid sample time (`time = Time.at(((Time.now.to_i / @config[:sample_time]).floor * @config[:sample_time]) + @config[:sample_alignment])`)
 * While `time < Time.now`
   * increment the prospective time by the `sample_time`

If you wish to edit the sample computation algorithm, it resides in `lib/server/consistency_manager.rb`, under the method `compute_next_sample_time`.


Client Management
-----------------
The server's responsibilities for managing clients as they connect and process work mean that it must present meaningful time limits on these connections (lest clients crash or misbehave).  These settings govern the rate at which clients are presumed to work, before the server starts re-assigning their work to other clients.

 * `time_per_link` --- How long, in seconds, each client gets to download a link before its batch is cancelled and moved back into the main pool of unallocated links.  On most systems this should not be over a second or two---even if some links time out, it is unlikely that all reach their timeout.  
 * `empty_client_backoff` --- If no links are available but a sample is open, tell clients to retry after this time.
 * `delay_overestimate` --- When a sample is closed, clients are told to wait until after the sample opening time.  A small amount is added to this to prevent clients from hitting the final seconds before the sample is open.  This should be less than `empty_client_backoff` for it to make any difference.  I recommend below 10 seconds.


Server
------
These settings govern the network properties of the server, and the Marilyn RPC system it uses for data transfer.


 * `service_name` --- The name of the service as described by Marilyn.  This should be the same between the server and client configuration, but otherwise is of little importance and may be set to an arbitrary value.
 * `interfaces[]{}` --- A list of interfaces to listen on.  Each interface should be a hash containing an ip and a port:
    * `interfaces[]/interface` --- The hostname or IP address of an interface on which to listen
    * `interfaces[]/port` --- The port on which to listen for this interface


Logging
-------
The logging system is the same for client, server, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)
