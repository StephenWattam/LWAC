Client Configuration
====================
The client is responsible for applying to the server and accessing the web in order to download small batches of links, which it then uploads back to the server for storage.  As such its config file is concerned with network access both to the server and to the web.



Server
------
This section defines which server to connect to.

 * `address` --- 
 * `port` --- 
 * `service_name` --- 



Network
-------
This section governs the manner in which clients attempt to contact the server, notably aggressiveness of retrying and polling for jobs.  Clients implement an exponential backoff system to ensure they do not over-compete for server resources when failing to perform transactions.

 * `connect_timeout` --- 
 * `minimum_reconnect_time` --- 
 * `maximum_reconnect_time` --- 
 * `connect_failure_penalty` --- 

Client
------

 * `` --- 
 * `` --- 
 * `` --- 
 * `` --- 

Worker Pool
-----------

 * `` --- 
 * `` --- 
 * `` --- 
 * `` --- 

  
Logging
-------
The logging system is the same for client, server, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)
