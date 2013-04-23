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
  * simplerpc

### Client

  * cURL Ruby bindings (gem install -r curb)
  * The 'gethostname' syscall

### Server

  * SQLite3 and Ruby bindings (gem install -r sqlite3)


Configuring
-----------
Please see the user documentation at docs/User for more information, as well as the sample documentation in configs/
