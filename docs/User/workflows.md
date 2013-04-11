LWAC Workflows
==============
LWAC functions as a data acquisition system only, however, it's still fairly flexible in how it is deployed.  This page outlines a simple setup for downloading a URL list, and covers what to edit/configure/run when.

URI Selection
-------------
Stage one is to settle on which URIs should be sampled.  These should then be placed in a file in one-line-per-URI format for use with the import script.

This URI list should then be imported into an empty metadata database using the [import tool](config_docs.html).  This will create a SQLite3 database with space for sample summaries and datapoint information.

Server Configuration
--------------------
On the server machine, a directory should be created that will hold the corpus.  This should be accessible to the server process (with write permissions), and should be on a filesystem that can handle many small files efficiently.  Place the metadata database in this corpus.

Next, configure the [server's configuration file](server_config.html) such that it is suited to the position of the corpus directory and the limits of the filesystem, network, and host machine.

Client Configuration
--------------------
Each client that is to do the download work must also be [configured](client_config.html) to point to the server, and should be tweaked to match the capacities of its host.

Data Collection
---------------
Clients will continually attempt to contact the server as long as they are running, so the order in which clients and servers are started is of no consequence.  

Summary statistics are output by the server regarding overall performance, including the number of links downloaded, progress on individual samples, etc.  Inspecting the logs of a running server should provide enough information on overall download progress.  It's also possible to export data from an 'active' corpus, though it is possible to configure the database in such a way that this is not possible (exclusive locking).

Operationalisation
------------------
This is possible one of two ways.  The former is to use the server's storage libraries to write custom export code in ruby.  The latter, and easiest, is to use the export tool provided.

If using the export tool, it must be [configured](export_config.html) to extract variables of interest from the corpus.  This configuration will vary for each server and study.

Once you've exported data, import it into some kind of analysis tool and do science with it :-)

