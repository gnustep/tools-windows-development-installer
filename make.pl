#!/usr/local/bin/perl -w
#
#
# make.pl - a perl script to build an Advanced Planning installer. Roughly does this:
#		- Copies everything needed to a temp directory (mainly to remove CVS dirs)
#		- Replaces keywords in .iss-script (see createScriptFromTemplate for keywords)
#		- Actually builds the installer
#		- Copies the installer back to the original directory
#		- Removes all temporary stuff
#
#
#
#         - input to the compiler, as mentioned above consists of:
#
#
#               - setup-compiler -- the setup compiler used to build
#                                   the installer.  So this will not end
#                                   up in the installer.
#
#               - scripts  -- scripts that will build GNUstep
#                             after the content is unpacked at the
#                             target system
#
#               - doc      -- a few text files to be installed,
#                             typically refering to the installer and
#                             not specific to the installed components
#
#               - libobjc  -- the libobjc project from the GNUstep project,
#                             to replace the default libobjc of the compiler
#
#               - make     -- the make system of the GNUstep project
#
#               - iconv    -- character encoding library needed by base
#
#               - intl     -- ??
#
#               - ffcall   -- foreign function call library, needed by base
#
#               - zlib     -- compression library, needed by base and gui
#
#               - base     -- the GNUstep base library
#
#               - libtiff  -- tiff support, needed by gui
#
#               - libpng   -- png support, needed by gui
#
#               - libjpeg  -- jpeg support, needed by gui
#
#               - gui      -- the GNUstep gui library
#
#               - back     -- the GNUstep back library
#
#               - patches  -- A file containing patches to the sources
#
#        - organization of input
#               there are a few ways to provide input for the installer
#
#               - packages -- path to a directory containing:
#
#                             ffcal-*.tar.gz
#                             libiconv-*.zip
#                             libintl-*.zip
#                             gnustep-base-*.tar.gz
#                             gnustep-make-*.tar.gz
#                             gnustep-objc-*.tar.gz
#			      gnustep-gui-*.tar.gz
#			      gnustep-back-*.tar.gz
#                             zlib-*.zip
#                             tiff-*.zip
#                             libpng-*.zip
#                             libjpeg-*.zip
#                             patch
#
#                             msys-*.exe
#                             mingw-*.exe
#
#
#      Prerequisites
#      -------------
#
#      The perl script assumes that a Achive::zip is installed.
#      It also uses Archive::tar but this is bundled with the Activestate
#      perl.
#      On top of that Digest::MD5 is required.
#      Win32::AbsPath is also required.
#
# TODO:
#  -
use diagnostics;
use strict;
use 5.005;
use File::Temp "tempdir";
use File::Path;
use File::Basename;
use File::Copy;
use File::Find;
use Getopt::Long;
use Pod::Usage;
use Cwd;
use Archive::Tar;
use Archive::Zip;
use Text::Template;
use Digest::MD5;
use IO::Handle;
use Win32::AbsPath;

autoflush STDOUT 1;

my $needToInstallMSYS = 1;
my $cleanup = 1;	   # -nocleanup leaves the temporary directory
my $compression = 1;       # -nocompression is way faster
my $buildCustom = 0;       # -custom to include the custom patches
my $leavelogs = 1;	   # -noleavelogs doesn't put all created logs in ./logs
my $verbose = 0;           # -verbose gives more noise
my $console = 1;           # -noconsole creates logfile instead of writing to stdout
my $makebinary = 1;        # -nobinary creates only source-only installer
my $outputPath = ".";      # -output specifies the path where logdir and installer end up
my $help = 0;
my $man = 0;
my $sourcePath = ".";
my $packagesPath;
my @projects = ( "base", "make", "libiconv", "libintl", "zlib", "ffcall", "libobjc", "scripts", "doc",
		 "patches", "libtiff", "libpng", "libjpeg", "gui", "back" );
my @localprojects = (); # Projects whose source is directly in the make.pl directory

my @tempProjects;
my %projectToCVSInfo;
my %projectToPackages;
my %projectToPackagePatterns;
my %projectToExtractedPath;
my $rootIsRemote = 0;
my %checksums = ();
my $coreVersion;
my $devLibsVersion;

# Prototypes
sub getVersionOfProject($);
sub coreVersion();
sub devLibsVersion();
sub copyDirectoryTreeFromTo($$);

