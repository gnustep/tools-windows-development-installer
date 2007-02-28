set CYGWIN="nowinsymlinks notty notitle binmode nontsec nontea nosmbntsec"

if "x%MSYSTEM%" == "x" set MSYSTEM=MINGW32

%1\msys\1.0\bin\sh.exe --login -c %2