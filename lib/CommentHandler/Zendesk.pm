#
# get a ticket JSON object:
# GET /api/v2/tickets/{ticket_id}.json
#
# curl https://{subdomain}.zendesk.com/api/v2/tickets/{ticket_id}.json \
#  -v -u {email_address}:{password}
#
#
# example agent view:
# https://exampledesk.zendesk.com/agent/tickets/123
#
# example alternate issue view:
# https://helpdesk.example.com/hc/en-us/requests/333
#

package CommentHandler::Zendesk;
use strict;
use warnings;

use JSON;
use LWP::UserAgent;
use CommentHandler::Configuration;


sub new {
    my ( $class, $host, $user, $pass ) = @_;
    my $cfg = CommentHandler::Configuration->new( 'Zendesk' );
    my $self = {
        'host'     => $host || $cfg->{'host'} || 'localhost',
        'user'     => $user || $cfg->{'user'} || 'commenthandler',
        'pass'     => $pass || $cfg->{'pass'} || 'commenthandler',
        'path'     => '/api/v2/tickets/%s.json',
        'issues'   => {},
    };
    $self->{'regex'} = '(?:https://(?:exampledesk.zendesk.com/(?:agent|api/v2)/tickets/|helpdesk.example.com/hc/[^/]+/requests/)(\d+)(?:\.json)?)';
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
        my $regex = $self->regex();
        if ( $issue =~ m/$regex/ ) {
            my $issue_number = $1;
            my $path = sprintf $self->{'path'}, $issue_number;
            my ( $un, $pw ) = ( URI::Escape::uri_escape( $self->{'user'} ), URI::Escape::uri_escape( $self->{'pass'} ) );
            my $url = sprintf 'https://%s%%2Ftoken:%s@%s%s', $un, $pw, $self->{'host'}, $path;
            my $ua = LWP::UserAgent->new();
            my $response = $ua->get( $url );

            if ( $response->is_success ) {
                my $data = decode_json $response->content;
                if ( exists $data->{'ticket'}{'status'} ) {
                    $self->{'issues'}{$issue} = ($data->{'ticket'}{'status'} =~ m/^(?:closed|solved)$/);
                } else {
                    print STDERR "found the ticket $issue but could not find a status field for it.\n";
                }
            } else {
                print STDERR "couldn't get a successful response from $path on " . $self->{'host'} . ": " . $response->code . ":: " . $response->message . "::: " . $response->content . "\n";
            }
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

