# $Id: 20compile.t 768 2006-09-17 14:24:14Z nicolaw $

chdir('t') if -d 't';
use lib qw(./lib ../lib);
use Test::More tests => 2;

use_ok('Parse::DMIDecode');
require_ok('Parse::DMIDecode');

1;

