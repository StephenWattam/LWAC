Limits and Performance
======================
LWAC was designed to maximise throughput to the web, and as such easily stretches certain system resources.  Extracting the best performance requires knowledge of some of the limits of your underlying system, as well as the architecture of LWAC.  This guide should cover each of the points, and explain which need attention for which conditions.

Throughput
----------
The system is capable of downloading around 2.5 million pages per hour per client when resource speed is not an issue.  This slows to roughly 100,000 per hour per client when using real-world (year-old) URL lists.  This equals roughly 10-100 million words per hour in practice.

Most speed issues are caused by the slow response of servers, for which parallelism is the only practical solution.  It's worth noting that the tool can download at around 20Mbps/client in a sustained manner---this most certainly breaks netiquette and may be sufficient to overload some hosts if you have many links pointing to the same servers.

Network
-------
LWAC transfers large batches of data between its client and server tools, as well as to the web.  To ensure reliability, these transfers occur at different times, however, they are both subject to various limitations.


### Client-Server Communication

#### Batch Size
Increasing the size of a batch will have a number of effects.

 1. More data will be queued up in RAM on both the client and the server.  The server will, at most, `hold cache_size * number_of_clients` links in memory.  The client will store at most its batch size.  Generally this is not an issue, as any modern system can store millions of Link objects in memory.
 2. Transfer between client and server will lock out other clients until complete, so smaller batches allow for better client load-balancing.

In my experience, sizes of 1000-10,000 are suitable for smaller corpora, and/or low client specifications.  Even if your web pages are small, there is overhead in managing the cache prior to sending it to the server, so batch sizes in excess of around 20,000 start slowing down (changing the client cache policy can help this).


#### Client Competition
Clients compete with one another for server time, and follow this algorithm to do so:

 1. Start worker servers
 2. Maintain work:
   * If the link pool is empty, connect to the server to get more links
   * When N MB of data have been downloaded, contact the server to upload
 3. When the server has no links to give, wait and back off

The server can support an unlimited number of clients, but beyond a point they will start locking one another out and efficiency drops off.  This point is highly dependent on:
  
  * Network speeds
  * The batch size, concurrency and other [client settings](client_config.html)

Since the server guarantees data consistency in the case of clients disconnecting, I recommend connecting progressively more clients until the point of maximum efficiency is reached for your setup.


### Web connection
LWAC places significant stress on the connection to the web, and can trigger things such as DDOS protection and traffic shaping schemes.  Steps should be adjusted to avoid this, if possible, such as by placing clients on different parts of the network.


#### Proxies/single points of failure
Proxies can be configured in the curl settings (`client_policy` section of the [server config](server_config.html)), however, they are subject to a number of effects that are generally undesirable for sampling (such as caching and header rewriting), and present a single point of failure which handles all of the stress.

Unfortunately there is currently no method to set a different proxy on each client (this is due in a later version).

#### DNS
DNS lookup is considered an integral part of fetching web data, and is thus repeated every time a client downloads a link.  If this places undue stress on one's DNS provider, a local cache can vastly reduce outgoing traffic with relatively little risk of damaging the quality of resultant data.



File System
-----------
The filesystem is used extensively in LWAC both as backing store and as a cache.  Many filesystems, especially those on virtual servers, impose significant performance overheads when dealing with small files or certain types of access.  It is important than LWAC is adjusted if this is the case.

### Server
The server's use of the filesystem is twofold:

 * Corpus backing store
 * Metadata database (read only beyond initial import)

#### Max Files per Dir
Many filesystems impose a fairly low limit on the number of files that will fit in one directory.  Since one file per datapoint is used in a corpus, they may be spanned over many directories.  See the [server config](server_config.html) for the relevant configuration properties.

#### Corpus Dir Size
Over time the corpus directory will grow very large.  It's possible to copy all but the current sample out of this directory whilst the server is running, though a better policy might simply be to place the corpus on a large disk or RAID volume.


#### SQLite3 performance (pragmas)
SQLite3 is largely retained in RAM during use, however, its disk access can be controlled through the use of `PRAGMA` statements.  If disk or memory usage is a particular problem, these can be adjusted to specify new limits, as mentioned in the [server config](server_config.html).

### Client
The client uses disks infrequently or never, depending on the configuration used, using a single cache file:
 
 * Datapoint cache

#### Open Socket Limit
Most operating systems impose limits on the number of sockets that may be open at any one time.  Since the client is heavily multithreaded, it is capable of exceeding these limits with relative ease.

On unix systems, the limit can be read using the command `ulimit -a`, where it is typically listed as the number of file descriptors allowed (minus one for the cache file and one for each log).

#### Cache Filesize
The file caching system is based on a single file, which will grow to the size of the sum of all data downloaded in one batch.  In testing with HTML data, this generally means about 10MB for every thousand links.

The client's cache system uses repeated `fseek` calls to look up data.  If your filesystem is very bad at seeking, it may be wiser to use a memory cache instead.

Memory Usage
------------
LWAC was designed for large samples, and as such its memory usage is minimal, static (O(1) complexity w.r.t. total corpus size), and configurable.

### Server
The server requires enough memory to store:

 * Lists of failed links (which accumulate if clients drop out during a batch, but are soon re-used).  A thousand links uses under 100KB of storage in RAM.
 * Datapoints currently being checked in (see `check_in_rate` in the [client config](client_config.html) to set this in MB)
 * SQLite3 or MySQL cache (see above)

This means that the server should always be using less than a few hundred megabytes of RAM, and much of that is ruby/libsqlite3/libcurl.

### Client
The client typically uses more RAM:

 * Lists of links to download (max will be the batch size).
 * Data downloaded from the web if using a memory cache (set `cache_file` in the [client config](client_config.html) to use a disk cache, or set `max_body_size` in the [server config](server_config.html))
 * Data being accumulated for upload to the server (see `check_in_rate` in the [client config](client_config.html))
 * Working data for a large number of download threads (at most equal to the number of threads multiplied by the `max_body_size`)

A client with a large batch size (tens of thousands of links), downloading large files (such as PDFs), and using a memory cache, may use gigabytes of RAM.  The same client with a disk cache will use only a couple of hundred MB, mostly comprising ruby, libcurl, and marilyn/eventmachine.
