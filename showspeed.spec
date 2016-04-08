#
# spec file for package showspeed
#
# Copyright (C) 2012,2013, jw@suse.de, openSUSE.org
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

Name:           showspeed
Version:        0.16
Release:        1
License:        GPL-2.0 or GPL-3.0
Summary:        Print speed and eta for a procees, file, or network
Url:            https://github.com/jnweiger/showspeed/
Source0:        showspeed.pl
Source1:        COPYING
Group:          Development/Tools/Other
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildArch:	noarch
# to generate the usage:
BuildRequires:	perl

%description

showspeed
=========

Print I/O activity of process, files, or network.
Print estimated time of arrival.

It can attach to a running process, identified by process name or pid, if the
name is ambiguous.  A line of statistics is printed every two seconds. If
possible an ETA countdown timer is also printed.

The effect of showspeed is similar to inserting |pv| into a command pipeline. Showspeed has these advantage over pv:

 * No need to construct an artificial pipeline if monitoring a simple command.
 * You can call it *after* starting your command or pipeline.
 * You can start stop monitoring as you like.
 * It can forsee the end and print an estimated time of arrival. Sometimes. 


Authors:
--------
	Juergen Weigert <jw@suse.de>

%prep
cp %{S:1} .

%build

%install
install -D -m755 %{S:0} %{buildroot}%{_bindir}/showspeed
(cd %{buildroot}%{_bindir}; perl showspeed --help) > showspeed.1 && /bin/true
install -D -m644 showspeed.1 %{buildroot}%{_mandir}/man1/showspeed.1

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root)
%doc COPYING
%{_bindir}/*
%{_mandir}/man1/*

%changelog
