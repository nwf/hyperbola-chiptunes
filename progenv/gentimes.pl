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
my $mode = "C";

my %OPTS = (
	'fcpu=i' => \$FCPU,
	'samprate=i' => \$SAMPLERATE,
	'sinewsize=i' => \$SINEWSIZE,
	'mode=s' => \$mode,
);

GetOptions(%OPTS) or die;


if ($mode eq "C") {
	print "#include \"progenv/gentimes.h\"\n";

	print "const uint8_t sinetable[] = {\n";
	print join ", ", map { int } @{gensinetab($SINEWSIZE,127)} ;
	print "};\n\n";

	# The frequency table ranges from C1 (note 4) to B7 (note 87)
	# 
	print "const uint16_t freqtable[] = {\n";
	foreach (@{genfreqtab($SAMPLERATE,4,87)}) { printf "0x%04x, ", int($_); }
	print "};\n\n";
} elsif ($mode eq "H") {
	print "#ifndef __PROGENV_GENTIMES_H__\n";
	print "#define __PROGENV_GENTIMES_H__\n\n";

	print "#ifdef ASSEMBLER\n";
	print "\t.global sinetable;\n";
	print "\t.global freqtable;\n";
	print "#else\n";
	print "#include <progenv/types.h>\n\n";
	print "extern const uint8_t sinetable[];\n";
	print "extern const uint16_t freqtable[];\n";
	print "#endif /* ASSEMBLER */\n\n";

	# Generate timer0 prescaler and limit for the mode we use.
	# t0denoms are from AVR spec.
	my @t0denoms = ( undef, 1, 8, 64, 256, 1024, undef, undef );
	my $ix = 1;
	while ($ix < 5 and $FCPU/$SAMPLERATE/$t0denoms[$ix] > 255) { $ix++; }
	die if not defined $t0denoms[$ix];
	print "#define T0DIV ", $ix, "\n";
	print "#define T0MAX ",
		int($FCPU/$SAMPLERATE/$t0denoms[$ix]), "\n\n";

	print "#define PLAY_WAIT ", $SAMPLERATE/100, ";\n\n";

	print "#endif /* __PROGENV_GENTIMES_H__ */\n";
} else {
	die "Invalid mode requested\n";
}