GetOptions ('extractedpath=s' => \$sourcePath,
	    'packagespath=s' => \$packagesPath,
	    'outputpath=s' => \$outputPath,
	    'cleanup!' => \$cleanup,
	    'compression!' => \$compression,
	    'custom!' => \$buildCustom,
	    'verbose!' => \$verbose,
	    'console!' => \$console,
	    'binary!' => \$makebinary,
	    'help|?' => \$help,
	    'man' => \$man) || pod2usage(2);

$packagesPath = cwd()."/$packagesPath" if ($packagesPath !~ /^.:/);

if (!$console)
  {
    open(STDOUT, ">>$outputPath/GNUstep-development-installer.log"); # redirect them to the log file
    open(STDERR, ">>$outputPath/GNUstep-development-installer.log"); # redirect them to the log file
  }

pod2usage(1) if ($help);
pod2usage(-exitstatus => 0, -verbose => 2) if ($man);

if (-e "$sourcePath/msys-source") {
  push @projects, "msys-source";
  $needToInstallMSYS = 0;
} else {
  push @projects, "mingw", "msys";
  $needToInstallMSYS = 1;
}

if ($buildCustom)
  {
    push @projects, "patches-Custom";
  }

if (coreVersion())
  {
    push @projects, "core";
    @projects = grep(!/(base|make|back|gui)/, @projects);
  }

if (devLibsVersion())
  {
    push @projects, "dev-libs";
    @projects = grep(!/libobjc/, @projects);
  }

my $tempdir = tempdir("gnustep-installer-XXXX", TMPDIR=>1, CLEANUP=>$cleanup);
print "Temp directory: $tempdir\n";

# Figure out where this project has been extracted and return that directory.
sub diskLocationOfProject($)
  {
    my $project = shift;
    if ($project eq "libobjc")
      {
	if (defined($projectToExtractedPath{$project}))
	  {
	    return $projectToExtractedPath{$project};
	  }
	if (defined($projectToExtractedPath{"dev-libs"}))
	  {
	    return $projectToExtractedPath{"dev-libs"}."/libobjc";
	  }
      }
    return defined($projectToExtractedPath{$project})?$projectToExtractedPath{$project}:"$tempdir/$project";
  }

sub coreVersion()
  {
    if (defined $packagesPath && length $packagesPath > 0)
      {
	find (sub { $coreVersion=$1 if (/core\.(\d+)\.tar\.bz2/); }, $packagesPath);
      }
    return $coreVersion;
  }

sub devLibsVersion()
  {
    if (defined $packagesPath && length $packagesPath > 0)
      {
	find (sub { $devLibsVersion=$1 if (/dev-libs\.(\d+)\.tar\.bz2/); }, $packagesPath);
      }
    return $devLibsVersion;
  }

sub getInstallerId
  {
    my $id = "";

    if (defined $coreVersion)
      {
	$id = "core-$coreVersion";
      }
    else
      {
	$id = "base-".getVersionOfProject("base")."-gui-".getVersionOfProject("gui");
	$id =~ s/\s\((:?un)?stable\)//g;
      }

    return $id;
  }


sub getInstallerName($$)
  {
    my $patched = shift;
    my $binaries = shift;

    return "GNUstep-".getInstallerId().($patched?"-Custom":"").($binaries?"":"-nobin");
  }


sub getChecksumOfFile($)
  {
    my $file = shift;
    open (FILE, $file) or return "";
    binmode (FILE);

    my $checksum=Digest::MD5->new->addfile(*FILE)->hexdigest;
    close FILE;
    return $checksum;
  }


sub justTheFilename($)
  {
    my $file = shift;
    $file =~ /([^\\\/]+)$/;
    return $1;
  }


sub msysCommands
  {
    my @commands = @_;
    my $dir = cwd();
    # Make $dir the current directory with forward slashes
    $dir =~ s#\\#/#g;

    for my $command (@commands)
      {
	print "$command\n";
	my $commandline = "$tempdir/msys-source/msys/1.0/bin/sh.exe -login -c \"cd $dir && $command\"";
	system($commandline);
      }
  }


