. /etc/profile.d/01-set-gnustep-install-dir.sh

# rm -rf /mingw/lib/gcc-lib/mingw32/3.2/include/objc/
# rm /mingw/lib/libobjc.*

cd /gnustep-source/make
./configure --prefix=$GNUSTEP_INSTALL_DIR --with-config-file=$GNUSTEP_INSTALL_DIR/GNUstep.conf-dev  --disable-importing-config-file
make install messages=yes

cp /usr/installer/set-gnustep-system.sh /etc/profile.d/02-set-gnustep-system.sh
