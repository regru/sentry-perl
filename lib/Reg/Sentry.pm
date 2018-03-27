package Reg::Sentry;

=encoding utf8

=head1 NAME

Reg::Sentry

=head1 MAINTAINERS

domain-team

=head1 AUTHORS

Pavel Serikov <serikov@reg.ru>

=cut

our $VERSION = '1.00';
use LWP::UserAgent;
use JSON::XS;
use Sub::Name;
use Carp;

=head1 SYNOPSIS

    my $sentry = Reg::Sentry->new(
        dsn => 'http://public_key:secret_key@example.com/project-id',
        project => 'srs-billing',
        tags => { type => 'autocharge' }
    );
    $sentry->fatal( 'msg' );
    $sentry->error( 'msg' );
    $sentry->warn ( 'msg' );
    $sentry->warning ( 'msg' );
    $sentry->info ( 'msg' );
    $sentry->debug( 'msg' );
    $sentry->error( $error_msg, extra => { var1 => $var1 } );

    All this methods is getting hash with event id as result

=cut

my @LEVELS;
BEGIN {
    @LEVELS = qw( fatal error warning warn info debug );
    no strict 'refs';
    for my $level ( @LEVELS ) {
        *{ __PACKAGE__ . "::$level" } = subname $level => sub { shift->_send( shift, level => $level, @_ ) };
    }
};


=head1 METHODS

=head2 new

    $class->new( %param )

Конструктор. Все параметры необязательны кроме project и dsn.

%param

    dsn        -- 'http://public_key:secret_key@example.com/project-id'

    logger     -- наименование логгирующего механизма/скрипта, например 'FrontOffice', 'BackOffice'.
                  по умолчанию имя скрипта.

    culprit    -- место возникновения ошибки/исключения (метод/функция).
                  Если undef, в качестве culprit будет браться вызывающая отправку события функция.

    tags       -- hash ref строк-тегов:
                    { send_alerts => 'no', type => 'autorenew', ... }.
                  Теги используются в Sentry для категоризации и для настройки алертов.

    extra      -- hash ref дополнительных значений (скаляры):
                    { 'var 1 was' => $var1, 'var 2 was' => $var2 }
                  Эти значения будут отображаться в спец. секции на странице ошибки.
                  Не скаляры будут принудительно Dumperизированы.

    show_stacktrace -- включение stacktrace (может вызывать излишнюю группировку событий)


=cut


my $ua = LWP::UserAgent->new( timeout => 10 );

sub new {
    my ( $class, %params ) = @_;

    confess 'Empty Sentry dsn' unless defined $params{dsn} && length $params{dsn};

    # '{PROTOCOL}://{PUBLIC_KEY}:{SECRET_KEY}@{HOST}{PATH}/{PROJECT_ID}'
    my ( $proto, $pub_key, $rest ) = split /:/, $params{dsn}, 3;
    $pub_key =~ s/['\/']//g; # public_key

    my $url_plus_proj_id = ( split /@/, $rest )[-1];
    $params{auth} = {
        protocol => $proto,
        public_key => $pub_key,
        secret_key => substr( $rest, 0, index($rest, '@') ),
        sentry_uri => substr( $url_plus_proj_id, 0, rindex($url_plus_proj_id, '/') ),
        project_id => (split /\//, $url_plus_proj_id)[-1]
    };

    bless { %params }, $class;
}


sub _generate_auth_header {
    my ($self) = @_;
    my %fields = (
        sentry_version   => 7,
        sentry_client    => "reg-sentry/$VERSION",
        sentry_timestamp => time(),
        sentry_key       => $self->{auth}{public_key},
        sentry_secret    => $self->{auth}{secret_key},
    );
    return 'Sentry ' . join(', ', map { $_ . '=' . $fields{$_} } sort keys %fields);
}


sub _send {
    my ( $self, $message, %param ) = @_;
    $ua->default_header( 'X-Sentry-Auth' => $self->_generate_auth_header() );
    my $api_endpoint = $self->{auth}{protocol}.'://'.$self->{auth}{sentry_uri}.'/api/'.$self->{auth}{project_id}.'/store/';
    my %json = %param;
    $json{message} = $message;
    my $req = HTTP::Request->new( 'POST', $api_endpoint );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( encode_json \%json);
    my $res = $ua->request( $req );
    decode_json ($res->content);
}

1;
