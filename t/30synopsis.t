# $Id: 30tie.t 567 2006-06-01 18:38:57Z nicolaw $

chdir('t') if -d 't';

use strict;
use Test::More tests => 10;
use lib qw(./lib ../lib);
use Parse::DMIDecode qw();

my $data;

my $dmi;
ok($dmi = new Parse::DMIDecode,'new');

ok($dmi->parse(slurp('dmidecode_eowyn.txt')),'parse dmidecode_eowyn.txt');
ok($dmi->keyword('system-serial-number') eq 'L3M4102','keyword system-serial-number');
ok($dmi->keyword('system-manufacturer') eq 'LENOVO','keyword system-serial-manufacturer');

ok($dmi->parse(slurp('dmidecode_arwen.txt')),'parse dmidecode_arwen.txt');
ok($dmi->keyword('bios-version') eq 'ASUS A7N266-VM ACPI BIOS Rev 1005','keyword bios-version');
ok($dmi->keyword('processor-version') eq 'AMD Athlon(TM) XP Processor','keyword processor-version');

ok($dmi->parse(slurp('dmidecode_aragorn.txt')),'parse dmidecode_aragorn.txt');
ok($dmi->keyword('bios-vendor') eq 'Dell Inc.','keyword bios-vendor');
ok($dmi->keyword('system-product-name') eq 'OptiPlex GX620','keyword system-product-name');

sub slurp {
	my $file = shift;
	my $data = '';
	if (open(FH,'<',$file)) {
		local $/ = undef;
		$data = <FH>;
		close(FH);
	}
	return $data;
}

1;