sub createScriptFromTemplate($$$$$)
{
  my $scriptfile = shift;
  my $templatefile = shift;
  my $injectCustomPatches = shift;
  my $injectBinaries = shift;
  my $relativeGNUstepInstallDir = shift;
  open ISS, ">$scriptfile"
    or die "Couldn't create $scriptfile: $!";
  my $template = Text::Template->new(SOURCE => $templatefile)
    or die "Couldn't construct template: $Text::Template::ERROR";
  my %vars = (injectCustomPatches => $injectCustomPatches,
	      installerVersion => getInstallerId(),
	      injectBinaries => $injectBinaries,
	      compression => $compression,
	      relativeGNUstepInstallDir => $relativeGNUstepInstallDir,
	      doc_path => diskLocationOfProject("doc"),
	      scripts_path => diskLocationOfProject("scripts"),
	      conf_path => diskLocationOfProject("conf"),
	      patches_path => diskLocationOfProject("patches"),
	      msys_path => diskLocationOfProject("msys-source"),
	      make_path => diskLocationOfProject("make"),
	      ffcall_path => diskLocationOfProject("ffcall"),
	      libobjc_path => diskLocationOfProject("libobjc"),
	      libiconv_path => diskLocationOfProject("libiconv"),
	      libintl_path => diskLocationOfProject("libintl"),
	      zlib_path => diskLocationOfProject("zlib"),
	      base_path => diskLocationOfProject("base"),
	      libtiff_path => diskLocationOfProject("libtiff"),
	      libpng_path => diskLocationOfProject("libpng"),
	      libjpeg_path => diskLocationOfProject("libjpeg"),
	      gui_path => diskLocationOfProject("gui"),
	      back_path => diskLocationOfProject("back"),
	      installerName => getInstallerName($injectCustomPatches, $injectBinaries));
  $template->fill_in(HASH => \%vars,
		     DELIMITERS => [ '[@', '@]' ],
		     OUTPUT => \*ISS)
    or die "Error filling in template: $Text::Template::ERROR";
  close ISS;
}

sub createScriptsFromTemplate($)
  {
    my $script_path = shift;
    my $template_file = "$script_path/test-back-installation.sh.template";
    my $script_file = "$script_path/test-back-installation.sh";

    # Get the interface version number
    my $interface_version_number;
    open BACK_VERSION, diskLocationOfProject("back")."/Version"
      or die "Can't find version of back";
    while (<BACK_VERSION>)
      {
	$interface_version_number = $1 if (/INTERFACE_VERSION_NUMBER=(.*)$/);
      }
    close BACK_VERSION;
    die "Can't find interface version number of back" if (!defined $interface_version_number);

    open OUT, ">$script_file"
      or die "Couldn't create $script_file: $!";
    my $template = Text::Template->new(SOURCE => $template_file)
      or die "Couldn't construct template: $Text::Template::ERROR";
    $template->fill_in(HASH => { interface_version_number => $interface_version_number },
		       DELIMITERS => [ '[@', '@]' ],
		       OUTPUT => \*OUT)
      or die "Error filling in template: $Text::Template::ERROR";
    close OUT;
  }



sub copyDirectoryTreeFromTo($$)
  {
    my $source_directory = shift;
    my $target_directory = shift;

    print "$source_directory -> $target_directory\n" if ($verbose);

    # Check whether we got sensible arguments
    return if (!defined($source_directory) || !defined($target_directory));
    return if (!-d $source_directory);

    # Make sure target directory exists
    mkpath $target_directory;
    die "Can't create $target_directory." if (!-d $target_directory);

    # Iterate over all items in $source_directory that do not lead to a
    # parent directory
    opendir(DIR, $source_directory) || die "Can't open directory $source_directory: $!\n";
    foreach (grep { !/^\.$/ && !/^\.\.$/ && !/^\.cvsignore$/s } readdir(DIR))
    {
	my $directory_entry = "$source_directory/$_";
	if (-d $directory_entry && !/^CVS$/)
	{
	    copyDirectoryTreeFromTo($directory_entry, "$target_directory/$_");
	}
	else
	{
	    # Note we happily ignore errors
	    unlink "$target_directory/$_";
	    copy($directory_entry, "$target_directory/$_");
	    chmod 0666, "$target_directory/$_";
	}
    }
    closedir(DIR);
  }

sub myUntar
  {
    my ($tarfile, $destination) = @_;
    my $currentDir;
    my @result;
    my $tar;

    $checksums{$tarfile} = getChecksumOfFile($tarfile);

    $currentDir = cwd ();
    chdir ($tempdir);

    print "Extracting $tarfile --> $tempdir\n" if ($verbose);

    $tar = Archive::Tar->new ($tarfile, 1);
    @result = $tar->list_files ();

    $tar->extract(@result);

    # Take the first entry and figure out the directory where files got extracted to
    $result[0] =~ /^([^\/\\]+)/;
    my $resulting_directory = $1;

    print "Renaming directory $resulting_directory --> $destination\n" if ($verbose);
    move ($resulting_directory, $destination);

    chdir ($currentDir);
  }

