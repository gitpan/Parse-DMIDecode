#!/usr/bin/perl -w

BEGIN { chdir '../' if -d '../examples/'; }

use strict;
use lib qw(./lib);
use Parse::DMIDecode;
use Parse::DMIDecode::Constants qw(@TYPES);

my $decoder = new Parse::DMIDecode;
#$decoder->probe;
#$decoder->parse(qx(sudo /usr/sbin/dmidecode));
$decoder->parse(`cat t/dmidecode_example4.txt`);

#print join("\n",$decoder->keywords)."\n";
#print $decoder->keyword('system-manufacturer')."\n";
#exit;

for my $handle ($decoder->get_handles( group => 'system' )) {
	printf(">>> Found handle at %s (%s):\n >> Keywords: %s\n%s\n",
			$handle->address,
			$TYPES[$handle->dmitype],
			join(', ',$handle->keywords),
			$handle->raw
		);
	for my $keyword ($handle->keywords) {
		printf("  > Keyword %s => '%s'\n",
				$keyword,
				$handle->keyword($keyword)
			);
	}
	print "\n\n";
}




