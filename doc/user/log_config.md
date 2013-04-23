Logger Configuration
====================
LWAC uses a more flexible extension of ruby's standard log libraries and outputs in a fairly standard format.  Each tool's config file contains its own logging section, though they share a common format.

Configuration 
-------------

 * `progname`                   --- The name of the program to output in the log file (printed on each line)
 * `logs{}`                     --- A hash containing all other logs that a user wishes to use.  The `LOG_NAME` below is arbitrary and used to refer to the log in summary output.
    * `logs/LOG_NAME/dev`       --- The device to use for this log.  This can either be a filename, or STDOUT/STDERR.
     * `logs/LOG_NAME/level`    --- The level to log at.  This is one of the symbols `:debug`, `:warn`, `:info`, `:error`, or `:fatal`


Sample Config
-------------
The configuration below outputs three logs, one to stdout for basic information whilst the program runs, one with errors only to a file, and another with basic progress to another file.

    :logging:
      :progname: Server
      :logs:
        :default:
          :dev: STDOUT
          :level: :info
        :errors:
          :dev: 'logs/server.err'
          :level: :warn                                              
        :file_log:
          :dev: 'logs/server.log'
          :level: :info

