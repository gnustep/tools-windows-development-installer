# First make sure we install to the paths the installer set
. /etc/profile.d/02-set-gnustep-system.sh

if [ -s $GNUSTEP_SYSTEM_ROOT/Tools/gnustep-base.dll ]
then
  echo base seems to have been compiled
  cd /gnustep-source/gui
  make install messages=yes warn=no

  cd /gnustep-source/back
  make install messages=yes warn=no
else
  echo base seems not to have been compiled not building gui either
fi