sub myUntarBZ2($$)
  {
    my ($tarfile, $destination) = @_;
    my $currentDir;
    my @result;
    my $tar;

    $checksums{$tarfile} = getChecksumOfFile($tarfile);

    $currentDir = cwd ();
    chdir ($tempdir);

    print "Copying $tarfile --> $tempdir\n" if ($verbose);
    copy $tarfile, $tempdir;

    my $newtarfile = $tarfile;
    $newtarfile =~ s/^.*[\\\/]//;
    $newtarfile = $tempdir . "/$newtarfile";

    print "Uncompressing $newtarfile\n" if ($verbose);
    my $curdir = cwd();
    chdir "$tempdir";
    my $newtarbase = justTheFilename($newtarfile);
    my $msys_path = diskLocationOfProject("msys-source");
    `"$msys_path/msys/1.0/bin/tar" -jxf $newtarbase`;
    chdir $curdir;

    move ("core/base", "base");
    move ("core/back", "back");
    move ("core/gui", "gui");
    move ("core/make", "make");
    move ("dev-libs/libobjc", "libobjc");

    chdir ($currentDir);
  }


sub myUnzip
  {
    my ($zipfile, $destination) = @_;
    my $currentDir;
    my $zip;

    $checksums{$zipfile} = getChecksumOfFile($zipfile);

    $currentDir = cwd ();
    chdir ($tempdir);

    print "Extracting: $zipfile --> $destination\n" if ($verbose);
    $zip = Archive::Zip->new ($zipfile);
    $zip->extractTree ('', "$destination/");

    chdir ($currentDir);
  }


sub installMSYSandMinGW
  {
    if ($needToInstallMSYS)
      {
	print "Installing MSYS/MinGW to get them source...\n" if ($verbose);
	system("$projectToPackages{msys}->[0] /sp- /silent /dir=\"$tempdir\\msys-source\\msys\\1.0\"");
	$checksums{$projectToPackages{msys}->[0]} = getChecksumOfFile($projectToPackages{msys}->[0]);
	system("$projectToPackages{mingw}->[0] /sp- /silent /dir=\"$tempdir\\msys-source\\msys\\1.0\\mingw\"");
	$checksums{$projectToPackages{mingw}->[0]} = getChecksumOfFile($projectToPackages{mingw}->[0]);
	delete $projectToPackages{msys};
	delete $projectToPackages{mingw};
      }
  }

sub getVersionFromVersionFile($)
  {
    my $versionFile = shift;
    local *VERSION;
    local undef $/;

    open VERSION, $versionFile or die "Can't open $versionFile:$!";
    my $versionFileContent = <VERSION>;

    $versionFileContent =~ /MAJOR_VERSION=(\d+)/;
    my $major = $1;
    $versionFileContent =~ /MINOR_VERSION=(\d+)/;
    my $minor = $1;
    $versionFileContent =~ /SUBMINOR_VERSION=(\d+)/;
    my $subminor = $1;

    return "$major.$minor.$subminor (".(($minor%2)?"un":"")."stable)";
  }


sub getVersionFromLibobjc($)
  {
    my $dir = shift;
    my $GNUmakefile = "$dir/GNUmakefile";
    local *VERSION;
    local undef $/;

    open VERSION, $GNUmakefile or die "Can't open $GNUmakefile:$!";
    my $versionFileContent = <VERSION>;

    $versionFileContent =~ /VERSION=([0-9.]+)/;
    return $1;
  }


sub libVersionFilenameInDirectory($)
  {
    my $directory = shift;

    opendir(DIR, $directory) || die "Can't opendir $directory: $!";
    my @versionFiles = reverse sort grep { /-lib\.ver$/i && -f "$directory/$_" } readdir(DIR);
    closedir DIR;

    if (scalar(@versionFiles)<1)
      {
	warn "No version file found in $directory.\n";
	return;
      }

    if (scalar(@versionFiles)>1)
      {
	warn "Too many version files found in $directory.\n";
      }

    return  $versionFiles[0];
  }


