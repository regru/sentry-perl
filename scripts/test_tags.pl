use lib 'lib';
use Reg::Sentry2;
use Data::Dumper;

my $s = Reg::Sentry2->new('https://035e54ae6fc447b39859800fac929c25:dfa6dd5a7e4349c2aa9a81e50506968b@sentry.reg.ru/22');

warn "Ok";


my $a = $s->info( 'Katastrofa', extra => { 'var 1 was' => $var1, 'var 2 was' => $var2 }, tags => { send_alerts => 'no'} );

warn Dumper $a;
