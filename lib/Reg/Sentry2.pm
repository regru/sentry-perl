package Reg::Sentry2;

=encoding utf8

=head1 NAME

Отсылает сообщение в сервис интеграции сообщений об ошибках Sentry.

=cut

=head1 SYNOPSIS

    my $sentry = Reg::Sentry->new(
        dsn => 'http://public_key:secret_key@example.com/project-id',
        tags => { type => 'autocharge' }
    );
    $sentry->fatal( 'msg' );
    $sentry->error( 'msg' );
    $sentry->warn ( 'msg' );
    $sentry->warning ( 'msg' );  # alias to warn
    $sentry->info ( 'msg' );
    $sentry->debug( 'msg' );
    $sentry->error( $error_msg, extra => { var1 => $var1 } );

All this methods is getting hash with event id as result


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

Конструктор. Использование

    my $sentry = Reg::Sentry->new(
        'http://public_key:secret_key@example.com/project-id',
        sentry_version    => 5 # can be omitted
    );

=cut

sub new {
    my ( $class, $dsn, %params ) = @_;

    die 'API key is not defined' unless $dsn;

    my $self = {
        ua => LWP::UserAgent->new( timeout => 10 ),
        %params,
    };

    $self->{sentry_version} ||= 5;
    $self->{internal_character_format} ||= 'unicode';

    ( my $protocol, $self->{public_key}, $self->{secret_key}, my $host_path, my $project_id )
        = $dsn =~ m{^ ( https? ) :// ( \w+ ) : ( \w+ ) @ ( .+ ) / ( \d+ ) $}ixaa;

    die 'Wrong dsn format'
        if grep { !defined $_ || !length $_ }
            ( $protocol, $self->{public_key}, $self->{secret_key}, $host_path, $project_id );

    $self->{uri} = "$protocol://$host_path/api/$project_id/store/";

    bless $self, $class;
}

=head4 send

Send a message to Sentry server.
Returns the id of inserted message or dies.

%params:
    message*  -- сообщение (об ошибке)
    event_id  -- id сообщения (по умолчанию случайный)
    level     -- 'fatal', 'error', 'warning', 'info', 'debug' (по умолчанию 'error')
    logger    -- наименование логгирующего модуля/скрипта
    platform  -- платформа
    culprit   -- место возникновения ошибки/исключения
    tags      -- hash ref тегов
    server_name -- сервер
    modules   -- array ref список модулей
    extra     -- hash ref дополнительных значений. Значения не-скаляры принудительно Dumperизируются.
    stacktrace -- array ref  либо строка
    user       -- hash ref инфы о пользователе

См. также http://sentry.readthedocs.org/en/latest/developer/client/index.html#building-the-json-packet

=cut

sub _send {
    my ( $self, %params ) = @_;

    my $auth = sprintf
        'Sentry sentry_version=%s, sentry_timestamp=%s, sentry_key=%s, sentry_client=%s, sentry_secret=%s',
        $self->{sentry_version},
        time(),
        $self->{public_key},
        'perl_client',
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

    my $answer_ref = eval { decode_json $response->decoded_content };
    die $@ if $@;

    die 'Wrong answer format' unless $answer_ref && $answer_ref->{id};

    return $answer_ref->{id};
}

sub _build_message {
    my ( $self, %params ) = @_;

    die 'No message given' unless defined $params{message} && length $params{message};

    my $data_ref = {
        message     => $params{message    },
        timestamp   => strftime( '%FT%X.000000Z', gmtime time ),
        level       => $params{level      },
        logger      => $params{logger     },
        platform    => $params{platform   } || 'perl',
        culprit     => $params{culprit    } || '',
        tags        => $params{tags       } || {},
        server_name => $params{server_name} || hostname(),
        modules     => $params{modules    },
        extra       => $params{extra      } || {},
        request     => $params{request    } || {},
        user        => $params{user       } || {},
    };

    if ( $params{stacktrace} ) {
        if ( !ref $params{stacktrace} ) {
            # Стектрейс передан как строка
            $data_ref->{extra}{stacktrace} = $params{stacktrace};
        }
        elsif ( ref $params{stacktrace} eq 'ARRAY' ) {
            # Стектрейс должен быть в формате Sentry

            # Выдергиваем строки из исходников
            for my $frame_ref ( @{ $params{stacktrace} // [] } ) {
                my %context = eval { _get_context_lines( $frame_ref->{abs_path}, $frame_ref->{lineno}, 5 ) };

                if ( $@ ) {
                    # Случае ошибок с кодировками (например смешение cp1251/utf8 не падаем,
                    # а не показываем исходник)
                    warn $@;
                    %context = ();
                }

                @$frame_ref{ keys %context } = values %context;
            }

            $data_ref->{stacktrace} = { frames => $params{stacktrace} };
        }
    }

    # dumperизируем не скаляры в extra
    my $extra_ref = $data_ref->{extra};

    $extra_ref->{ $_ } = pp( $extra_ref->{ $_ } )
        for grep { ref $extra_ref->{ $_ } } keys %$extra_ref;

    return $data_ref;
}

# Получить строки кода c ошибкой из исходников
sub _get_context_lines {
    my ( $package, $line, $pre_post_cnt ) = @_;

    # убираем ненужный каталог из пути
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

# Прочитать контент из файла-исходника в cp1251 или utf8 и вернуть его во внутренней кодировке.
# При смешении кодировок в файле будет падать.
sub _read_source_file {
    my ( $file ) = @_;

    return  unless open my $src, '<', $file;
    my $content;
    {
        local $/ = undef;
        $content = <$src>;
    }
    close $src;

    # Пробуем конвертить бинарный контент файла во внутренний формат из utf-8, затем из cp1251.
    if ( my $decoded = eval { _decode_from( 'utf-8', $content ) } ) {
        return $decoded;
    }

    return _decode_from( 'cp1251', $content );
}


# Декодирует бинарную строку в кодировке $encoding во внутренний формат.
# Исходные данные не модифицируется. В случае не валидных входных данных происходит die.
sub _decode_from {
    my $res = Encode::decode($_[0], $_[1], Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
    _from_unicode $res;
    $res;
}

# Преобразовывает данные из Unicode во внутренний формат
sub _from_unicode {
    carp "Should only be used in void context" if defined wantarray;
    if ($self->{internal_character_format} eq 'cp1251') {
        for (@_) {
            confess SCALAR_NOT_REF_EXPECTED if ref;
            eval {
                defined and $_ = Encode::find_encoding('cp1251')->encode($_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
                1;
            } or do {
                confess "from_unicode called with "._hex_dump_string($_)." and crashed: $@";
            }
        }
    }
    return;
}


sub _hex_dump_string {
    my ($str, %opts) = @_;
    return undef unless defined $str;

    # считается плохим тоном использовать is_utf8/_utf8_off, но здесь мы это делаем т.к. хотим
    # выставить "наружу" внутренности строки

    my $isutf = utf8::is_utf8($str);
    Encode::_utf8_off($str);

    # Ограничиваем размер данных (если заданно)
    my $is_cut = 0;
    if ( $opts{bytes_limit} ) {
        my $str_length = length $str;

        if ( $str_length > $opts{bytes_limit} ) {
            $str = substr($str, 0, $opts{bytes_limit});
            $is_cut = 1;
        }
    }

    $str =~ s/\\/\\\\/g;
    if (!$opts{keep_lf}) {
        $str =~ s/\r/\\r/g;
        $str =~ s/\n/\\n/g;
    }
    $str =~ s/\t/\\t/g;
    $str =~ s/\"/\\\"/g;
    $str =~ s/([\x00-\x09\x0b-\x0c\x0e-\x1f\x7f]|[[:^ascii:]])/sprintf("\\x%02X",ord($1))/eg;
    $str = "\"$str\"" unless $opts{no_quotes};

    if ( $isutf && ! $opts{no_prefix} ) {
        $str = "(UTF-8) ".$str;
    }

    if ( $is_cut ) {
        $str = $str . "...";
    }

    $str;
}


1;