sub getVersionFromLib($)
  {
    my $dir = diskLocationOfProject(shift);
    my $versionFile = "$dir/manifest/".libVersionFilenameInDirectory("$dir/manifest/");
    local *VERSION;
    local undef $/;

    open VERSION, $versionFile or die "Can't open $versionFile:$!";
    my $versionFileContent = <VERSION>;

    #Jpeg 6b: libraries
    #LibPng-1.2.8: Developer files
    #Tiff 3.5.7: developer files
    #Zlib 1.1.4: developer files
    #LibIconv 1.8: developer files
    #LibIntl 0.11.5: developer files
    return " $1" if ($versionFileContent =~ /(\d+\.\d+\.\d+)/);
    return " $1" if ($versionFileContent =~ /(\d+\.\d+)/);
    return " $1" if ($versionFileContent =~ /Jpeg\s(.*):/);
    return;
  }


sub getVersionFromMSYS($)
  {
    my $dir = shift;
    if (defined $projectToExtractedPath{"msys-source"})
      {
	$dir = $projectToExtractedPath{"msys-source"};
      }
    else
      {
	$dir =~ s/msys/msys-source/;
      }
    my $msysWelcome = "$dir/msys/1.0/doc/msys/MSYS_WELCOME.rtf";
    local *VERSION;
    local undef $/;

    open VERSION, $msysWelcome or die "Can't open $msysWelcome:$!";
    my $versionFileContent = <VERSION>;

    # Version 1.0.7
    $versionFileContent =~ /Version\s+([0-9.]+)/;
    return $1;
  }


sub getVersionFromMinGW($)
  {
    my $dir = shift;
    if (defined $projectToExtractedPath{"msys-source"})
      {
	$dir = $projectToExtractedPath{"msys-source"};
      }
    else
      {
	$dir =~ s/mingw/msys-source/;
      }

    my $mingwWelcome = "$dir/msys/1.0/mingw/doc/MinGW/MinGW_WELCOME.rtf";
    local *VERSION;
    local undef $/;

    open VERSION, $mingwWelcome or die "Can't open $mingwWelcome:$!";
    my $versionFileContent = <VERSION>;

    # Version 2.0.0
    $versionFileContent =~ /Version\s+([0-9.]+)/;
    return $1;
  }


sub getVersionFromFFCall($)
  {
    my $dir = diskLocationOfProject(shift);
    my $ffcallSpec = "$dir/ffcall.spec";
    local *VERSION;
    local undef $/;

    open VERSION, $ffcallSpec or die "Can't open $ffcallSpec:$!";
    my $versionFileContent = <VERSION>;

    #%define	version	1.8d
    $versionFileContent =~ /\%define\s+version\s+([0-9a-z.]+)/;
    return $1;
  }


sub getVersionOfProject($)
  {
    my $project = shift;
    return getVersionFromVersionFile(diskLocationOfProject($project)."/Version") if ($project =~ /(base|make|gui|back)$/);
    return getVersionFromLibobjc(diskLocationOfProject($project)) if ($project =~ /libobjc$/);
    return getVersionFromFFCall($project) if ($project =~ /ffcall$/);
    return getVersionFromMSYS($project) if ($project =~ /msys$/i);
    return getVersionFromMinGW($project) if ($project =~ /mingw$/i);
    return getVersionFromLib($project) if ($project =~ /(zlib|libtiff|libpng|libjpeg|libiconv|libintl)$/);
    return $coreVersion if ($project =~ /core$/);
    return $devLibsVersion if ($project =~ /dev-libs$/);
    return;
  }


sub copyLogsFromBuiltGNUstep($$)
  {
    return if (!$leavelogs);

    my $installername = shift;
    my $sourcedirectory = shift;
    my $targetdirectory;

    if ($installername =~ /(?:\/||\\)([^\\\/]+)\.exe/s)
      {
	$targetdirectory = $1;
      }
    else
      {
	$targetdirectory = $installername;
	$targetdirectory =~ s/\.exe//s;
      }

    $targetdirectory = "$outputPath/log/$targetdirectory";
    print "Copying logs from $sourcedirectory to $targetdirectory (\$installername=$installername)\n";
    mkpath $targetdirectory;

    copyDirectoryTreeFromTo("$sourcedirectory/Development/msys/1.0/installer", "$targetdirectory/installer");
    copyDirectoryTreeFromTo("$sourcedirectory/Development/Source/patches", "$targetdirectory/patches");
    copy("$sourcedirectory/installer.tar.bz2", "$targetdirectory") if (-e "$sourcedirectory/installer.tar.bz2");
    `"$tempdir/msys-source/msys/1.0/bin/tar" -jcf $targetdirectory.tar.bz2 $targetdirectory`;
    rmtree $targetdirectory;
  }




