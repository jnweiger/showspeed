showspeed
=========

Print I/O activity of process, files, or network.
Print estimated time of arrival.

It can attach to a running process, identified by process name or pid, if the name is ambiguous.
Once per second a line of statistics is printed. If possible an ETA countdown timer is also printed.

E.g. 
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
