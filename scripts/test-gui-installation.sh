tmp=/usr/installer/temp
failed=$tmp/GUI-INSTALLATION-TEST-FAILED
succeeded=$tmp/GUI-INSTALLATION-TEST-SUCCEEDED

if [ -s $GNUSTEP_SYSTEM_ROOT/Tools/gnustep-gui.dll ]
then
  echo GUI seems to have been compiled
  mkdir $succeeded
else
  echo GUI seems not to have been compiled
  mkdir $failed
  sh /usr/installer/create-log-tar.sh
fi
