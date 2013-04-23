Installation
============
LWAC is distributed as a gem, and this should handle management of include paths and dependencies:

 * [Ruby](http://www.ruby-lang.org/en/) v1.9.3 or above
 * [libcurl](http://curl.haxx.se/libcurl/) (client only)
 * [sqlite3](http://www.sqlite.org/) (server only)
 * Some supporting gems:
   * simplerpc
   * sqlite3 (server only)
   * curb (client only)

To install, simply run:

    $ gem install lwac

and gem should download and install the latest version.

Git
---
If you wish to run LWAC straight from the git repository, this is possible by adding a single item to ruby's `$LOAD_PATH`.  To do this, run:

    $ ruby -I ./lib lwac ....

This is particularly useful when modifying the code.  If you make some modifications, please don't hesitate to get in touch and I'll do my best to integrate them upstream.
