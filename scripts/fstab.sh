/bin/sed 's/"//g' /usr/installer/temp/fstab.temp > /usr/installer/temp/fstab.temp2
/bin/sed 's/\\/\//g' /usr/installer/temp/fstab.temp2 > /etc/fstab