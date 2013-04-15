Installation
============
LWAC requires no installation, simply run it in-place.  However, there are some dependencies:

 * [Ruby](http://www.ruby-lang.org/en/) v1.9.3 or above
 * [libcurl](http://curl.haxx.se/libcurl/) (client only)
 * [sqlite3](http://www.sqlite.org/) (server only)
 * Some supporting gems:
   * marilyn-rpc
   * eventmachine
   * sqlite3 (server only)
   * curb (client only)
   * god (optional, for [process monitoring](monitoring.html))

Installation script
-------------------
The installation script bundled with LWAC will install the gems for you, for a deployment on a server or client.  To use it, simply run:

    ./install_deps.rb BUNDLE [VERSION]

The `BUNDLE` argument specifies whether you want to install dependencies for the client, server, or both.  Clients do not require sqlite3, and servers do not require libcurl.  Note that machines using export scripts must have the server components installed.

The optional `VERSION` parameter tells the script how strict to be when version-checking:

  * `strict`---This is the default, and will install only the versions I have personally used to test and develop LWAC.
  * `optimistic`---This will install any version newer than the tested ones.  This will generally let you get minor bug fixes, but over time libraries may change quite a lot
  * `lazy`---Simply install any version available

LWAC is developed using the latest version of all of the dependencies, on Arch linux (which is usually very up-to-date), and subsequently the versions against which it is tested will progress gradually.
