#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Math::Trig 'pi2';

sub genfreqtab ($$$) {
	my ($sr,$lo,$hi) = @_;
	my $res = [ ];
	for my $i ($lo..$hi) {
		push @$res, 2**16/$sr*(440*2**(($i-49)/12));
	}	
	$res
}

sub gensinetab ($$) {
	my ($ndiv, $max) = @_;
	my $res = [ ];
	for my $i (0..$ndiv-1) {
		push @$res, int(sin(pi2*$i/$ndiv) * $max);
	}
	$res
}

my $FCPU = 20000000;
my $SAMPLERATE = 16000;
my $SINEWSIZE = 64;

print "#include \"progenv/gentimes.h\"\n";

print "const s8 sinetable[] = {\n";
print join ", ", map { int } @{gensinetab($SINEWSIZE,127)} ;
print "};\n\n";

# The frequency table ranges from C1 (note 4) to B7 (note 87)
# 
print "const u16 freqtable[] = {\n";
foreach (@{genfreqtab($SAMPLERATE,4,87)}) { printf "%4x, ", int($_); }
print "};\n\n";

# Generate timer0 prescaler and limit for the mode we use.
# t0denoms are from AVR spec.
my @t0denoms = ( undef, 1, 8, 64, 256, 1024, undef, undef );
my $ix = 1;
while ($ix < 5 and $FCPU/$SAMPLERATE/$t0denoms[$ix] > 255) { $ix++; }
die if $ix == 5;
print "const int T0DIV = ", $ix, ";\n";
print "const int T0MAX = ",
		int($FCPU/$SAMPLERATE/$t0denoms[$ix]), ";\n\n";
