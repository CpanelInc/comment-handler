#!/usr/bin/perl
package CommentHandler;
use strict;
use warnings;

use lib qw( lib ../lib );
use CommentHandler::Configuration;

main() unless caller();
exit;

sub new {
    my $class = shift;
    my $self = {
        'reader'      => undef,
        'writer'      => undef,
        'case_status' => [],
        'cases'       => [],
        'regex'       => '',
        'resolved'    => [],
        'open'        => [],
    };
    return bless $self, $class;
}

sub main {
    my $ch = CommentHandler->new();
    $ch->load_plugins();
    $ch->reader->read( $ch->regex() );
    for my $r ( $ch->resolved_cases() ) {
        $ch->writer->delete_downtime( $_, 'HOST' ) for $ch->reader->host_downtimes_for_case( $r );
        $ch->writer->delete_downtime( $_, 'SVC' ) for $ch->reader->service_downtimes_for_case( $r );
        $ch->writer->delete_comment( $_, 'HOST' ) for $ch->reader->host_comments_for_case( $r );
        $ch->writer->delete_comment( $_, 'SVC' ) for $ch->reader->service_comments_for_case( $r );
        for my $h ( $ch->reader->hostnames_for_case( $r ) ) {
            $ch->writer->enable_check( $h );
            $ch->writer->enable_notification( $h );
        }
        for my $hs ( $ch->reader->host_and_service_pairs_for_case( $r ) ) {
            $ch->writer->enable_check( @{ $hs } );
            $ch->writer->enable_notification( @{ $hs } );
        }
    }
    for my $o ( $ch->open_cases() ) {
        # this one is for full-host silencing
        $ch->writer->disable_notification( $_ ) for $ch->reader->hostnames_for_case( $o );

        # this is for silencing services
        for my $hs ( $ch->reader->host_and_service_pairs_for_case( $o ) ) {
            $ch->writer->disable_notification( @{ $hs } );
        }
    }
}

sub reader {
    my $self = shift;
    return $self->{'reader'};
}

sub writer {
    my $self = shift;
    return $self->{'writer'};
}

sub resolved_cases {
    my $self = shift;

    for my $cspi ( @{ $self->{'case_status'} } ) {
        push @{ $self->{'resolved'} }, $cspi->claim_cases(
            $self->reader->case_ids()
        )->list_resolved();
    }
    return @{ $self->{'resolved'} };
}

sub open_cases {
    my $self = shift;
    for my $cspi ( @{ $self->{'case_status'} } ) {
        push @{ $self->{'open'} }, $cspi->claim_cases(
            $self->reader->case_ids()
        )->list_open();
    }
    return @{ $self->{'open'} };
}

sub regex {
    my $self = shift;
    if ( ! $self->{'regex'} ) {
        my @parts;
        for my $cspi ( @{ $self->{'case_status'} } ) {
            push @parts, $cspi->{'regex'};
        }
        $self->{'regex'} = sprintf '(?:%s)', join '|', @parts;
    }
    return $self->{'regex'};
}

sub load_plugins {
    my $self = shift;
    my $config = CommentHandler::Configuration->new( 'main' );
    my %plugins = (
        'comment_reader' => $config->{'comment_plugins'}{'reader'},
        'comment_writer' => $config->{'comment_plugins'}{'writer'},
        'case_plugins'   => [ grep { !! $config->{'case_status_plugins'}{$_} } keys %{ $config->{'case_status_plugins'} } ],
    );
    for my $type ( 'reader', 'writer' ) {
        eval {
            my $module = (sprintf 'CommentHandler/%s.pm', $plugins{'comment_'.$type});
            require $module;
            my $new = sprintf 'CommentHandler::%s', $plugins{'comment_'.$type};
            $self->{$type} = $new->new();
        };
        if ( $@ ) {
            die sprintf 'Error loading plugin %s of type %s : %s', $plugins{'comment_'.$type}, 'comment_'.$type, "\n$@\n";
        }
    }
    for my $sp ( @{ $plugins{'case_plugins'} } ) {
        eval {
            my $module = (sprintf 'CommentHandler/%s.pm', $sp);
            require $module;
            my $mod = sprintf 'CommentHandler::%s', $sp;
            push @{ $self->{'case_status'} }, $mod->new();
        };
        if ( $@ ) {
            die sprintf 'Error loading plugin %s of type %s : %s', $sp, 'case_status_plugin', "\n$@\n";
        }
    }

}

1;
__END__

