package CommentHandler::Configuration;
use strict;
use warnings;

use JSON;

my $homedir = ( getpwuid( $< ) )[ 7 ];
my $global_config_dir = '/etc/comment-handler';
my $user_config_dir   = sprintf '%s/.comment-handler', $homedir;

sub new {
    my ( $class, $file ) = @_;
    my $user_file = sprintf '%s/%s', $user_config_dir, $file;
    my $global_file = sprintf '%s/%s', $global_config_dir, $file;
    my $self = get_config( $user_file ) || get_config( $global_file ) || default_config( $file );
    bless $self, $class;
    return $self;
}

sub get_config {
    my $error = '';
    my $result = 0;
    my $fh;
    my @queue = (
        [ sub { -e $_[0] }, sub { sprintf '%s does not exist. %s', $_[0], $! } ],
        [ sub { -r $_[0] }, sub { sprintf '%s cannot be read. %s', $_[0], $! } ],
        [
            sub { open $fh, '<', $_[0] },
            sub { sprintf '<%s> cannot be opened for reading. %s', $_[0], $! },
        ],
    [ sub { local $/; my $j = <$fh>; chomp $j; return from_json( $j ) }, sub { sprintf 'error while reading %s', $_[0] }, ],
    );
    for my $work ( @queue ) {
    $result = $work->[0]( $_[0] );
    $error = $work->[1]( $_[0] ) if ! $result;
        last if $error;
    }
    my $basename = ($_[0] =~ m{.*/([^/]+)$})[0];
    ( $result, $error ) = check_config( $result, $basename );
    return wantarray ? ( $result, $error ) : $result;
}

sub default_config {
    my $section = shift;
    my %main = (
        'config'              => 'main',
        'comment_plugins'     => {
            'reader' => 'NagiosStatusReader',
            'writer' => 'NagiosCommands',
        },
        'case_status_plugins' => {
            'Jira'    => 1,
            'Zendesk' => 1,
        }
    );

    my %NagiosStatusReader = (
        'config' => 'NagiosStatusReader',
        'proto'  => 'fileread',
        'path'   => '/var/log/nagios/status.dat',
    );
    my %NagiosScraper = (
        'config' => 'NagiosScraper',
        'proto'  => 'https',
        'host'   => 'localhost',
        'path'   => '/nagios/cgi-bin/extinfo.cgi?type=3',
        'user'   => 'commenthandler',
        'pass'   => 'some pass you might never pineapple',
    );
    my %NagiosCommands = (
        'config' => 'NagiosCommands',
        'proto'  => 'pipewrite',
        'path'   => '/var/spool/nagios/nagios.cmd',
    );
    my %ExampleCustomTicketSystem = (
        'config'  => 'ExampleCustomTicketSystem',
        'proto'   => 'mysql',
        'db'      => 'tickets',
        'query'   => q{select id from tickets where status = 'open' and type = 'bofh';},
        'host'    => 'localhost',
        'user'    => 'commenthandler',
        'pass'    => 'some pass you might never pineapple',
    );
    my %Jira = (
        'config'   => 'Jira',
        'proto'    => 'https',
        'host'     => 'jira',
        'user'     => 'commenthandler',
        'pass'     => 'some pass you might never pineapple',
        'projects' => [ 'JIRA' ],
    );
    my %Zendesk = (
        'config' => 'Zendesk',
        'proto'  => 'https',
        'host'   => 'examplehelpdesk.zendesk.com',
        'user'   => 'zendesk-user@example.com',
        'pass'   => 'API-KEY-GOES-HERE',
    );

    my %available = (
        'main'                  => \%main,
        'NagiosScraper'         => \%NagiosScraper,
        'NagiosStatusReader'    => \%NagiosStatusReader,
        'NagiosCommands'        => \%NagiosCommands,
#        'ExampleCustomTicketSystem' => \%ExampleCustomTicketSystem,
        'Jira'                  => \%Jira,
        'Zendesk'               => \%Zendesk,
    );

    return (exists $available{ $section } ? $available{ $section } : undef );
}

sub check_config {
    my ( $config, $section ) = @_;
    my @errors = ();
    my $error_string = undef;

    my %check = ( 'path' => 1, 'host' => 2, 'user' => 4, 'pass' => 8, 'query' => 16, 'table' => 32, 'projects' => 64);
    my %protocol_needs = (
        'custom'    => 0,
        'fileread'  => $check{'path'},
        'pipewrite' => $check{'path'},
        'https'     => $check{'host'},
        'mysql'     => $check{'host'}|$check{'user'}|$check{'pass'},
    );
    my %protocol_accepts = (
        'custom'    => 0,
        'fileread'  => $check{'path'},
        'pipewrite' => $check{'path'},
        'https'     => $check{'path'}|$check{'host'}|$check{'user'}|$check{'pass'}|$check{'query'}|$check{'projects'},
        'mysql'     => $check{'host'}|$check{'user'}|$check{'pass'}|$check{'table'}|$check{'query'}|$check{'projects'},
    );


    'HASH' eq ref $config or push @errors, 'The configuration object should be a hash (JSON object in a config file).';
    if( exists $config->{'config'} ){
        push @errors, (
            $section eq $config->{'config'} ? () :
            sprintf 'The configuration section requested for %s reports it is for %s.', $section, $config->{'config'}
        )
    } else {
        push @errors, 'The configuration does not have a "config" label to identify it.';
    }
    if ( $section ne 'main' ) {
        exists $config->{'proto'} or push @errors, 'Every config section other than "main" needs a protocol (for example pipewrite, https, mysql).';
    }

    if ( exists $config->{'config_checker'} && ( $config->{'config_checker'} ne 'standard' ) ) {
        # The plugin should check its config in its constructor (and be set to custom protocol), use the standard checker,
        # or give us a config checker method to test the rest of its configuration.
        eval {
            my $module = sprintf 'CommentHandler/%s.pm', $section;
            require $module;
            my $class = sprintf 'CommentHandler::%s', $section;
            my $checker = $config->{'config_checker'};
            ( $config, $error_string ) = $class->$checker( $config );
        };
        if ( $@ ) {
            $config = {};
            push @errors, ( sprintf 'While using the custom config checker for %s, the following happened.: %s', $section, $@ );
        }
    } else {
        # For the core protocols we know about for plugins that don't check their own config, check what config values they need and accept.
        # Plugins may accept more.
        # If they specify a core protocol type but demand/need more than specified they should check for themselves.
        # If they accept fewer config variables than here for a known protocol type, they should check for themselves.
        # In general, it's best to specify "custom" for the protocol if it doesn't match the protocol you were thinking of, or do a PR.
        if ( exists $config->{'proto'} && exists $protocol_needs{ $config->{'proto'} } ) {
            # for each thing we really care about checking
            foreach my $c ( keys %check ) {
                # check the bitmask to see if it's needed
                if ( $protocol_needs{ $config->{'proto'} } & $check{$c} ) {
                    exists $config->{$c} or push @errors, ( sprintf 'Protocol %s needs a value for "%s".', $config->{'proto'}, $c );
                }
                # check to make sure we don't have extra config values the plugin cannot make sense of
                if ( ! ( $protocol_accepts{ $config->{'proto'} } & $check{$c} ) ) {
                    if ( exists $config->{$c} ) {
                        push @errors, (
                            sprintf 'Protocol %s cannot make sense of value "%s" and the plugin will not accept it.',  $config->{'proto'}, $c
                        );
                    }
                }
            }
        }

    }

    $config = undef if scalar @errors;

    return wantarray ? ( $config, $error_string ) : $config;
}

1;
__END__

