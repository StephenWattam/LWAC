Monitoring/Maintenance
======================
LWAC should require little maintenance beyond initial deployment.  It is heavily network-dependent, and as such its libraries should be kept up-to-date for security purposes (simply re-run the [deploy script](install.html) with optimistic version handling).


Disk Space
----------
As the corpus grows it may be necessary to move data off the server's working disk.  Any samples that are not currently open may be moved whislt the server is running---this basically means all but the last entry in the corpus.

Process Monitoring
------------------
LWAC is as prone to failure as any other long-running process, and should ideally be monitored during its sampling runs, especially if they last many months.  Many tools are available for this (such as [monit](http://mmonit.com/monit/), [Ubic](https://github.com/berekuk/Ubic), [God](http://godrb.com/) or [bluepill](https://github.com/arya/bluepill)), and any should suffice in monitoring both client and server processes.  

