# $Id: 30tie.t 567 2006-06-01 18:38:57Z nicolaw $

chdir('t') if -d 't';

use strict;
use warnings;
use Test::More;
use lib qw(./lib ../lib);
use Parse::DMIDecode qw();

my @files = glob('testdata/*');
plan tests => (scalar(@files)*16) + 1;

my $dmi;
ok($dmi = Parse::DMIDecode->new(nowarnings => 1),'new');

for my $file (@files) {
	ok($dmi->parse(slurp($file)),$file);
	ok($dmi->smbios_version >= 2.0,"$file \$dmi->smbios_version");
	#ok($dmi->dmidecode_version >= 2.0,"$file \$dmi->dmidecode_version");
	ok($dmi->table_location,"$file \$dmi->table_location");
	ok($dmi->structures == scalar($dmi->handle_addresses),"$file \$dmi->structures == \$dmi->handle_addresses");
	for my $dmitype (qw(0 1 2 3)) {
		my @handles;
		ok(
			@handles = $dmi->get_handles( dmitype => $dmitype ),
			"$file \$dmi->get_handles(dmitype => $dmitype)"
		);
		ok($handles[0]->dmitype == $dmitype,"$file \$handle->dmitype");
		ok($handles[0]->bytes =~ /^\d+$/,"$file \$handle->bytes");
	}
}

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

