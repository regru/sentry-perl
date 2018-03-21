use lib 'lib';
use Reg::Sentry;
use Data::Dumper;

my $s = Reg::Sentry->new(dsn => 'https://035e54ae6fc447b39859800fac929c25:dfa6dd5a7e4349c2aa9a81e50506968b@sentry.reg.ru/22');
my $a = $s->info( 'Test panic!', extra => { 'var 1 was' => $var1, 'var 2 was' => $var2 } );

warn Dumper $a;
