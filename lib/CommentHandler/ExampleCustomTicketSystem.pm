package CommentHandler::ExampleCustomTicketSystem;
use strict;
use warnings;

use DBI;
use CommentHandler::Configuration;

sub new {
    my $conf = CommentHandler::Configuration->new( 'ExampleCustomTicketSystem' );
    my $self = {
        'regex'    => q{^\s*(?<=https:\/\/ticketdesk\.example\.com\/staff\/ticket/)([[:digit:]]+)\s*$},
        'resolved' => [],
        'open'     => [],
        'cache'    => {
            'open'    => [],
            'updated' => 0,
            'timeout' => 60, # in seconds
        },
        'db'       => {
            'db'    => $conf->{'db'}    // 'tickets',
            'host'  => $conf->{'host'}  // 'localhost',
            'port'  => $conf->{'port'}  // 3306,
            'user'  => $conf->{'user'}  // 'commenthandler',
            'pass'  => $conf->{'pass'}  // 'some fine pass we are in now',
            'query' => $conf->{'query'} // q{select ticketid from support where status = 'open' and type = 'sysadmin';},
        },
        'dbh'      => undef,
        'sth'      => undef,
    };

    bless $self, shift;

    $self->connect();
    return $self;
}

sub regex {
    my $self = shift;
    return $self->{'regex'};
}

sub claim_cases {
    my ( $self, @issues ) = @_;
    my $regex = $self->{'regex'};

    @issues = map { my $f = $_; $f =~ s/^\s+|\s+$//g; $_ = $f } @issues;
    @issues = map { my $f = $_; $f =~ s{https://ticketdesk\.example\.com/staff/ticket/\?}{}; $_ = $f } @issues;
    my @my_issues = grep { m/$regex/ } @issues;

    if ( ( $self->{'cache'}{'timeout'} + time() ) > $self->{'cache'}{'updated'} ) {
        $self->update_open();
    }

    my %open = map { $_ => 1 } @{ $self->{'cache'}{'open'} };

    if ( defined $self->{'dbh'} ) {
        @{$self->{'resolved'}} = grep { ! exists $open{$_} } @my_issues;
        @{$self->{'open'}} = grep { exists $open{$_} } @my_issues;
    } else {
        # fail safe
        @{$self->{'resolved'}} = [];
    }
    return $self;
}

sub list_resolved {
    my $self = shift;
    return @{$self->{'resolved'}}
}

sub list_open {
    my $self = shift;

    return @{ $self->{'open'} };
}

sub update_open {
    my $self = shift;
    my $trying = 1;
    my $attempts = 3;
    while ( $trying ) {
        local $@;
        eval {
            $self->connect;
            $self->{'sth'}->execute();
            @{ $self->{'cache'}{'open'} } = map { $_->[0] } @{ $self->{'sth'}->fetchall_arrayref([0]) };
            $self->{'cache'}{'updated'} = time();
        };
        if ( $@ ) {
            die $@ if $trying > $attempts;
            sleep $trying;
            $trying++;
        } else {
            $trying = 0;
        }
    }
    return $self;
}

sub connect {
    my $self = shift;
    if ( ! ( $self->{'dbh'} && $self->{'dbh'}->ping ) ) {
        my %attr = (
            'RaiseError'           => 1,
        );
        if ( 'SCALAR' eq ref $self->{'db'}{'host'} ) {
            # promote to array
            $self->{'db'}{'host'} = [ $self->{'db'}{'host'} ];
        }
        for my $host ( @{ $self->{'db'}{'host'} } ) {
            local $@;

            eval {
                my $dsn = sprintf 'DBI:mysql:database=%s;host=%s;port=%s;', $self->{'db'}{'db'}, $host, $self->{'db'}{'port'};
                $self->{'dbh'} = DBI->connect_cached( $dsn, $self->{'db'}{'user'}, $self->{'db'}{'pass'}, \%attr ) or die  $DBI::errstr;
                $self->{'sth'} = $self->{'dbh'}->prepare( $self->{'db'}{'query'} );
            };
            if ( $@ ) {
                print STDERR "database connection error: " . $@ . "\n" . $DBI::errstr . "\n";
        exit 1;
            } else {
                last;
            }
            sleep 1;
        }
    }
    return $self;
}

1;
__END__

