echo %1\Development\msys\1.0\mingw /mingw > %1\Development\msys\1.0\installer\temp\fstab.temp
echo %1\Development\Source /gnustep-source >> %1\Development\msys\1.0\installer\temp\fstab.temp
echo %1 /gnustep-install-dir >> %1\Development\msys\1.0\installer\temp\fstab.temp

%1\Development\msys\1.0\bin\sh.exe /usr/installer/fstab.sh

echo export GNUSTEP_INSTALL_DIR=/%1 > %1\Development\msys\1.0\installer\temp\set-gnustep-install-dir.sh.temp1
echo export GNUSTEP_INSTALL_DIR_WINDOWS_PATH=%1 > %1\Development\msys\1.0\installer\temp\set-gnustep-install-windows-dir.sh.temp1

%1\Development\msys\1.0\bin\sh.exe /usr/installer/create-set-gnustep-install-dir.sh
