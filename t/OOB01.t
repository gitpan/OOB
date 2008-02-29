BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use Test::More tests => 2;
use strict;
use warnings;

use_ok( 'OOB' ); # just for the record
can_ok( 'OOB',qw(
 OOB_get
 OOB_set
 OOB_reset
) );
