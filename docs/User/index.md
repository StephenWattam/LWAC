LWAC User Guide
===============
Welcome to the LWAC user guide.  The purpose of this document is to explain some of the design concepts used and provide recipes for completing common tasks.

Concepts
--------
The [concepts](concepts.html) used in the model are explained here.

Tools
-----
LWAC consists of a number of [tools](tools.html), and these are explained individually here.

Workflows
---------
LWAC's [workflow](workflows.html) was designed around longitudinal sampling.  Some common methods are explained here.



Log Output
----------
Below is the log output from a simple test run using three links and the example configs (logged at the INFO level).  It shows a single checkout/in loop for a local client.


     - Server starts and summarises logs - 
    I, [2013-03-14T12:57:36.757142 #27841]  INFO -- Server: Summary of logs:
    I, [2013-03-14T12:57:36.757322 #27841]  INFO -- Server:  (1/2) default (level: INFO, device: fd=1 TTY)
    I, [2013-03-14T12:57:36.757410 #27841]  INFO -- Server:  (2/2) file_log (level: INFO, device: fd=6 filename=logs/server.log)
     - Summary of the state of the corpus - 
    I, [2013-03-14T12:57:36.784777 #27841]  INFO -- Server: No sampling has occurred yet, this is a new deployment.
     - Opens a sample and computes the next sample time - 
    I, [2013-03-14T12:57:36.785029 #27841]  INFO -- Server: *** Opened new sample to commence on 2013-03-14 12:58:00 +0000
    I, [2013-03-14T12:57:36.785088 #27841]  INFO -- Server: Estimated completion time: 2013-03-14 12:58:01 +0000
    I, [2013-03-14T12:57:36.785577 #27841]  INFO -- Server: Current sample: <Sample 0, 3/3 [closed, incomplete]>.
    I, [2013-03-14T12:57:36.785641 #27841]  INFO -- Server: Sample closed: wait 24s before sampling until 1363265880.
     - Server starts network server -
    I, [2013-03-14T12:57:36.785690 #27841]  INFO -- Server: Registering exit handler for download server.
    I, [2013-03-14T12:57:36.785734 #27841]  INFO -- Server: Listening for connections connections on:
    I, [2013-03-14T12:57:36.785874 #27841]  INFO -- Server:   localhost:27400
    I, [2013-03-14T12:57:36.786227 #27841]  INFO -- Server:   148.88.227.135:27400
     - client connects and requests links -
    I, [2013-03-14T13:00:01.066651 #27841]  INFO -- Server: Client LOCAL_25f4e5cdc4902e3d1fc5753dd992adec wishes to check out 1000 links.
     - The sample is opened and links are sent up to the client's capacity -
    I, [2013-03-14T13:00:01.067658 #27841]  INFO -- Server: Dispatched 3 link[s], timeout 3s (2013-03-14 13:00:04 +0000)
    I, [2013-03-14T13:00:01.067881 #27841]  INFO -- Server: 3 + 0 = 3/3 links checked out + available = remaining/total (100.0%).
     - The client disconnects and downloads links - 
    I, [2013-03-14T13:00:01.249565 #27841]  INFO -- Server: Client LOCAL_25f4e5cdc4902e3d1fc5753dd992adec wishes to check in 3 datapoint[s].
     - All links are now checked in, so close and summarise the sample - 
    I, [2013-03-14T13:00:01.271092 #27841]  INFO -- Server: Current sample complete.
    I, [2013-03-14T13:00:01.271209 #27841]  INFO -- Server: Sample duration: 0s
    I, [2013-03-14T13:00:01.271261 #27841]  INFO -- Server: *** Closing sample <Sample 0, 0/3 [open, complete]>
     - Open a new sample and compute the next sample time - 
    I, [2013-03-14T13:00:01.271871 #27841]  INFO -- Server: *** Opened new sample to commence on 2013-03-14 13:01:00 +0000
    I, [2013-03-14T13:00:01.271937 #27841]  INFO -- Server: Estimated completion time: 2013-03-14 13:01:00 +0000
    I, [2013-03-14T13:00:01.272378 #27841]  INFO -- Server: Done.
     - Client connects and asks for links, but the sample is not open yet, so is told to wait until 2013-03-14 13:01:00 +0000 - 
    I, [2013-03-14T13:00:01.272454 #27841]  INFO -- Server: 0 + 3 = 3/3 links checked out + available = remaining/total (100.0%).
    I, [2013-03-14T13:00:01.273594 #27841]  INFO -- Server: Client LOCAL_25f4e5cdc4902e3d1fc5753dd992adec wishes to check out 1000 links.
    I, [2013-03-14T13:00:01.273725 #27841]  INFO -- Server: Telling client to wait 69 seconds.
     - SIGINT sent -
    F, [2013-03-14T13:00:13.636703 #27841] FATAL -- Server: Closing DownloadServer cleanly...
    F, [2013-03-14T13:00:13.636901 #27841] FATAL -- Server: Closing storage manager, writing state to corpus/state.yml
    F, [2013-03-14T13:00:13.638300 #27841] FATAL -- Server: Done.


     - client starts and summarises logs - 
    I, [2013-03-14T13:00:01.065542 #27889]  INFO -- Client: Summary of logs:
    I, [2013-03-14T13:00:01.065645 #27889]  INFO -- Client:  (1/2) default (level: INFO, device: fd=1 TTY)
    I, [2013-03-14T13:00:01.065699 #27889]  INFO -- Client:  (2/2) file_log (level: INFO, device: fd=6 filename=logs/client.log)
     - Prints its ID - 
    I, [2013-03-14T13:00:01.065910 #27889]  INFO -- Client: Client started with UUID: LOCAL_25f4e5cdc4902e3d1fc5753dd992adec
     - Polls the server for links - 
    I, [2013-03-14T13:00:01.068465 #27889]  INFO -- Client: Received 3/1000 links from server.
     - Starts the download process - 
    I, [2013-03-14T13:00:01.068676 #27889]  INFO -- Client: Creating worker pool and starting work...
    I, [2013-03-14T13:00:01.072776 #27889]  INFO -- Client: 50 worker[s] created.
    I, [2013-03-14T13:00:01.097650 #27889]  INFO -- Client: 50 download thread[s] started.
     - Downloads links, reporting any errors here - 
    I, [2013-03-14T13:00:01.234497 #27889]  INFO -- Client: Workers all terminated naturally.
     - Sends links to the server, after a summary - 
    I, [2013-03-14T13:00:01.234705 #27889]  INFO -- Client: Downloaded.  Checking in complete links...
    I, [2013-03-14T13:00:01.234818 #27889]  INFO -- Client: Queue complete.
    I, [2013-03-14T13:00:01.234920 #27889]  INFO -- Client:   Response:
    I, [2013-03-14T13:00:01.235020 #27889]  INFO -- Client:     200    : 3
    I, [2013-03-14T13:00:01.235121 #27889]  INFO -- Client:     404    : 0
    I, [2013-03-14T13:00:01.235226 #27889]  INFO -- Client:     other  : 0
    I, [2013-03-14T13:00:01.235300 #27889]  INFO -- Client:   Errors   : 0
    I, [2013-03-14T13:00:01.235375 #27889]  INFO -- Client:   Complete : 3
    I, [2013-03-14T13:00:01.235952 #27889]  INFO -- Client: Sending 3 datapoints (~0.2MB) to server...
     - Then the server tells it to back off until the sample is open again - 
    I, [2013-03-14T13:00:01.274146 #27889]  INFO -- Client: Sleeping for 69s until 2013-03-14 13:01:10 +0000 at the server's request.
     - SIGINT sent -
    F, [2013-03-14T13:00:10.878767 #27889] FATAL -- Client: Caught signal!
    F, [2013-03-14T13:00:10.878936 #27889] FATAL -- Client: Contacting the server to cancel links...
    F, [2013-03-14T13:00:10.879023 #27889] FATAL -- Client: Done.

