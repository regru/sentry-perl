# ABSTRACT: Yet another lightweight Sentry client

package WWW::Sentry;

=encoding utf8

=head1 NAME

WWW::Sentry

=head1 DESCRIPTION

Module for sending messages to Sentry, open-source cross-platform crash reporting and aggregation platform.

Implements Sentry reporting API https://docs.sentry.io/clientdev/

=head1 SYNOPSIS

    my $sentry = Reg::Sentry->new( $dsn, tags => { type => 'autocharge' } );

    $sentry->fatal( 'msg' );
    $sentry->error( 'msg' );
    $sentry->warn ( 'msg' );
    $sentry->warning ( 'msg' );  # alias to warn
    $sentry->info ( 'msg' );
    $sentry->debug( 'msg' );

    $sentry->error( $error_msg, extra => { var1 => $var1 }, read_sources );

    All this methods return event id as result or die with error

    %params:
        message*  -- error message
        event_id  -- message id (by default it's random)
        level     -- 'fatal', 'error', 'warning', 'info', 'debug' ('error' by default)
        logger    -- the name of the logger which created the record, e.g 'sentry.errors'
        platform  -- A string representing the platform the SDK is submitting from. E.g. 'python'
        culprit   -- The name of the transaction (or culprit) which caused this exception. For example, in a web app, this might be the route name: /welcome/
        tags      -- tags for this event (could be array or hash )
        server_name -- host from which the event was recorded
        modules   -- a list of relevant modules and their versions
        environment -- environment name, such as ‘production’ or ‘staging’.
        extra     -- hash ref of additional data. Non scalar values are Dumperized forcely

        context_lines_ -- integer. reads source file and add to stacktrace specified amount of code lines around place where error occured.
        0 by default (do not read source file)

    * - required params

    Attributes from other Sentry Interfaces could be also provided as %params, e.g.

        stacktrace -- array ref  or string
        context_lines -- how much lines from source code will be added
        user       -- hash ref user info


See also

https://docs.sentry.io/clientdev/overview/#building-the-json-packet
https://docs.sentry.io/clientdev/attributes/
https://docs.sentry.io/clientdev/interfaces/




=cut

use LWP::UserAgent;
use MIME::Base64 'encode_base64';
use Sys::Hostname;
use Data::Dump qw( pp );
use utf8;
use POSIX;
use JSON::XS;
use Sub::Name;
use Carp;

my @LEVELS;
BEGIN {
    @LEVELS = qw( fatal error warning warn info debug );
    no strict 'refs';
    for my $level ( @LEVELS ) {
        *{ __PACKAGE__ . "::$level" } = subname $level => sub { shift->_send( message => shift, level => $level, @_ ) };
    }
};


=head4 new

Constructor

    my $sentry = Reg::Sentry->new(
        'http://public_key:secret_key@example.com/project-id',
        sentry_version    => 5 # can be omitted
    );

See also

https://docs.sentry.io/clientdev/overview/#parsing-the-dsn



=cut

sub new {
    my ( $class, $dsn, %params ) = @_;

    die 'API key is not defined' unless $dsn;

    my $self = {
        ua => LWP::UserAgent->new( timeout => 10 ),
        %params,
    };

    $self->{sentry_version} ||= 5;

    ( my $protocol, $self->{public_key}, $self->{secret_key}, my $host_path, my $project_id )
        = $dsn =~ m{^ ( https? ) :// ( \w+ ) : ( \w+ ) @ ( .+ ) / ( \d+ ) $}ixaa;

    die 'Wrong dsn format'
        if grep { !defined $_ || !length $_ }
            ( $protocol, $self->{public_key}, $self->{secret_key}, $host_path, $project_id );

    $self->{uri} = "$protocol://$host_path/api/$project_id/store/";

    bless $self, $class;
}

=head4 _send

Send a message to Sentry server.
Returns the id of inserted message or dies.



=cut

sub _send {
    my ( $self, %params ) = @_;

    my $auth = sprintf
        'Sentry sentry_version=%s, sentry_timestamp=%s, sentry_key=%s, sentry_client=%s, sentry_secret=%s',
        $self->{sentry_version},
        time(),
        $self->{public_key},
        __PACKAGE__,
        $self->{secret_key},
    ;

    my $message = $self->_build_message( %params );
    $message = encode_json $message;
    my $response = $self->{ua}->post(
        $self->{uri},
        'X-Sentry-Auth' => $auth,
        'Content-Type' => 'application/octet-stream',
        Content => encode_base64( $message ),
    );

    unless ( $response->is_success ) {
        if ( int( $response->code / 100 ) == 4 ) {
            die $response->status_line . ': ' . $response->decoded_content;
        }

        die $response->status_line;
    }

    my $answer_ref = decode_json $response->decoded_content;

    die 'Wrong answer format' unless $answer_ref && $answer_ref->{id};

    return $answer_ref->{id};
}


sub _build_message {
    my ( $self, %params ) = @_;

    die 'No message given' unless defined $params{message} && length $params{message};

    my $data_ref = {
        message     => $params{message    },
        timestamp   => strftime( '%FT%X.000000Z', gmtime time ),
        level       => $params{level      } || $self->{level} || 'info',
        logger      => $params{logger     },
        platform    => $params{platform   } || 'perl',
        culprit     => $params{culprit    } || '',
        tags        => $params{tags       } || $self->{tags} || {},
        server_name => $params{server_name} || hostname(),
        modules     => $params{modules    },
        extra       => $params{extra      } || {},
        request     => $params{request    } || {},
        user        => $params{user       } || {},
    };

    if ( $params{stacktrace} ) {
        # Make frames
        # # https://docs.sentry.io/clientdev/interfaces/stacktrace/
        if ( !ref $params{stacktrace} ) {
            # stacktrace as string
            # was $data_ref->{extra}{stacktrace} = $params{stacktrace} , why ?
            $data_ref->{stacktrace} = $params{stacktrace};
        }
        elsif ( ref $params{stacktrace} eq 'ARRAY' ) {
            # Сonverting stacktrace to Sentry format

            # Read strings from sources
            for my $frame_ref ( @{ $params{stacktrace} // [] } ) {

                if ($self->{context_lines}) {
                    my %context = eval { _get_context_lines( $frame_ref->{abs_path}, $frame_ref->{lineno}, $self->{context_lines} ) };
                }

                if ( $@ ) {
                    %context = ();
                }

                @$frame_ref{ keys %context } = values %context;
            }

            $data_ref->{stacktrace} = { frames => $params{stacktrace} };
        }
    }

    my $extra_ref = $data_ref->{extra};

    # Dump non scalars to extra
    $extra_ref->{ $_ } = pp( $extra_ref->{ $_ } )
        for grep { ref $extra_ref->{ $_ } } keys %$extra_ref;

    return $data_ref;
}

# getting code strings from sources
sub _get_context_lines {
    my ( $package, $line, $pre_post_cnt ) = @_;

    $package =~ s{^lib/}{};

    return  unless $line && $package && $package =~ m{^/};

    --$line; # 0 indexed

    my $content = _read_source_file( $package ) or return;

    my @lines = split "\n", $content;

    my $first = max( $line - $pre_post_cnt, 0       );
    my $last  = min( $line + $pre_post_cnt, $#lines );

    my $context_line = $lines[ $line ];
    my @pre  = @lines[ $first .. $line - 1 ];
    my @post = @lines[ $line + 1 .. $last  ];

    $_ = substr $_, 0, 255  for $context_line, @pre, @post;

    return (
        context_line => $context_line,
        post_context => \@post,
        pre_context  => \@pre,
    );
}

# Read content from source file and return in internal encoding
# Assumes that sources are in utf8 encoding
sub _read_source_file {
    my ( $file ) = @_;

    return  unless open my $src, '<', $file;
    my $content;
    {
        local $/ = undef;
        $content = <$src>;
    }
    close $src;

    return utf8::decode($content);
}


1;
