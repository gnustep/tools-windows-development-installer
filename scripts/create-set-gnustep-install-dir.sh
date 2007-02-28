/bin/sed 's/\\/\//g' /usr/installer/temp/set-gnustep-install-dir.sh.temp1 > /usr/installer/temp/set-gnustep-install-dir.sh.temp2
/bin/sed 's/://g' /usr/installer/temp/set-gnustep-install-dir.sh.temp2 > /etc/profile.d/01-set-gnustep-install-dir.sh
/bin/sed 's/\\/\//g' /usr/installer/temp/set-gnustep-install-windows-dir.sh.temp1 >> /etc/profile.d/01-set-gnustep-install-dir.sh
