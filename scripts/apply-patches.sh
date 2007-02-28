# This script is used by the installer to apply patches it could contain.

for patchfile in /gnustep-source/patches*/*.patch ; do patch -p0 -d /gnustep-source/ < $patchfile ; done


# Copy reject files to /usr/installer/log, so we know what failed

find /gnustep-source -name *.rej -a -exec cp --parents {} /usr/installer/log/ \;
