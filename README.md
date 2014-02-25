showspeed
=========

Print I/O activity of process, files, or network.
Print estimated time of arrival.

It can attach to a running process, identified by process name or pid, if the name is ambiguous.
A line of statistics is printed every two seconds. If possible an ETA countdown timer is also printed.

The effect of showspeed is similar to inserting |pv| into a command pipeline. Showspeed has these advantage over pv:

 * No need to construct an artificial pipeline if monitoring a simple command.
 * You can call it *after* starting your command or pipeline.
 * You can start stop monitoring as you like.
 * It can forsee the end and print an estimated time of arrival. Sometimes. 

Example: 
<pre>
$ dd if=bigfile of=/tmp/otherbigfile &
$ showspeed dd
dd looks like a process name. pid=4417 matches av0=dd.
p/4417/fd/0r /home/jw/bigfile 113MB/s (12%, 2.3GB)  9m:35
p/4417/fd/1w /tmp/otherbigfile 182MB/s (2.6GB)
p/4417/fd/0r /home/jw/bigfile 285MB/s (15%, 3.0GB)  8m:08
p/4417/fd/0r /home/jw/bigfile 115MB/s (16%, 3.2GB)  8m:01
p/4417/fd/0r /home/jw/bigfile 107MB/s (17%, 3.4GB)  7m:39
p/4417/fd/1w /tmp/otherbigfile 104MB/s (3.5GB)
p/4417/fd/0r /home/jw/bigfile 139MB/s (19%, 3.7GB)  7m:37
p/4417/fd/0r /home/jw/bigfile 116MB/s (20%, 3.9GB)  7m:18
p/4417/fd/1w /tmp/otherbigfile  67MB/s (4.0GB)
p/4417/fd/1w /tmp/otherbigfile 100MB/s (4.1GB)
</pre>


Users may wonder, why the good old command line tools don't come already with their own progress indicators. Modern versions of rsync support --progress. wget automatically does it. But cp, dd, and many other programs don't. 
A good progress indicator adds quite some complexitiy, that technically does not make the program faster or better. For the developer, it appears to violate the unix philosophy of doing only one thing, but do it well. 

For the end user, the progress indicator may be part of 'doing it well'. Showspeed was written for end users -- those that still know what a command line is.
