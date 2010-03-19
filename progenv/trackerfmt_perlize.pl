use strict;
use warnings;

use Data::Dumper;

sub parse_header($) {
    my ($FH) = @_;
    my %const = ( );
    while (my $line = <$FH>) {
        chomp $line;
        if($line =~ /#define\s+(PACKSIZE_\S+)\s+(\S+)\s*.*$/) {
            $const{$1} = $2;
        } elsif($line =~ /#define\s+(NR_\S+)\s+(\S+)\s*.*$/) {
            $const{$1} = $2;
        } elsif($line =~ /#define\s+(TRACKLEN)\s+(\S+)\s*.*$/) {
            $const{$1} = $2;
        }
    }

    return \%const;
}

open TF, '<', "progenv/trackerfmt.h" or die $!;
my $params = parse_header(*TF);
close TF;

print Dumper($params);
