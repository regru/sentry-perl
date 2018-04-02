#!/usr/bin/perl
# perl -I lib t/build_message.t

use WWW::Sentry;
use Test::More;

my $dsn = 'http://public_key:secret_key@example.com/1234';

my $sentry = WWW::Sentry->new( $dsn, tags => { type => 'autocharge' } );

my $a = $sentry->_build_message(
    message => 'Arbeiten',
    some_unwanted_attr => 'Msg'
);

is($a->{message}, 'Arbeiten', 'Message attribute is correct');
is($a->{level}, 'info', 'Default level is info if not specified');
is($a->{tags}{type}, 'autocharge', 'Tag specified in constructor is set');
is($a->{platform}, 'perl', 'Default platform is perl');
is($a->{some_unwanted_attr}, undef, 'Filter parameters that are not defined in Sentry API for less payload');

done_testing();
