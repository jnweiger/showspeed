#!/bin/sh
#
# pull a file from github and make it a tar ball for RPM and DEB builds
#
# 2014,2016 jw@owncloud.com

set -x
tstamp=$(date +"%Y%m%d")

source=$(grep Source0: *.spec)
set $source
source=$2
name=showspeed
srcname=showspeed.pl
rm $srcname
# if there is no url in the specfile, use this:
if [ "$source" == "$srcname" ]; then
 source="https://raw.githubusercontent.com/jnweiger/$name/master/$srcname"
fi

set -x
wget $source -O $srcname
version=$(perl ./$srcname --version 2>&1)
sed -i -e "s@^\(Version:\s*\).*@\1"$version"@" *.spec
sed -i -e "s@^\(pkgver=\s*\).*@\1"$version"@" PKGBUILD
sed -i -e "s@^\(Version:\s*\).*@\1"$version-$tstamp"@" *.dsc

tar zcvf $name.tar.gz $srcname COPYING
set +x
osc vc -m "Version $version -- $0"

echo Try: debchange -mc debian.changelog