## Here the work of putting all the input in the correct location starts


# First directly copy already unpacked packages
if ($sourcePath)
  {
    @tempProjects = @projects;
    for my $project (@tempProjects)
      {
	my $path;
	if (-e "$sourcePath/$project")
	  {
	    $path = Win32::AbsPath::Fix ( $sourcePath );
	  }
	else
	  {
	    if (-e "./$project")
	      {
		$path = cwd();
		$path =~ s/\//\\/g;
	      }
	  }

	if (defined $path)
	  {
	    print "Copying $project...\n";
	    $projectToExtractedPath{$project} = "$path\\$project";
	    $projectToExtractedPath{$project} =~ s/\//\\/g;
#	    copyDirectoryTreeFromTo("$path/$project", "$tempdir/$project");
	    @projects = grep !/^$project$/, @projects;
	    push(@localprojects, $project);
	  }
      }
  }

if ($packagesPath)
  {
    %projectToPackagePatterns = (
				 msys => 'MSYS-(.*)\.exe$',
				 mingw => 'MinGW-(.*)\.exe$',
				 ffcall => 'ffcall-(.*)\.tar\.gz$',
				 make => 'gnustep-make-(.*)\.tar\.gz$',
				 libobjc => 'gnustep-objc-(.*)\.tar\.gz$',
				 libiconv => 'libiconv-.*\.zip$',
				 libintl => 'libintl-.*\.zip$',
				 base => 'gnustep-base-(.*)\.tar\.gz$',
				 patches => 'patches$',
				 "patches-Custom" => 'patches-Custom$',
				 zlib => 'zlib-.*\.zip$',
				 libtiff => 'tiff-.*\.zip$',
				 libpng => 'libpng-.*\.zip$',
				 libjpeg => 'jpeg-.*\.zip$',
				 gui => 'gnustep-gui-(.*)\.tar\.gz$',
				 back => 'gnustep-back-(.*)\.tar\.gz$',
				 core => 'core\.(\d+)\.tar\.bz2$',
				 'dev-libs' => 'dev-libs\.(\d+)\.tar\.bz2$'
			      );

#'
    @tempProjects = @projects;
    for my $project (@tempProjects)
      {
	if ($projectToPackagePatterns{$project})
	  {
	    my @findResult = ();
	    ## Try to find the right tar.gz / .exe file
	    find (sub { my $name = $_;
			if ($name =~ /$projectToPackagePatterns{$project}/) {
			  push @findResult, $File::Find::name;
			}
		      }, $packagesPath );
	    if (scalar (@findResult) == 0 && $project !~ /patches/)
	      {
		die "Can not find package for project $project.";
	      }
	    if (scalar (@findResult) > 1 && $project !~ /(zlib|libtiff|libpng|libjpeg|libiconv|libintl|patches)/)
	      {
		die "Found more than one package for project $project: ".join(", ",@findResult).".";
	      }
	    if (scalar (@findResult) > 3 && $project =~ /(zlib|libtiff|libpng|libjpeg)/)
	      {
		die "Found more than three packages for project $project.";
	      }
	    $projectToPackages{$project} = \@findResult;
	    @projects = grep !/^$project$/, @projects;
	  }
      }

    ## Now install MSYS and MingW
    installMSYSandMinGW();

    # At this point we are certain that msys and mingw are in
    # $tempdir/msys, so we can use msys tools if we like

    for my $project (keys %projectToPackages)
      {
	for my $package (@{$projectToPackages{$project}})
	  {
	    print "Preparing $package...\n";
	    if ($package =~ /tar\.bz2$/)
	      {
		myUntarBZ2($package, "$tempdir/$project");
	      }
	    else
	      {
		if ($package =~ /tar\.gz$/)
		  {
		    myUntar($package, "$tempdir/$project");
		  }
		else
		  {
		    if ($package =~ /\.zip$/)
		      {
			myUnzip($package, "$tempdir/$project");
		      }
		    else
		      {
			if (-d $package)
			  {
			    copyDirectoryTreeFromTo($package, "$tempdir/$project");
			  }
			else
			  {
			    die "No extraction method found for file: $package\n.";
			  }
		      }
		  }
	      }
	  }
      }
  }

