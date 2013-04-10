Tools
=====
LWAC's workflow is based around a simple import-augment-export system, and as such there are three major tools in the distribution:

Import
------
The import tool is responsible for creating a metadata database, and importing links into it.  It does not create the whole corpus directory structure (this is handled by the download server), but will construct requisite SQL tables for handling sampling.

### Importing links

The import script may be run simply by running

    ./import DBFILE LINKFILE [create]

where:

 * `DBFILE` is the filepath of an SQLite3 database, or the path you wish to create if one does not exist yet;
 * `LINKFILE` is a one-link-per-line list of hyperlinks to use for this sample (assumed UTF-8), and;
 * `create` is the word 'create' if you wish to create a database from scratch.  If this argument is given, the import tool will look in `./resources/schemata/` and execute ALL the SQL files it finds in order to construct the database (further documentation is given in the schemata directory).

### Progress and Performance
Whilst importing links, the tool will output its progress per 1023 links (see 'Advanced Configuration' below).  Unlike other tools in the distribution, the import script does not use the same data access or log libraries and its output is somewhat minimal.

### Advanced Configuration
The import tool can be configured by editing the constants within the file itself.  These run to:

 * `SQLITE_PRAGMA`---A list of SQLite3 pragma statements to be run.  The defaults have been chosen to maximise performance and offer a speed up of many orders of magnitude over the default configuration, though it is possible to further tune them with a little effort.
 * `FIX_ENCODING`---Set this to false to make the import script ignore any encoding glitches in the input files.  Generally, it's wise to keep this feature set to true to avoid any nasty surprises later (though all tools in LWAC can handle broken UTF-8 strings with various levels of capacity)
 * `NOTIFY_PROGRESS`---Print the progress every N links.  By default this is set to 1023, so that all significant figures update, which for some reason I always think looks neater :-)
 * `SCHEMA_PATH`---A string representing where to find the list of schemata to construct a new database.  Default is "./resources/schemata".
 * `SCHEMATA`---A list of schema files to apply when creating a new database.  The presumption is that one table is created per schema file, and this list is built automatically if `SCHEMA_PATH` above is set correctly by listing all files that end in `.sql`.  Note that SQLite3 does not support running multiple table creations in a single transaction.


Download
--------
The download phase is controlled by a single system, split into server and client.  The roles of the server are to:

 * Manage access to metadata and backing store (main corpus) in an atomic fashion
 * Enforce sampling policy
 * Manage client connections and download attempts

and it is thus configured with knowledge of the limitations of the backing store, properties of the metadata database, and network access to the client.

The client is tasked with:

 * Connecting to a relevant server and asking for work
 * Connecting to external servers to download data
 * Uploading data to a storage server

and thus is configured with network access properties for both the server and external HTTP servers, and rate/batch limits that should be tuned for the machine on which it is run.

Each server supports an unlimited number of clients, however, their access to the corpus is regulated through a competition model---whilst one is connected, the others are told to wait.  




Export
------
