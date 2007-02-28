tmp=/usr/installer/temp
failed=$tmp/INSTALLATION-BASE-TEST-FAILED
succeeded=$tmp/INSTALLATION-BASE-TEST-SUCCEEDED

rm $tmp/which-defaults-should-be $tmp/which-defaults-actual $tmp/diff-defaults $tmp/defaults-read-should-be $tmp/defaults-read-actual $tmp/diff-defaults-read
rmdir $failed $succeeded

echo $GNUSTEP_INSTALL_DIR/System/Tools/defaults > $tmp/which-defaults-should-be
type -p defaults > $tmp/which-defaults-actual

diff $tmp/which-defaults-actual $tmp/which-defaults-should-be > $tmp/diff-defaults

if [ -s $tmp/diff-defaults ]
then
  echo Differences, so something is wrong
  mkdir $failed
  sh /usr/installer/create-log-tar.sh
else
  echo No differences, so everything is OK
  echo GNUstepBuildEnvironment Test \'Yes\' > $tmp/defaults-read-should-be
  defaults write GNUstepBuildEnvironment Test Yes
  defaults read GNUstepBuildEnvironment Test > $tmp/defaults-read-actual
  diff $tmp/which-defaults-actual $tmp/which-defaults-should-be > $tmp/diff-defaults-read
  if [ -s $tmp/diff-defaults-read ]
  then
    echo Actually using defaults went wrong
    mkdir $failed
    sh /usr/installer/create-log-tar.sh
  else
    echo Absolutely everything went spiffy
    mkdir $succeeded
  fi
fi
