Client Configuration
====================
The client is responsible for applying to the server and accessing the web in order to download small batches of links, which it then uploads back to the server for storage.  As such its config file is concerned with network access both to the server and to the web.



Server
------
This section defines which server to connect to.

 * `address` --- The IP address or hostname at which to contact the server
 * `port` --- The port to use when contacting the server
 * `service_name` --- The name of the service exposed by the Marilyn RPC system.  Should correspond to that set in the server configuration.



Network
-------
This section governs the manner in which clients attempt to contact the server, notably aggressiveness of retrying and polling for jobs.  Clients implement a linear backoff system to ensure they do not over-compete for server resources when failing to perform transactions.

 * `connect_timeout` --- How long we should give the socket to respond when connecting to the server
 * `minimum_reconnect_time` --- The minimum time we should wait before reconnecting
 * `maximum_reconnect_time` --- The maximum time we should wait before connecting, approached graduaklly from the minimum
 * `connect_failure_penalty` --- The delay to add to the backoff time upon each failure, up to the `maximum_reconnect_time`

Client
------
The client's limitations as a system are described here, as well as a way of identifying multiple clients run from a single host.  

Clients check out batches of links, process them, then check in smaller batches (since the datapoints now have a large payload).  The ratio of these sizes should be tuned in accordance with the filesizes being uploaded on a regular basis, and the degree of data security one wishes to ensure.

 * `uuid_salt` --- A human-readable string to prepend the client UUID with.  Each client computes its ID from the hostname, and this is a way of making the IDs more human-readable (as well as running multiple clients on the same host).
 * `batch_capacity` --- How many links to check out and download in one batch.  The client will receive up to this number of links to download each time it contacts the server.
 * `check_in_size` --- How many datapoints to upload at once, in MB.  Datapoints contain data from the web, and are thus larger/easier to interrupt.
 * `cache_file` --- A filepath to keep web data in before it is pushed to the server.  Reduces client RAM requirements.  If you don't wish to use a file cache (i.e. slow filesystem, much RAM, set this to nil/blank).
 * `simultaneous_workers` --- The number of workers to run in the same pool.  Given preferrable network conditions, this many connections to websites will be open at once, and this number must be chosen whilst bearing in mind the limitations of your kernel and netiquette (especially if you have many links pointing at the same servers).  Within each client, links are downloaded from servers by a series of workers, which consume links from the pending pool.  This has the distinct advantage of being capable of very high degrees of parallelism (beyond that where the kernel will start dropping connections) with relatively little overhead.  Since they are the final point of contact with external web servers, they control things such as request parameters and the following of redirects.


  
Logging
-------
The logging system is the same for client, server, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)