if (scalar (@projects) > 0)
  {
    die "Could not find the following packages: @projects";
  }

# Create scripts that come from templates
{
  createScriptsFromTemplate(diskLocationOfProject("scripts"));
}

copy ("GNUstep-development.iss.template", $tempdir);
copy ("gnustep-logo.bmp", $tempdir);
copy ("gnustep-logo-32x32.ico", $tempdir);
copy ("GNUstep-development.iss", $tempdir);
copy ("Desktop.ini", $tempdir);

{
  local *BEFORE;
  local *VERSIONS;

  open BEFORE, ">>$tempdir/infobefore.txt";
  open VERSIONS, ">$tempdir/versions.txt";
  my $before = *BEFORE;
  my $versions = *VERSIONS;
  my $stdout = *STDOUT;

  my @handles = ($before, $versions);
  push(@handles, $stdout) if ($verbose);

  print BEFORE "This installer contains the following:\n\n";
  foreach my $handle (@handles)
    {
      my @p = ("base", "make", "gui", "back", "libobjc", "ffcall", "libiconv", "libintl", "zlib", "libtiff", "libpng", "libjpeg", "MinGW", "MSYS");
      if (defined $coreVersion)
	{
	  print $handle "core snapshot $coreVersion\n";
	  @p = grep(!/(base|make|back|gui)/, @p);
	}
      if (defined $devLibsVersion)
	{
	  print $handle "libobjc snapshot $devLibsVersion\n";
	  @p = grep(!/libobjc/, @p);
	}

      foreach my $proj (@p)
	{
	  print $handle "$proj version ".getVersionOfProject($proj)."\n";
	}
    }
}

sub scriptToReplaceInstallDirForFile($$$)
  {
    my $filename = shift;
    my $old_gnustep_install_dir = shift;
    my $new_gnustep_install_dir = shift;

    return
      'THE_FILE='.$filename."\n".
      'echo THE_FILE=$THE_FILE'."\n".
      'if [ -s $THE_FILE ]'."\n".
      'then'."\n".
      'THE_FILE_OLD=$THE_FILE.old'."\n".
      'echo THE_FILE_OLD=$THE_FILE_OLD'."\n".
      'mv $THE_FILE $THE_FILE_OLD'."\n".
      'echo mv $THE_FILE $THE_FILE_OLD done'."\n".
      '/bin/sed s#'.$old_gnustep_install_dir.'#'.$new_gnustep_install_dir.'#g $THE_FILE_OLD > $THE_FILE'."\n".
      'echo /bin/sed s#'.$old_gnustep_install_dir.'#'.$new_gnustep_install_dir.'#g $THE_FILE_OLD'."\n".
      'rm $THE_FILE_OLD'."\n".
      'fi'."\n";
  }

