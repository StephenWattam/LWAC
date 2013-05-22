Import Tool Configuration
=========================
The import tool is responsible for creating (or adding links into) the server's corpus.  Its configuration file is thus very simple---all options for string processing and storage remain the preserve of the [server's config file](server_config.html).


Config
------
The import tool uses the server configuration to access a corpus, and loads it as if it were a server.

 * `server_config`  --- The path to the server configuration file.  The importer will use this for storage properties and string sanitisation settings.

Other than that its configuration options apply to output and file handling:

 * `schemata_path`  --- The path where `.sql` files may be found for creating a database.  Leave this blank to use defaults that come bundled with LWAC.
 * `create_db`      --- Boolean.  Set to `true` to make the import script attempt to create the database if it doesn't exist.
 * `notify`         --- How many lines should be import before the UI updates and tells the user.

For example:

    :server_config: example_config/server.yml
    :schemata_path:                             # use defaults
    :notify: 12345
    :create_db: true


Logging
-------
The logging system is the same for client, server, import, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)

