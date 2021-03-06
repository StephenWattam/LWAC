Client Configuration
====================
The client is responsible for applying to the server and accessing the web in order to download small batches of links, which it then uploads back to the server for storage.  As such its config file is concerned with network access both to the server and to the web.



Server
------
This section defines which server to connect to.  This section contains configuration for [SimpleRPC](http://stephenwattam.com/projects/simplerpc/), and supports all features it does.  Only the salient ones are documented here.

 * `hostname`   --- The IP address or hostname at which to contact the server
 * `port`       --- The port to use when contacting the server
 * `password`   --- Optional.  The password to use for auth (must match server config)
 * `secret`     --- Optional.  The encryption key to use when sending the password (must match server config)

For example:

    :server:
      :hostname: "127.0.0.1"
      :port: 27401
      :password: lwacpass
      :secret: egrniognhre89n34ifnui4n8gf490

Network
-------
This section governs the manner in which clients attempt to contact the server, notably aggressiveness of retrying and polling for jobs.  Clients implement a linear backoff system to ensure they do not over-compete for server resources when failing to perform transactions.

 * `connect_timeout`         --- How long we should give the socket to respond when connecting to the server
 * `minimum_reconnect_time`  --- The minimum time we should wait before reconnecting
 * `maximum_reconnect_time`  --- The maximum time we should wait before connecting, approached gradually from the minimum
 * `connect_failure_penalty` --- The delay to add to the backoff time upon each failure, up to the `maximum_reconnect_time`

For example:

    :network:
      :connect_timeout: 20
      :minimum_reconnect_time: 1
      :maximum_reconnect_time: 240
      :connect_failure_penalty: 3

Client
------
The client's limitations as a system are described here, as well as a way of identifying multiple clients run from a single host.  

Clients check out batches of links, process them, then check in smaller batches (since the datapoints now have a large payload).  The ratio of these sizes should be tuned in accordance with the filesizes being uploaded on a regular basis, and the degree of data security one wishes to ensure.

 * `announce_progress` --- Boolean.  Set to true to print worker status to the screen every half second during operation.
 * `uuid_salt` --- A human-readable string to prepend the client UUID with.  Each client computes its ID from the hostname, and this is a way of making the IDs more human-readable (as well as running multiple clients on the same host).
 * `batch_capacity` --- How many links to check out and download in one batch.  The client will receive up to this number of links to download each time it contacts the server.
 * `check_in_size` --- How many datapoints to upload at once, in MB.  Set to the `cache_limit` to make uploads go fastest, or below it to split them.
 * `cache_limit` --- The approximate size of the cache used by the client (in bytes).  After downloading this amount of data, the cache will be swapped out and uploaded in chunks to the server.
 * `cache_dir` --- A directory to create file caches in.  Reduces client RAM requirements, as the cache will store web data before upload.  If you wish to use memory instead, leave this blank.  At most two caches will be active at any one time, meaning memory limits will be:
   * If using memory caching, `2 * cache_limit + simultaneous_workers * max_body_size`
   * If using disk caching, `check_in_size + simultaneous_workers * max_body_size`
 * `simultaneous_workers` --- The number of workers to run in the same pool.  Given preferrable network conditions, this many connections to websites will be open at once, and this number must be chosen whilst bearing in mind the limitations of your kernel and netiquette (especially if you have many links pointing at the same servers).  Within each client, links are downloaded from servers by a series of workers, which consume links from the pending pool.  This has the distinct advantage of being capable of very high degrees of parallelism (beyond that where the kernel will start dropping connections) with relatively little overhead.

For example:

    :client:
      :announce_progress: true
      :monitor_rate: 0.5
      :uuid_salt: "LOCAL"
      :batch_capacity: 1000
      :cache_limit: 209715200
      :check_in_size: 209715200
      :simultaneous_workers: 200
      :cache_dir:                   # nil to use RAM cache
  
Logging
-------
The logging system is the same for all tools and shares a configuration format.  For details, see [configuring logging](log_config.html)