sub _buildInstallerInDir($$)
  {
    my $dir = shift;
    my $patched = shift;
    my $scriptfile = "$dir/GNUStep-development".($patched?"-patched":"").".iss";
    my $templatefile = "$dir/GNUstep-development.iss.template";
    createScriptFromTemplate($scriptfile, $templatefile, $patched, 0, "GNUstep");
    my $installername = "$dir\\Output\\".getInstallerName($patched,0).".exe";
    my $command = "setup-compiler\\ISCC.exe ".($verbose?"":"/q ")." \"$scriptfile\"";
    print "$command\n";
    system ($command) == 0
      or die "Compiling of $scriptfile failed: $?";

    return if (!$makebinary);

    # Now run this installer, creating binaries
    print "Building binaries with $installername...\n";
    my $gnustepInstallDir = tempdir("GNUstep-XXXX", DIR=>$dir);
    $gnustepInstallDir =~ /[\\\/](GNUstep-....)$/;
    my $relativeGNUstepInstallDir = $1;
    $command = "\"$installername\" /silent /log /noicons /dir=\"$gnustepInstallDir\" /components=build/base,build/base/gui";
    print "$command\n";
    delete $ENV{PATH};
    system($command);
    # Copy the created logs here if needed
    copyLogsFromBuiltGNUstep($installername, $gnustepInstallDir);

    my $scripts_path = diskLocationOfProject("scripts");

    # Now create an installer with binaries
    {
      my $old_gnustep_install_dir = "/".$gnustepInstallDir;
      $old_gnustep_install_dir =~ s/://;
      $old_gnustep_install_dir =~ s/\\/\//g;

      open OUT, ">$scripts_path/replace-gnustep-system-root.sh" or die "Can't open scripts/replace-gnustep-system-root.sh:$!";
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Library/Makefiles/GNUstep.sh',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Library/Makefiles/GNUstep.csh',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Library/Makefiles/config.make',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Library/Makefiles/config.make',
						 "C:/GNUstep", '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Library/Makefiles/Additional/base.make',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Tools/openapp',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/System/Tools/opentool',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR');
      print OUT scriptToReplaceInstallDirForFile('$GNUSTEP_INSTALL_DIR/GNUstep.conf-dev',
						 $old_gnustep_install_dir, '$GNUSTEP_INSTALL_DIR_WINDOWS_PATH');
      print OUT 'cp /usr/installer/set-gnustep-system.sh /etc/profile.d/02-set-gnustep-system.sh'."\n";
      close OUT;
    }

    $scriptfile = "$dir/GNUStep-development".($patched?"-patched":"")."-bin.iss";
    createScriptFromTemplate($scriptfile, $templatefile, $patched, 1, $relativeGNUstepInstallDir);
    $installername = "$dir\\Output\\".getInstallerName($patched,1).".exe";
    $command = "setup-compiler\\ISCC.exe ".($verbose?"":"/q ")."\"$scriptfile\"";
    print "$command\n";
    print "cwd=".cwd()."\n";
    system ($command) == 0
      or die "Compiling of $scriptfile failed: $?";
    unlink "$scripts_path/replace-gnustep-system-root.sh";
    copy $installername, $outputPath;
    $checksums{$installername} = getChecksumOfFile($installername);
  }

_buildInstallerInDir($tempdir, $buildCustom);

open CRC, ">doc/MD5-checksums-for-Windows-Installer-Generated-".getInstallerId() or die "Can't open checksum file for writing: $!";
print CRC "MD5 checksum for the installer:\n\n";
foreach my $filename (keys %checksums)
  {
    next if (justTheFilename($filename) !~ /^GNUstep.*\.exe$/);

    print CRC $checksums{$filename}." *".justTheFilename($filename)."\n";
  }
print CRC "\nMD5 checksum for the files that are contained in the installer:\n\n";

foreach my $filename (sort keys %checksums)
  {
    if ( justTheFilename($filename) !~ /^GNUstep.*\.exe$/ )
      {
	print CRC $checksums{$filename}." *".justTheFilename($filename)."\n";
      }
  }
close CRC;

__END__
=head1 NAME

  make.pl - Create a GNUstep development installer

=head1 SYNOPSIS

make.pl [options]

 Options:
   -help            brief help message
   -man             full documentation
   -verbose         more noise on stdout
   -nocleanup       leave temporary files behind
   -path [path]     source path (defaults to .)
   -packagespath [path]  package path, path pointing to the source packages (.tar.gz or .exe)
   -custom
   -nocompression   don't compress resulting installer

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-verbose>

Gives more progress information.

=item B<-extractedpath [path]>

A directory containing extracted sources for projects, in
subdirectories named after those projects.

=item B<-custom>

Build an installer containing the custom patches.

=item B<-nocleanup>

While creating an installer, all files are copied to a temporary
directory which normally is deleted when done. With -nocleanup it is
left behind.

=item B<-nobinary>

Don't build an installer containing binaries.

=item B<-nocompression>

Instructs to put files in the installer without compressing them. This
is way faster than using compression, but makes a seven-fold bigger
installer file.

=item B<-packagespath>

A directory containing packaged sources that should go into the
installer.  It is an alternative to the -extractedpath option, the
differences being that this will unpack the sources before putting
them in the installer.

=item B<-outputpath>

The directory where the resulting installer will be put. Defaults to
current directory.

=back

=head1 DESCRIPTION

B<make.pl> Creates a GNUstep development installer.  For this it needs
three kind of soures:

  - The build environment: MSYS/MinGW The sources we want to build:
    make, base, gui, back, ffcall, libobjc, iconv, intl, zlib, jpeg,
    tiff, png.
  - Supporting files, like scripts to build the installer, scripts
    which will be used on the target machine to build the sources,
    documentation.

The installer finds these sources in the path specified by --packagespath.

=head1 SPECIAL CASES

=head2 MSYS/MinGW

=head2 Installer scripts

=cut
