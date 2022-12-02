package CommentHandler::Jira;
use strict;
use warnings;

use JSON;
use LWP::UserAgent;
use CommentHandler::Configuration;

sub new {
    my ( $class, $host, $user, $pass, @projects ) = @_;
    my $cfg = CommentHandler::Configuration->new( 'Jira' );
    my $self = {
        'host'     => $host || $cfg->{'host'} || 'localhost',
        'user'     => $user || $cfg->{'user'} || 'commenthandler',
        'pass'     => $pass || $cfg->{'pass'} || 'commenthandler',
        'path'     => '/rest/api/2/issue/%s?fields=resolution',
        'projects' => ( scalar @projects ? \@projects : $cfg->{'projects'} || [ 'BOFH', 'SRE', 'DESKTOP', 'NETWORK', 'SYSADMIN' ] ),
        'issues'   => {},
    };
    $self->{'regex'} = '(?:' . (join '|', @{$self->{'projects'}}) . ')-[[:digit:]]+';
    bless $self, $class;
    return $self;
}

sub regex {
    my $self = shift;
    return $self->{'regex'};
}

sub claim_cases {
    my ( $self, @issues ) = @_;
    my $regex = $self->{'regex'};
    for my $i ( @issues ) {
        $self->is_resolved( $i ) if ( $i =~ m/$regex/ );
    }
    return $self;
}

sub is_resolved {
    my ( $self, $issue ) = @_;
    if ( ! exists $self->{'issues'}{$issue} ) {
        my $path = sprintf $self->{'path'}, $issue;
        my ( $un, $pw ) = ( URI::Escape::uri_escape( $self->{'user'} ), URI::Escape::uri_escape( $self->{'pass'} ) );
        my $url = sprintf 'https://%s:%s@%s%s', $un, $pw, $self->{'host'}, $path;
        my $ua = LWP::UserAgent->new();
        my $response = $ua->get( $url );

        if ( $response->is_success ) {
            my $data = decode_json $response->content;
            $self->{'issues'}{$issue} = !! (
                ( exists $data->{'fields'}{'resolution'}{'name'} )
                &&
                ( defined $data->{'fields'}{'resolution'}{'name'} )
            );
        } else {
            print STDERR "couldn't get a successful response from $path on " . $self->{'host'} . ": " . $response->code . ":: " . $response->message . "::: " . $response->content . "\n";
        }
    }
    return $self->{'issues'}{$issue};
}

sub list_resolved {
    my $self = shift;
    return grep { $self->{'issues'}{$_} } keys %{ $self->{'issues'} };
}

sub list_open {
    my $self = shift;
    return grep { !  $self->{'issues'}{$_} } keys %{ $self->{'issues'} };
}

1;
__END__

