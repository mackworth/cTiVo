#!/usr/bin/perl

#  elgatoScript.pl
#  cTiVo
#
#  Created by Hugh Mackworth on 2/11/13.
#  Copyright (c) 2013 Hugh Mackworth. All rights reserved.
use warnings;
use strict;
use File::Spec;
use File::BaseName;


if ($#ARGV < 0) {
	@ARGV = ( "AppleTV",  "-i", "/tmp/ctivo/test.mpg", "test.mp4"); #"-edl", "test.tivo.edl",
}
use Cwd();
foreach (@ARGV) {
	print $_ . "\n";
}
my $programPath = Cwd::abs_path($0);
my ($volume, $directory, $fileName) = File::Spec->splitpath($programPath);
my $program_dir= $volume . $directory;

my $turboAppName = "";
local $SIG{'INT' } = \&cleanAndExit;  local $SIG{'QUIT'} = \&cleanAndExit;
local $SIG{'HUP' } = \&cleanAndExit;  local $SIG{'TRAP'} = \&cleanAndExit;
local $SIG{'ABRT'} = \&cleanAndExit;  local $SIG{'STOP'} = \&cleanAndExit;
use sigtrap 'handler' => \&cleanAndExit, 'normal-signals';

my $launchElgato = "/usr/bin/osascript \"" . $program_dir. "elgatoLaunch.scpt\" \"" . join ('" "', @ARGV) ."\"";
print $launchElgato ."\n1%\n";  #signal start, while turbo still launching

my $counter = 2;
my $launchResponse = "";
while (1) {
	$launchResponse = `$launchElgato`;
	chop($launchResponse);  #delete return
	last if ($launchResponse ne "1");
		#waiting for another encoding to finish, but need to check in
	print $counter ."%\n";
	$counter = $counter+1;
	$counter = 1 if ($counter >= 100);
		
}

print $launchResponse ."\n";

if ($launchResponse =~ /Not Found/) {
	print "turbo HD encoder not available"."\n";
	exit 1;

}
$turboAppName = $launchResponse;   #launch is required to send back turbo's app Name
print $turboAppName . "\n";
my $checkElgato = "/usr/bin/osascript \"" . $program_dir. "elgatoProgress.scpt\" \"$launchResponse\"";
print $checkElgato ."\n" . $counter ."%\n";  #signal start, while turbo still launching

while (1) {
	my $progressResponse =`$checkElgato`;
	chop($progressResponse); #delete return
	last if $progressResponse eq "0";
	print $counter ."%\n";
	$counter = ($counter + 1);
	$counter = 1 if ($counter >= 100);
}

# close all file handles and do any other clean up
# this method will be called if the followng signals are given to your pid # kill -INT
# kill -ABRT
# kill -QUIT
# kill -TERM
sub cleanAndExit(){
	my $signame = shift;
	print "Due to signal SIG$signame\n";
	if ($turboAppName ne "") {
		print "Terminating encoder, cleaning up and exiting\n";
		my $killElgato = "/usr/bin/osascript \"" . $program_dir. "elgatoQuit.scpt\" \"" . $turboAppName ."\"";
		print $killElgato ."\n";
		print `$killElgato`
	}
	exit(1);
}

