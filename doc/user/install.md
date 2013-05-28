Installation
============
LWAC is distributed as a gem, and this should handle management of include paths and dependencies:

 * [Ruby](http://www.ruby-lang.org/en/) v1.9.3 or above
 * [libcurl](http://curl.haxx.se/libcurl/) (client only)
 * [sqlite3](http://www.sqlite.org/) or [mysql](http://www.mysql.com/) or [mariaDB](https://mariadb.org/) (server only)
 * Some supporting gems:
   * simplerpc
   * sqlite3 or mysql2 (server only)
   * curb (client only)

To install, simply run:

    $ gem install lwac

to install the latest version, and then:

 * If you are only ever going to run the client, `gem install curb`
 * If you are only ever going to run the server, `gem install sqlite3` _or_ `gem install mysql2`
 * If you're going to run both clients and servers, install both of the above.

Git
---
If you wish to run LWAC straight from the git repository, this is possible by adding a single item to ruby's `$LOAD_PATH`.  To do this, run:

    ruby -I ./lib ./bin/lwac [commands]

This is particularly useful when modifying the code.  If you make some modifications, please don't hesitate to get in touch and I'll do my best to integrate them upstream.
