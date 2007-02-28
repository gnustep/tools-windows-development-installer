totarfile=/usr/installer/temp/totar
find /usr/installer ! -name totar* > $totarfile
# cd-ing to /gnustep-source is a workaround for an error that occurs in "find /gnustep-source"
cd /gnustep-source
find /gnustep-source \( -name *.log -o -name *.status -o -name config.h -o -name GSConfig.h \) >> $totarfile
tar -c --no-recursion --files-from=$totarfile | bzip2 -9 > /gnustep-install-dir/installer.tar.bz2
