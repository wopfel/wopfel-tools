#!/usr/bin/perl

# Copyright (C) wopfel - https://github.com/wopfel
# Created 2010-09-02
# Released under GPL version 2 or later

# Purpose:
# - Rotate remote storage directories
# - Sync local files to remote storage
# - Twitter end-of-backup message

# Preparation:
# sudo mkdir -p /media/<your_backup_filesystem>/Spiegel_<your_hostname>/{logs,spiegel{1,2,3}}
# (replace <your_backup_filesystem> and <your_hostname>)

use strict;
use warnings;
use File::Copy;
use Sys::Hostname;
use POSIX;
use POSIX qw(strftime);
use Net::Twitter;



my $destsys = "/media";

opendir( my $dh, $destsys ) || die "Cannot open dir";

while ( my $dirname = readdir $dh ) {

    # Skip . and ..
    next if $dirname =~ /\.\.?/;

    # Only directories
    next unless -d "$destsys/$dirname";

    # Subdirectory Spiegel_<hostname>/spiegel1/ must be there
    if ( -e "$destsys/$dirname/Spiegel_" . hostname . "/spiegel1/." ) {
        $destsys .= "/$dirname";
        print "Found directory $destsys.\n";
        last;
    }

}

closedir $dh;

######################

# Failback to /mnt
if ( ! -e "$destsys/Spiegel_" . hostname ) {
    $destsys = "/mnt";
}

my $local_path = "/var/local/my-backuptools";

# Check effective UID
if ( $> != 0 ) {
    die "No root user (ID=$>)";
}

my $dest = "$destsys/Spiegel_" . hostname;
print "Destination: $dest.\n";

my $ymdhms = strftime( '%Y-%m-%d_%H%M%S', localtime );
my $remote_logfile = "$dest/logs/rsync_$ymdhms.log";
print "Remote-Logfile: $remote_logfile.\n";

my $local_logfile = "$local_path/lastlog";
print "Local-Logfile: $local_logfile.\n";

###

if ( ! -e "$dest/spiegel1/." ) {
    die "Falscher Mount Ziel? Verz. spiegel1 fehlt. Abbruch!";
}

if ( ! -e "$dest/." ) {
    die "Falscher Mount Ziel? Abbruch!";
}

# Rotation
move "$dest/spiegel3",        "$dest/spiegel_aktuell";
move "$dest/spiegel2",        "$dest/spiegel3";
move "$dest/spiegel1",        "$dest/spiegel2";
move "$dest/spiegel_aktuell", "$dest/spiegel1";

# Immer nach spiegel1 schreiben
$dest = "$dest/spiegel1";


######################################################

print "Starting copy processes... ";
print scalar localtime;
print " [" . time . "]";
print ".\n";

my %rsyncs = ( 
               "/home" => "--delete-excluded --exclude='/home/*/.gvfs' --exclude='/home/*/.local/share/Trash' " .
                          "--exclude='/home/*/.thumbnails' --exclude='/home/*/.mozilla/firefox/*.default/Cache/'",
               "/etc"  => "",
               "/boot" => "",
               "/var"  => "",
               "/usr"  => "",
               "/root" => "",
             );

foreach ( sort keys %rsyncs ) {

    print "Rsync $_...";

    my $cmd = "rsync --stats --delete -avv ";
    $cmd .= "--link-dest='../spiegel2' ";
    $cmd .= "$rsyncs{$_} "  if $rsyncs{$_};
    $cmd .= "$_ '$dest/' ";
    $cmd .= ">> $remote_logfile 2>&1";

    #print "Command: $cmd ";

    system $cmd;

    print " Returncode: $? - ";
    print scalar localtime;
    print " [" . time . "]";
    print ".\n";

}


###############################


my %other_cmds = (
                   "Dpkg"       => "dpkg -l > '$dest/_Dpkg-Liste.txt'",
                   "MBR"        => "dd if=/dev/sda of='$dest/_MBR-sda' bs=512 count=1 >> $remote_logfile 2>&1",
                   "Partitions" => "( sfdisk -d && echo '---' && fdisk -l && echo '---' && fdisk -lu ) > '$dest/_Partitionsliste.txt' 2>&1",
                   "Lshw"       => "lshw > '$dest/_Lshw.txt' 2>&1",
                   "LvmDump"    => "lvmdump -a -d '$dest/lvmdump' 2>&1",
                   "DmiDecode"  => "dmidecode > '$dest/_DmiDecode.txt' 2>&1",
                 );

system( "rm -rf -- '$dest/lvmdump'" );

foreach ( keys %other_cmds ) {

    print "$_...";

    my $cmd = $other_cmds{$_};

    system( $cmd );

    print " Returncode: $? - ";
    print scalar localtime;
    print " [" . time . "]";
    print ".\n";

}


###############################

unlink                          "$local_path/lastlog.7";
move "$local_path/lastlog.6",   "$local_path/lastlog.7";
move "$local_path/lastlog.5",   "$local_path/lastlog.6";
move "$local_path/lastlog.4",   "$local_path/lastlog.5";
move "$local_path/lastlog.3",   "$local_path/lastlog.4";
move "$local_path/lastlog.2",   "$local_path/lastlog.3";
move "$local_path/lastlog.1",   "$local_path/lastlog.2";
move $local_logfile,            "$local_path/lastlog.1";

copy $remote_logfile, $local_logfile;

###############################

open LASTRUN, ">", "$dest/../lastrun";
print LASTRUN "$0 -- Logfile=$local_logfile - ";
print LASTRUN scalar localtime;
print LASTRUN " [" . time . "].\n";
close LASTRUN;

###############################

unlink                          "$local_path/lastrun.7";
move "$local_path/lastrun.6",   "$local_path/lastrun.7";
move "$local_path/lastrun.5",   "$local_path/lastrun.6";
move "$local_path/lastrun.4",   "$local_path/lastrun.5";
move "$local_path/lastrun.3",   "$local_path/lastrun.4";
move "$local_path/lastrun.2",   "$local_path/lastrun.3";
move "$local_path/lastrun.1",   "$local_path/lastrun.2";
move "$local_path/lastrun",     "$local_path/lastrun.1";

open LASTRUN, ">", "$local_path/lastrun";
print LASTRUN "# LASTRUN INFO
Script: $0.
Date and time: $ymdhms.
Timestamp: " . time . ".
Destination: $dest.
Remote-Logfile: $remote_logfile.
Local-Logfile: $local_logfile.
";
close LASTRUN;

###############################

my $nt = Net::Twitter->new(
                           traits              => [qw/API::REST OAuth/],
                           ssl                 => 1,
                           consumer_key        => '***********',
                           consumer_secret     => '***********',
                           access_token        => '***********',
                           access_token_secret => '***********',
);


my $message = "Backup ended, sys=" . hostname . " dest=$destsys -- ";
$message .= strftime "%Y-%m-%d %H:%M:%S UTC", gmtime;

print "Sending this message to twitter:\n$message\n";

$nt->update( $message );

###############################

exit 0;

