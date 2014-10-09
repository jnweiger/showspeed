#! /usr/bin/perl -w
#
# 2011-2014 (C) jw@suse.de
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
# No warranty.
#
# 2011-12-02, v0.1  jw
# 2011-12-03, v0.2  jw, draft version of showspeed_pid() done.
# 2011-12-04, v0.3  jw, sub second intervall, sub run_status() added.
# 2011-12-15, v0.4  jw, eta added. --net added.
# 2011-12-18, v0.5  jw, rw letters added to fd... reporting.
# 2012-02-15, v0.6  jw, consulting /proc/pid/cmdline, as /stat and /comm are 15 bytes only.
#                       handle /proc/$pid/fd/$fd -> ... (deleted)
# 2012-02-16,       jw, showspeed_disk started, unfinished.
# 2012-09-24, v0.7  jw, improved /proc/pid/cmdline to /comm fallback
# 2012-10-17, v0.8  jw, printing position if perc_p is 100%
# 2012-11-04, v0.9  jw, added filename support. Only one proc currently.
# 2012-11-20, V0.10 jw, added vmsize printing when idle.
# 2012-12-09, V0.11 jw, argv1 matching added. Improved perc_p is 100% code.
# 2013-01-16, V0.12 jw, printing position if perc_p is 100% for both read and write.
# 2013-04-15, V0.13 jw, Renamed whatsup to showspeed. Script name and function calls.
#                       Added experimental --sync option.
#                       Stack trace less vulnerable.
# 2014-02-25, V0.14 jw, Added --cmd / -c for directly starting a command.
# 2014-08-15, V0.15 jw, Added find_termsize_fn(), used in showspeed_pid()
#                       to fit the line into the terminal. Using a randomizer for overlaps.
# 2014-10-09, V0.16 jw, vmsize from run_status() is now 0 (not '-') in case of error.
#
## FIXME: We should we have an option to include child processes too...
##        So that we can see plugin-container acting on behalf of MozillaFirefox
##
## CAUTION: reading /proc/NNNN/stack can cause an oops in 
##          Linux 3.1.0-1.2-default #1 SMP PREEMPT 
##
## TODO: option --disk
##  /proc/diskstats has it all:
##  8       6 sda6 320472 16503 66857632 1660013 77410 9334 66385608 30813329 0 1178302 32471447
##  Field 3 -- # of sectors read
##  Field 4 -- # of milliseconds spent reading
##  Field 7 -- # of sectors written
##  Field 8 -- # of milliseconds spent writing
##  Field 9 -- # of I/Os currently in progress
##  Field 10 -- # of milliseconds spent doing I/Os
##
## look into:
## /sys/class/block/sda/stat

use Data::Dumper;
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;
use Time::HiRes qw(time);	# harmless if missing.
use English;			# allow $EUID instead of $>

my $version = '0.16';
my $verbose  = 1;
my $top_nnn = 1;
my $int_sec = '1.5';
my $pipe;
my $out_style;
my $opt_read = 1;
my $opt_write = 1;
my $opt_pid = undef;
my $opt_sync = 0;

my $syncer_pid = undef;

my $help = 0;
my @cmd = ();

GetOptions(
	"verbose|v+"   	=> \$verbose,
	"version|V"    	=> sub { print "$version\n"; exit },
	"quiet"        	=> sub { $verbose = 0; },
	"help|h|?"      => sub { $help = -1 },

	"intervall|i=f"	=> \$int_sec, 
	"top|t=i"	=> \$top_nnn,
	"pid|p=i" 	=> \$opt_pid,
	"cmd|c"		=> sub { @cmd = @ARGV; @ARGV = (); },
	"pipe=s" 	=> \$pipe,
	"out|o=s"  	=> \$out_style,
	"read|r"	=> sub { $opt_write = 0; },
	"write|w"	=> sub { $opt_read = 0; },
	"network|net"   => sub { unshift @ARGV, "/dev/net"; },
	"disk|disc"     => sub { unshift @ARGV, "/dev/disk"; },
	"sync|s+"     	=> \$opt_sync,
) or $help++;

# use samles from the last minute for eta calculation.
my $histlen = 60  / $int_sec;	

