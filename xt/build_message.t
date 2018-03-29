#!/usr/bin/perl

# perl -I lib xt/build_message.t
# Testing stacktrace

use WWW::Sentry;

my $dsn = 'http://public_key:secret_key@example.com/1234';

sub test_die {
    die "Die message";
}

eval { test_die() };


# print $SIG{__DIE__};
# warn Carp::longmess();

my $sentry = WWW::Sentry->new( $dsn, tags => { type => 'autocharge' } );

my $a = $sentry->_build_message(
    message => 'Arbeiten',
    level => 'info',
    tags => { 'tag1' => 'value1' },
    # modules => `cpan -l`,
    extra => { 'extrakey' => 'extraval' },
    user => 'pavelsr',
    stacktrace => [ 'a' , 'b' ]
);

#
# use Data::Dumper;
#
# warn Dumper $a;
