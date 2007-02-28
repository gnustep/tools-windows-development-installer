# First make sure we install to the paths the installer set
. /etc/profile.d/02-set-gnustep-system.sh

# Build the libobjc library and install it in the right location
cd /gnustep-source/libobjc
make install messages=yes

#  Reinstall GNUstep make (with ObjC this time)
cd /gnustep-source/make
make distclean
./configure --prefix=$GNUSTEP_INSTALL_DIR --with-config-file=$GNUSTEP_INSTALL_DIR/GNUstep.conf-dev  --disable-importing-config-file
make install messages=yes

# ffcall
cd /gnustep-source/ffcall
./configure --prefix=$GNUSTEP_SYSTEM_ROOT
make messages=yes
make install messages=yes

# Build and install the base library itself
cd /gnustep-source/base
#export LDFLAGS=-lwsock32
./configure --disable-xml
make install messages=yes warn=no
