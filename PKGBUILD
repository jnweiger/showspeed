# $Id$
# Maintainer: Jürgen Weigert <jw@owncloud.com>
# This is for Arch Linux.

pkgname=showspeed
pkgver=0.16
pkgrel=1
pkgdesc="Print I/O activity of process, files, or network. Print estimated time of arrival"
arch=('any')
url="https://github.com/jnweiger/showspeed"
license=('GPL-2.0')
depends=('perl')
optdepends=('docker')
makedepends=('perl')
options=('!strip')
source=('https://github.com/jnweiger/showspeed/blob/master/showspeed.pl')
# must say SKIP so that it builds.
sha1sums=('SKIP')


package() {
  install -d ${pkgdir}/usr/bin

  # an unpacked tar ball would be in ${srcdir}/${pkgname} or similar.
  cp /usr/src/packages/SOURCES/${pkgname}.pl ${pkgdir}/usr/bin/${pkgname}
}
