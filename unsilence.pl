#!/usr/bin/perl
use strict;
use warnings;

if ( @ARGV && $ARGV[0] =~ /^--?h(?:elp)?/i ) {
    warn "
USAGE:
    unsilence.pl [file]

  takes a list of servers, one per line, in one or more files or on STDIN.
  Then it tells Nagios to enable host and service checks and host and service notifications for all of those servers.

";
    exit;
}
 
my $time = time();
open my $cmd, '>>', '/var/spool/nagios/nagios.cmd' or die "$!\n";

while ( <> ) {
    my $host = $_;
    my $string = sprintf '[%u] ENABLE_HOST_CHECK;%s%s[%u] ENABLE_HOST_SVC_CHECKS;%s%s',
        $time, $host, "\n", $time, $host, "\n";
    print {$cmd} $string;
    $string = sprintf '[%u] ENABLE_HOST_NOTIFICATIONS;%s%s[%u] ENABLE_HOST_SVC_NOTIFICATIONS;%s%s',
        $time, $host, "\n", $time, $host, "\n";
    print {$cmd} $string;
}
close $cmd or die "$!\n";