die "--pipe not implemented. Always stderr.\n" if defined $pipe;
die "--out not implemented. Always plain.\n" if defined $out_style;
my $arg = shift;
$help++ if !$help and !$opt_pid and !length($arg||'') and !scalar(@cmd);
my $usage_text = $help = ".\n" if $help > 0;
$usage_text ||= q{, which can 
be one of the following types:

a file: (name must begin with / or ./ or ../)
     lists (the top NNN) processes, that read or write the file
     together with the bandwidth in MB/s they achieve. 
     When the fileposition is not at the end of the file, (e.g. 
     when reading or overwriting a file) a progress 
     percentage is also printed.

a process name: (plain word without special characters)
     names (the top NNN) processes of that name, if more than 
     one is found, 2 seconds of time are spent to determine the most
     active one, then continues as if its pid was specified.

a process pid: (digits only)
     prints the name, its (top NNN) open files and the bandwith
     it achives on those files. Sockets and pipes may or may not show up here.
     If the specified process fails to show any activity, during one statistics
     interval, the state of the process is shown (sleeping|waiting|...) together 
     with the system call name found in /proc/PID/stack

a network device: (name starts with /dev/)
     prints the name and statistics as found in /proc/self/net/dev
     with the special name '/dev/net', the (top NNN) most active 
     device(s) are/is reported.
     
};

pod2usage(-verbose => 1, -msg => qq{
showspeed V$version Usage: 

$0 [options] [.]/FILE
$0 [options] PROC_NAME
$0 [options] -c COMMANG [ARGS ...]
$0 [options] [-p] PID
$0 [options] /dev/[NET]
$0 [options] --net
$0 [options] --disk	(not impl.)
$0 --help

Showspeed shows bandwidth statistics for one object.

Valid options are:

 --interval SSS
      update the statistics every SSS seconds. 
      Default 2.

 --cmd COMMAND [ ARGS ... ]
      Start a command to be monitored instead of attaching to a command.
      Use this as the last option on the command line. 

 --top NNN 
      defines how many activities are reported simultaneously.
      Default: 1

 --out ansi|plain|json
      ansi: use simple console ansi sequences to format and
            update the output table. Default, when --pipe is not specified.
      plain: same as ansi, but records are formated as simple lines, 
            one below the other. Default, when --pipe is used.
      json: repeatedly output a json dictionary object, 
            with a trailing newline.

 --pipe "|COMMAND"
 --pipe "&FD"
      Send the output to another command or filedescriptor.
      With a comand name, the leading pipe character is optional.
      Default is '&2', which means STDERR.

 --pid PID
      Look into the process specified by PID. 
      Default: guess what to do, by matching the type of the parameter.

 --read
      restrict to read activity. Default: read and write

 --write
      restrict to write activity. Default: read and write
 
 --sync
      frequently call sync(1). This is strongly recommended, if 
      there is write activity and the ETA time should reflect real 
      physical data written to disk. Default: ETA guestimates delivery 
      into the kernel's block buffer cache.

 --help
      output more detailled help text.
           
Not all of the above is implemented.}.$usage_text
) if $help;

my $get_termsize = find_termsize_fn();

if (scalar @cmd)
  {
    $opt_pid = run_cmd(@cmd);
    $arg = "$opt_pid";
  }

if ($opt_pid || $arg =~ m{^\d+$})
  {
    showspeed_pid($opt_pid || $arg);
    exit 0;
  }

if ($opt_pid)
  {
    warn "$arg does not match {^\\d+\$}, -p ignored.\n";
    $arg = $opt_pid;
    sleep 1;
  }

if ($arg =~ m/^[+\.\w_-]+$/)
  {
    print STDERR "$arg looks like a process name." if $verbose; # CONT...

    my @eaccess = ();
    opendir DIR, "/proc" or die "opendir /proc failed: $!\n";
    my %p = map { $_ => {} } grep { /^\d+$/ } readdir DIR;
    closedir DIR;
    for my $p (keys %p)
      {
        if (open IN, "<", "/proc/$p/cmdline")
	  {
	    my $argv = join '', <IN>;
	    $p{$p}{argv} = [ split /\0/, $argv ];
	    $p{$p}{argv0} = $p{$p}{argv}[0] if defined $p{$p}{argv}[0];
	    $p{$p}{argv1} = $p{$p}{argv}[1] if defined $p{$p}{argv}[1];
	    close IN;
	  }
        if (open IN, "<", "/proc/$p/stat")
	  {
	    # don't care if open fails. the process may have exited.
	    $p{$p}{stat} = join '', <IN>;
	    if ($p{$p}{stat} =~ m{\((.*)\)\s+(\w)\s+(\d+)}s)
	      {
	        # this {cmd} is truncated to 15 bytes, argh!
		$p{$p}{cmd} = $1;
		$p{$p}{state} = $2;
		$p{$p}{ppid} = $3;
	      }
	    close IN;
	  }
	my $seen_something = 0;
	for my $key ([$p{$p}{cmd},   'cmd', 100],
	             [$p{$p}{argv0}, 'av0',  10],
		     [$p{$p}{argv1}, 'av1',   1])
	  {
	    my $name = $key->[0];
	    my $w = $key->[2];
	    next unless defined $name;
	    $p{$p}{sort}+= 1024*$w if $name eq $arg;
	    $p{$p}{sort}+=  256*$w if lc $name eq lc $arg;
	    $p{$p}{sort}+=  128*$w if $name =~ m{\b/\Q$arg\E$};
	    $p{$p}{sort}+=   64*$w if $name =~ m{\b/\Q$arg\E$}i;
	    $p{$p}{sort}+=   32*$w if $name =~ m{\b\Q$arg\E\b};
	    $p{$p}{sort}+=   16*$w if $name =~ m{\b\Q$arg\E\b}i;
	    $p{$p}{sort}+=    8*$w if $name =~ m{\b\Q$arg\E};
	    $p{$p}{sort}+=    4*$w if $name =~ m{\b\Q$arg\E}i;
	    $p{$p}{sort}+=    2*$w if $name =~ m{\Q$arg\E};
	    $p{$p}{sort}+=    1*$w if $name =~ m{\Q$arg\E}i;
	    $p{$p}{found_via} = [ $key->[1], $name, $p{$p}{sort} ] 
	      if (($p{$p}{sort}||0) > ($p{$p}{found_via}[2]||0));
	    $seen_something++;
          }
	push @eaccess, $p unless $seen_something;
      }
    my @sorted = sort { ($p{$b}{sort}||0) <=> ($p{$a}{sort}||0) } keys %p;
    my $pid = $sorted[0];
    unless (defined $pid and $p{$pid}{sort})
      {
        warn sprintf "%d processes EACCESS, try again as root?\n", scalar(@eaccess) if @eaccess;
        die "no process matches '$arg'\n";
      }
    @sorted = grep { ($p{$_}{sort}||0) == ($p{$pid}{sort}||0) } @sorted;
    if (scalar @sorted > 1)
      {
        print STDERR "\n" if $verbose;	# ... CONT.
        warn "multiple processes matching equally good:\n";
	for my $p (@sorted)
	  {
	    my $longname = "($p{$p}{cmd})";
	    $longname .= " $p{$p}{argv0}" if defined $p{$p}{argv0} and $p{$p}{argv0} ne $p{$p}{cmd};
	    $longname .= " " . join(" ",@{$p{$p}{argv}}[1 .. $#{$p{$p}{argv}}]) 
	      if defined $p{$p}{argv1};
	    warn "$p $longname\n";
	  }
	exit 1;
      }

    if ($verbose)
      {
        print STDERR " pid=$pid"; 	# ... CONT.
	if (my $f = $p{$pid}{found_via})
	  {
    	    print STDERR " matches $f->[0]=$f->[1]";
    	    print STDERR " score=$f->[2]" if $verbose > 1;
	  }
	print STDERR ".\n";
      }
    showspeed_pid($pid, $p{$pid}{argv0}||$p{$pid}{cmd});
    exit 0;
  }

if ($arg =~ m{/dev/net})
  {
    print STDERR "$arg looks like /dev/net .\n" if $verbose > 1;
    my $old;
    my ($counter, $tot_in, $tot_out) = (0,0,0);
    for (;;)
      {
        my ($term_w, $term_h) = $get_termsize->();

        my $new = showspeed_net();
	for my $dev (keys %$new)
	  {
	    if ($old && $old->{$dev})
	      {
	        $new->{$dev}{in_d} = $new->{$dev}{in} - $old->{$dev}{in};
	        $new->{$dev}{out_d} = $new->{$dev}{out} - $old->{$dev}{out};
	      }
	    $new->{$dev}{io} = ($new->{$dev}{in_d}||0) + ($new->{$dev}{out_d}||0);
	  }
	my @sorted = sort { 
	    $new->{$b}{io} <=> $new->{$a}{io} 
	    		   ||
		        $a cmp $b
			      } keys %$new;
	for my $i (0..$top_nnn-1)
	  {
	    my $n = $sorted[$i];
	    last unless $new->{$n}{io};
	    printf STDERR "%8s %8s in, %8s out\n", $n, 
	    	"".fmt_speed($new->{$n}{in_d}, $int_sec),
	    	"".fmt_speed($new->{$n}{out_d}, $int_sec);
	    $tot_out += $new->{$n}{out_d};
	    $tot_in  += $new->{$n}{in_d};
	  }
	if ($counter++ > 22)
	  {
	    printf STDERR "Total seen: %8s in, %8s out\n", 
	      "".fmt_speed($tot_in), "".fmt_speed($tot_out);
	    $counter = 0;
	  }
	wait_interval();

	$old = $new;
	
      }
  }

if ($arg =~ m{/dev/disk})
  {
    print STDERR "$arg looks like /dev/disk .\n" if $verbose > 1;
    my $old = {};
    for (;;)
      {
        my ($term_w, $term_h) = $get_termsize->();
        my $new = showspeed_disk();
	for my $dev (keys %$new)
	  {
	  }

	wait_interval();
	$old = $new;
        die "--disk not implemented. sorry\n";
      }
  }

if ($arg =~ m{/})
  {
    print STDERR "$arg looks like a file name.\n" if $verbose > 1;
    $procs = lsof_pid($arg);

    my @pids = keys %$procs;
    if (scalar(@pids) == 0)
      {
        if ($EUID == 0 or !-e $arg)
	  {
            print STDERR "$arg is unused.\n";
	  }
	else
	  {
            print STDERR "$arg appears unused. Try again as root?\n";
	  }
	exit 0;
      }
    if (scalar(@pids) > 1)
      {
        print STDERR "$arg is used by multiple processes. Choose one pid:\n";
	for my $pid (sort { $a <=> $b } @pids)
	  {
	    my $p = $procs->{$pid};
	    printf STDERR "%d: fd=", $pid;
	    my $comma = '';
	    for my $fd (sort { $a <=> $b } keys %{$p->{fd}})
	      {
	        printf STDERR "%s%d%s", $comma, $fd, $p->{fd}{$fd}{a};
	        my $comma = ',';
	      }
	    printf STDERR " %s\n", proc_pid_cmdline($pid);
	  }
	exit 0;
      }
    showspeed_pid($pids[0]);
    exit 0;
  }

die "implemented: type procname, pid, filename, --net. Nothing else. Sorry.\n";

exit 0;
############################################################

sub syncer_task
{
  my ($parent_pid) = @_;
  ## do this asynchronuously as sync() may block for ages.
  for (;;)
    {
      last unless kill 0, $parent_pid;	 # take care of ourselves.
      my $tstamp = time;
      system('sync') if $opt_sync;
      my $now = time;
      printf "synctime: %g\n", $now - $tstamp if $verbose > 1;
      select(undef, undef, undef, $int_sec);
    }
  printf "syncer exiting\n" if $verbose > 1;
  exit();
}

sub run_cmd
{
  my @cmd = @_;
  my $cmd_pid = fork();
  if ($cmd_pid == 0)
    {
      # should we do nohup or do we want him to die when we hint CTRL-C?
      exec @cmd;
      die "could not exec $cmd[0]: $!\n";
    }
  printf "[$cmd_pid] +$cmd[0] ... started\n" if $verbose > 1;
  return $cmd_pid;
}

sub wait_interval
{
  if (defined $syncer_pid)
    {
      ## test if syncer is still there
      if (kill 0, $syncer_pid)
        {
	  print "syncer $syncer_pid is still there\n" if $verbose > 2;
	}
      else
        {
	  print "syncer $syncer_pid gone.\n" if $verbose > 1;
	  $syncer_pid = undef;
	}
    }
  
  if ($opt_sync and !defined $syncer_pid)
    {
      # we need a syncer and have none.
      my $pid = $$;
      $syncer_pid = fork();
      syncer_task($pid) if $syncer_pid == 0;
    }

  select(undef, undef, undef, $int_sec);
}


sub showspeed_disk
{
  my $new = {};
  open IN, "<", "/proc/diskstats" or die "cannot open /proc/diskstats: $!\n";
  while (defined (my $line = <IN>))
    {
      chomp $line;
      next unless $line =~ m{^\s*\w+:\s};
    }
  die "showspeed_disk: not impl.";
}

sub showspeed_net
{
  my $new = {};
  open IN, "<", "/proc/self/net/dev" or die "cannot open /proc/self/net/dev: $!\n";
  while (defined (my $line = <IN>))
    {
      chomp $line;
      next unless $line =~ m{^\s*\w+:\s};
      #  Inter-|   Receive                                                |  Transmit
      #   face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
      #
      #   eth0: 578234868 1524405    0    0    0     0          0    288504 124947018  165012    0    0    0     0       0          0
      my @l = split /\s+/, $line;
      shift @l if $l[0] eq '';
      $new->{$l[0]} = { in => $l[1], out => $l[9] };
    }
  close IN;
  return $new;
}

sub proc_pid_cmdline
{
  my ($pid) = @_;
  my $cmd;
  unless ($cmd)
    {
      if (open IN, "/proc/$pid/cmdline") 
        {
          # proc/pid/comm not in SLE11SP1
          $cmd = <IN> || ''; 	# kjournald has no cmdline
          chomp $cmd;
	  $cmd =~ s{\0.*$}{};
	  close IN;
	}
    }
  unless ($cmd)
    {
      if (open IN, "/proc/$pid/comm")
        {
          # /proc/pid/comm is also truncated to 15 bytes, grrr..
          $cmd = <IN>; 
          chomp $cmd;
          close IN;
	}
    }

  $cmd = "(pid=$pid)" unless $cmd;
  return $cmd;
}

sub showspeed_pid
{
  my ($pid, $cmd) = @_;
  $cmd = proc_pid_cmdline($pid) unless $cmd;

  print STDERR "showspeed_pid($pid, '$cmd')\n" if $verbose > 1;
  my $hist;
  my $old;
  while (1)
    {
      my ($term_w, $term_h) = $get_termsize->();

      my $new = fdinfo($pid);
      return unless defined $new;

      ## this is either core::time or Time::HiRes::time, if available
      $new->{ts} = time;
      my %f = ();
      if ($old)
        {
	  ## compare old and new. placing diffs in $new
	  for my $fd (sort keys %{$new})
	    {
	      my $n = $new->{$fd};
	      my $o = $old->{$fd};
	      next if $n->{ign} or !$o or $o->{ign};

	      my $f = $n->{file};
	      next if !defined($f) or 
	              !defined($o->{file}) or
		        $o->{file} ne $f;

	      $n->{diff} = 0;
	      $n->{diff} = $n->{pos} - $o->{pos} if
	        defined($n->{pos}) and 
		defined($o->{pos}) and 
		$n->{pos} > $o->{pos};

	      if ($n->{diff})
	        {
		  ## raw data for speed calucaltion:
	          $f{$f}{io} += $n->{diff};
	          push @{$f{$f}{fd}}, $fd;
		  my $perc = ($n->{pos}*100.)/($n->{size}||1);
		  ## name the position that is furthest, if multiple.
		  if ($perc > ($f{$f}{perc}||0))
		    {
		      $f{$f}{perc} = $perc;
		      $f{$f}{pos}  = $n->{pos};
		      $f{$f}{diff} = $n->{diff};
		    }
		  $f{$f}{size} = $n->{size};
		  $f{$f}{name} = $f;
	          $f{$f}{r}++ if $n->{rw} =~ m{r};
	          $f{$f}{w}++ if $n->{rw} =~ m{w};
		}
	    }


	  my @sorted = map { $f{$_} } sort { 
	  	$f{$b}{io}  <=> $f{$a}{io}
			    or
		$f{$b}{size} <=> $f{$a}{size}
			    or
		$f{$a}{fd}[0] <=> $f{$b}{fd}[0]
			     } keys %f;
	  my $printed = 0;
	  for my $i (0..$top_nnn-1)
	    {
	      ## speed calculation
	      my $t = $sorted[$i];
	      last unless defined $t;
	      my $fds = join('/',@{$t->{fd}});
	      my ($speed,$unit,$fmt) = fmt_speed($t->{io}, $int_sec);
	      $fds .= 'r' if $t->{r};
	      $fds .= 'w' if $t->{w};

	      my $perc_p = '';
	      # CAUTION: $t->{perc} evaluates < 100.0 sometimes when writing.
	      # possible cause: while blocked in write, disk size is updated early, 
	      # but fdinfo pos is updated late.
	      #
	      # We use same rounding in if and in sprintf, 
	      # to avoid printing (100%, 1.2GB) 0m:00
	      if (int($t->{perc}+.5) < 100)
	        {
	          $perc_p = sprintf " (%d%%", ($t->{perc}+.5);
		}
	      if ($t->{w} || 1)
	        {
		  # this was meant for writing, but it also makes sense 
		  # when reading e.g. block devices. my /dev/mmcblk0p1
		  # always reports size eq pos.
		  #
		  # offset
		  $perc_p .= length($perc_p) ? ", " : " (";
		  $perc_p .= fmt_speed($t->{pos});
		}
	      $perc_p .= ")" if length $perc_p;

	      ## raw data for eta calculation:
	      my $f = $t->{name};
	      push  @{$hist->{$f}}, [$old->{ts}, $f{$f}{diff}];
	      shift @{$hist->{$f}} if $#{$hist->{$f}} > $histlen;

	      ## eta calculation:
	      my $sum = 0;
	      my $tdiff = $new->{ts} - $hist->{$f}[0][0];
	      map { $sum += $_->[1]; } @{$hist->{$f}};
	      $sum = 1 if $sum < 1;
	      # warn "$t->{name} has no size\n" unless defined $t->{size};
	      # warn "$t->{name} has no pos\n" unless defined $t->{pos};
	      my $eta = ($t->{size}-$t->{pos}) * $tdiff / $sum;

              my $eta_p = ''; $eta_p = " ".fmt_eta($eta) if $t->{perc} < 100.0;
	      my $line = sprintf "p/%d/fd/%s %s $fmt%s%s%s", $pid, $fds,
	      			$t->{name}, $speed, $unit, $perc_p, $eta_p;

              ## make the line fit into the terminal.
	      if (defined $term_w and length $line > $term_w)
	        {
		  my $half1 = ($term_w-3)/2;
	          ## Randomize the position of the ellipsis to show overlapping context. 
		  ## Is that confusing, or is that helpful?
		  $half1 = int(0.5*$half1+rand($half1));
		  my $half2 = $term_w-3-$half1;
		  $line = substr($line, 0, $half1) . '...' . substr($line, -$half2);
		}

              print STDERR "$line\n";
	      # print STDERR "pos=$t->{pos}, sum=$sum, t=$tdiff\n";
	      $printed++;
	    }
	  if (!$printed)
	    {
	      my ($state,$syscall,$vmsize) = run_status($pid);
	      my $where = ''; $where = " in $syscall" if length($syscall||'') > 1;
	      print STDERR "p/$pid idle: $state$where vm:".fmt_speed($vmsize);
	      $new->{vmsize} = $vmsize;
	      $new->{vmsize_ts} = $new->{ts};
	      if ($old->{vmsize} and $new->{vmsize} > $old->{vmsize})
	        {
		  print STDERR " +".fmt_speed($new->{vmsize}-$old->{vmsize},
		                              $new->{vmsize_ts}-$old->{vmsize_ts});
		}
	      print STDERR "\n";
	    }
	}
      wait_interval();
      $old = $new;
    }
}

sub fmt_speed
{
  # Second parameter causes a '/s' suffix.
  # Omit the second paramater to format a kbyte/mbyte amount.
  my ($bytes,$secs) = @_;
  $bytes||=0;
  my $persec = '/s';
  unless ($secs)
    {
      $persec = '';
      $secs = 1;
    }
  my $speed = ($bytes+.0)/$secs;
  my $unit = "B$persec ";
  if ($speed > 500) { $speed *= .001; $unit = "KB$persec"; }
  if ($speed > 500) { $speed *= .001; $unit = "MB$persec"; }
  if ($speed > 500) { $speed *= .001; $unit = "GB$persec"; }
  my $fmt = '%3.1f'; $fmt = '%3.0f' if $speed > 10;
  return ($speed, $unit, $fmt) if wantarray;
  return sprintf "$fmt%s", $speed, $unit;
}

sub run_status
{
  my ($pid) = @_;
  my ($st,$sc,$sz) = ('-','-',0);

  if (open IN, "<", "/proc/$pid/status")
    {
      while (defined (my $line = <IN>))
        {
	  chomp $line;
	  if ($line =~ m{^State:\s+(\w+)\s+\((.*?)\)})
	    {
              ## second line is: 
	      # State:	S (sleeping)
              $st = "$1=$2" 
	    }
	  elsif ($line =~ m{^VmSize:\s+(\d+)\s*(\w+)})
	    {
	      # VmSize:	  448564 kB
	      $sz = $1;
	      my $unit = $2;
	      $sz *= 1024 if lc $unit eq 'kb';
	      $sz *= 1024*1024 if lc $unit eq 'mb';
	      last;
	    }
	}
      close IN;
    }

  return $st,$sc,$sz if $st =~ m{^R}; # avoid an oops. bnc#734751

  if (open IN, "<", "/proc/$pid/stack")
    {
      my @stack = <IN>;
      close IN;
      chomp @stack;
      ## try to pick a good name from the stack
      for my $frame (reverse @stack)
        {
	  # [<c033b565>] sys_select+0x85/0xb0
	  # [<c025ade0>] do_signal_stop+0x90/0x1e0
	  # [<c04ef3e9>] tty_read+0x79/0xd0
	  # [<c0331bc5>] pipe_wait+0x45/0x60

	  $sc = $1 if $frame =~ m{\b(sys_\w+)};		 
  	  $sc = $1 if $frame =~ m{\b([_\w]*signal_\w+)}; 
	}
      ## default to innermost frame, if nothing was good above.
      my $inner = $1 if defined $stack[0] and $stack[0] =~ m{\s+(\w+)};
      $sc = $inner if defined $inner and $sc eq '-';
      $sc .= ':'. $inner if defined $inner and $sc =~ m{^sys_};
      # warn Dumper \@stack;
    }

  return $st, $sc, $sz;
}


sub fdinfo
{
  my ($pid) = @_;

  unless (opendir DIR, "/proc/$pid/fd")
    {
      warn "/proc/$pid/fd: $!, retry as root?\n" if $!+0 == 13;	# EPERM
      return undef;
    }
  my %fd = map { $_ => {} } grep { /^\d+$/ } readdir DIR;
  closedir DIR;

  for my $fd (keys %fd)
    {
      $fd{$fd}{file} = readlink "/proc/$pid/fd/$fd";
      unless (defined $fd{$fd}{file})
        {
	  delete $fd{$fd};
	  next;		# happens a lot when monitoring myself.
	}
      $fd{$fd}{size} = -s $fd{$fd}{file};
      $fd{$fd}{size} = -s "/proc/$pid/fd/$fd" unless defined $fd{$fd}{size};
      # can we somehow get the size of a deleted file?
      warn "/proc/$pid/fd/$fd -> $fd{$fd}{file} has no size\n" unless defined $fd{$fd}{size};
      if (open IN, "<", "/proc/$pid/fdinfo/$fd")
        {
	  # pos:	0
	  # flags:	02
          while (defined(my $line = <IN>))
	    {
	      chomp $line;
	      $fd{$fd}{$1} = $2 if $line =~ m{^(\w+)[:\s]+(.*)};
	    }
          close IN;
        }
      my $rw = $fd{$fd}{flags}; $rw = 'rw' unless defined $rw;
      $rw = 'r' if $rw =~ m{.*0$};
      $rw = 'w' if $rw =~ m{.*1$};
      $fd{$fd}{ign}++ if $rw eq 'r' and !$opt_read;
      $fd{$fd}{ign}++ if $rw eq 'w' and !$opt_write;
      $fd{$fd}{rw} = $rw;
      ## never ignore 02 aka update aka rw
    }
  return \%fd;
}

sub fmt_eta
{
  my ($eta) = @_;
  my $hh = int($eta/3600.);
  $eta -= $hh * 3600;
  my $mm = int($eta/60.);
  $eta -= $mm * 60;
  if ($hh)
    {
      $mm++ if $eta > 30;
      return sprintf "%2dh:%02d", $hh, $mm;
    }
  return sprintf "%2dm:%02d", $mm, int($eta+.5);
}

## next two functions taken from File::Unpack
sub _children_fuser
{
  my ($file, $ppid) = @_;
  $ppid ||= 1;
  $file = Cwd::abs_path($file);

  opendir DIR, "/proc" or die "opendir /proc failed: $!\n";
  my %p = map { $_ => {} } grep { /^\d+$/ } readdir DIR;
  closedir DIR;

  # get all procs, and their parent pids
  for my $p (keys %p)
    {
      if (open IN, "<", "/proc/$p/stat")
        {
	  # don't care if open fails. the process may have exited.
	  my $text = join '', <IN>;
	  close IN;
	  if ($text =~ m{\((.*)\)\s+(\w)\s+(\d+)}s)
	    {
	      $p{$p}{cmd} = $1;
	      $p{$p}{state} = $2;
	      $p{$p}{ppid} = $3;
	    }
	}
    }

  # Weed out those who are not in our family
  if ($ppid > 1)
    {
      for my $p (keys %p)
	{
	  my $family = 0;
	  my $pid = $p;
	  while ($pid)
	    {
	      # Those that have ppid==1 may also belong to our family. 
	      # We never know.
	      if ($pid == $ppid or $pid == 1)
		{
		  $family = 1;
		  last;
		}
	      last unless $p{$pid};
	      $pid = $p{$pid}{ppid};
	    }
	  delete $p{$p} unless $family;
	}
    }

  my %o; # matching open files are recorded here

  # see what files they have open
  for my $p (keys %p)
    {
      if (opendir DIR, "/proc/$p/fd")
        {
	  my @l = grep { /^\d+$/ } readdir DIR;
	  closedir DIR;
	  for my $l (@l)
	    {
	      my $r = readlink("/proc/$p/fd/$l");
	      next unless defined $r;
	      # warn "$p, $l, $r\n";
	      if ($r eq $file)
	        {
	          $o{$p}{cmd} ||= $p{$p}{cmd};
	          $o{$p}{fd}{$l} = { file => $file };
		}
	    }
	}
    }
  return \%o;
}

# see if we can read the file offset of a file descriptor, and the size of its file.
sub _fuser_offset
{
  my ($p) = @_;
  for my $pid (keys %$p)
    {
      for my $fd (keys %{$p->{$pid}{fd}})
        {
	  if (open IN, "/proc/$pid/fdinfo/$fd")
	    {
	      while (defined (my $line = <IN>))
	        {
		  chomp $line;
		  $p->{$pid}{fd}{$fd}{$1} = $2 if $line =~ m{^(\w+):\s+(.*)\b};
		}
	    }
	  close IN;
	  $p->{$pid}{fd}{$fd}{size} = -s $p->{$pid}{fd}{$fd}{file};
	}
    }
}

## The following code is adopted from ioana-0.41, jw@suse.de, 2012-11-04

## returns device/inode in string representation.
sub inode_pair
{
  my ($h, $fail) = @_;
  return $h->{I} if defined $h->{I};

  if ($fail)
    {
      return undef unless defined $h->{D} and defined $h->{i};
    }

  my $d = $h->{D}||0;
  $d = hex $d if $d =~ m{^0x}i;
  $d .= "/" . ($h->{i}||0);
  return $h->{I} = $d;  
}


sub lsof_pid
{
  my ($fname) = @_;


  my %procs = ( 0 =>  {} );	# results go here
  my $p = $procs{0};
  
  my $f = '0';		# NUL separated output.
  $f .= 'a';		# r=read, w=write, u=update
  $f .= 'd';		# device character code, (does not work?)
  $f .= 'D';		# filesystem-devnode in hex
  $f .= 'r';		# device major/minor in hex
  $f .= 'i';		# inode number
  $f .= 'f';		# file descriptor
  $f .= 'o';		# file offset (does not work?)
  $f .= 's';		# file size
  $f .= 't';		# file type: REG, CHR, DIR
  $f .= 'T';		# TCP/IP info
  $f .= 'S';		# stream module and device names
  $f .= 'n';		# name, comment or internet address, 
                        # (using \r\n but not \\, beware!)

  my $cmd = "env LC_ALL=C /usr/bin/lsof -F $f";

  my $avoid_block = 0;	# must not be set, or lsof bails out with 
                        # lsof: status error on $fname: Resource temporarily unavailable
  # -b is essential to avoid blocking in stat() calls on dead filesystems.
  # but it makes certain fields not available, sigh.
  # types CHR and DIR may show up as 'unknown', and
  # n-names may look like '/usr/bin/perl (stat: Resource temporarily unavailable)'
  # or '/suse/jw/src/perl/ioana-0.08 (wotan:/real-home/jw)'
  # some of the silly texts behind the names can be prevented with -w, but not all.
  # sigh.
  $cmd .= " -w -b" if $avoid_block;

  $cmd .= " -- '$fname'";

  open IN, "$cmd 2>/dev/null|" or die "failed to run $cmd: $!\n";
  while (defined (my $line = <IN>))
    {
      my %h = $line =~ m{(\w)([^\0]*)\0}g;

      if (defined($h{n}) and $h{n} =~ m{^(.*?)\s+\((\S+:.*?)\)$})
        {
	  ## this did not happen on sles9. it happens on code10.
	  # fmema tREGD0x307i28484n/usr/bin/perl (stat: Resource temporarily unavailable)
	  # fmema tREGD0x0i0n[heap] (stat: Resource temporarily unavailable)
	  # fmema tREGD0x307i10926n/lib64/ld-2.3.91.so (stat: Resource temporarily unavailable)
	  # or:
	  # fmema tREGD0x0i0n[heap] (stat: No such file or directory)
	  #
	  # lsof appears to be immune to locale, but we still force LC_ALL=C make sure
	  # future releases still talk something we can parse.

	  $h{n} = $1;
	  my $rest = $2;
	  if ($verbose > 1)
	    {
	      warn "lsof: message '$rest' stripped from path name ($h{n})\n" unless 
		    $h{n} eq '[heap]' or 
		    $rest =~ m{^stat: Resource temporarily unavailable$};
	    }
	}

      if (defined $h{p})
        {
	  $cur_pid = $h{p};
	  $procs{$cur_pid} = {} unless defined $procs{$cur_pid};
	  $p = $procs{$cur_pid};
	}
      next unless defined $h{f};	# ignore p line

      if ($h{f} =~ m{^(\d+)$})
        {
          $p->{fd}{$1} = \%h;
	}
      elsif ($h{f} =~ m{^(txt|rtd|cwd)$})
        {
	  $p->{$1} = \%h;
	}
      elsif ($h{f} eq 'mem')
        {
	  $p->{mmap}{inode_pair(\%h,1)} = \%h;
	}
      else
        {
	  die Dumper "unknown f:", \%h;
	}
    }

  close IN;

  die "lsof returned data without previous p line" if scalar keys %{$procs{0}};
  delete $procs{0};
  return \%procs;
}


sub find_termsize_fn
{
  if (eval "use Term::ReadKey; 1")
    {
      return sub
        {
	  my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
	  return ($wchar, $hchar);
	}
    }

  if (eval "use Term::Size::Any; 1")
    {
      return sub
        {
          return Term::Size::Any::chars(*STDOUT{IO});
	}
    }

  if (eval "use Term::Size; 1")
    {
      return sub
        {
          return Term::Size::chars(*STDOUT{IO});
	}
    }

  return sub { return (undef, undef); };
}
