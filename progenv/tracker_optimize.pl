#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

my $version = 0;
my $channels = 0;
{ 
    my $HEADLINE = <STDIN>;
    chomp $HEADLINE;
    die "Header mismatch" if $HEADLINE ne "musicchip tune";

    my $VERSLINE = <STDIN>;
    chomp $VERSLINE;
    if ($VERSLINE =~ /^version (.*)$/) {
        $version = $1;
    } else {
        die "Malformed version line: '$VERSLINE'";
    }

    my $BLANKLINE = <STDIN>;
    chomp $BLANKLINE;
    die "Expected end of headers, but got '$BLANKLINE'\n" if $BLANKLINE ne "";
}

die "Wrong or unsupported version" if $version < 1 || $version > 1;

if (1 == $version) {
    $channels = 4;
}

my %songrows = ( );
my %trackrows = ( );
my %track_rename = ( );
my %instrumentrows = ( );
my %instrument_rename = ( );

while (my $LINE = <STDIN>) {
    chomp $LINE;
    next if $LINE eq "";

    my ($cmd, $rest);
    if($LINE =~ /^(\S*)(( [0-9a-f]{2})+)$/i) {
        ($cmd, $rest) = ($1, $2);
        chomp $rest;
    } else {
        die "Malformed line: '$LINE'\n";
    }

    if($cmd eq "songline") {
        my ($ix, @tts) = split ' ', $rest;
        die "Malformed songline (channel mismatch): '$LINE'"
            if ((scalar @tts) != 2*$channels);
        die "Duplicate song row '$ix'." if exists $songrows{$ix};
        $songrows{$ix} = [ ];
        for my $i (0..$channels-1) {
            # print " '", $ix, "' '", $tts[2*$i] , "' '", $tts[2*$i+1], "'\n";

            $track_rename{$tts[2*$i]} = -1;
            push @{$songrows{$ix}}, [$tts[2*$i], $tts[2*$i+1]];
        }
    } elsif($cmd eq "trackline") {
        my ($tix, $ix, $note, $instr, $c0, $p0, $c1, $p1, @junk) = split ' ', $rest;
        die "Malformed trackline: '$LINE'"
            if scalar @junk != 0 or not defined $p1;
        die "Duplicate track row '$tix:$ix'."
            if exists $trackrows{$tix} and exists $trackrows{$tix}{$ix};
        $trackrows{$tix} = { } if not exists $trackrows{$tix};
        $trackrows{$tix}{$ix} = [$note, $instr, $c0, $p0, $c1, $p1];
        $instrument_rename{$instr} = -1;
    } elsif($cmd eq "instrumentline") {
        my ($iix, $ix, $cmd, $param, @junk) = split ' ', $rest;
        die "Malformed instrumentline: '$LINE'"
            if scalar @junk != 0 or not defined $param;
        die "Duplicate instrument row '$iix:$ix'."
            if exists $instrumentrows{$iix} and exists $instrumentrows{$iix}{$ix};
        $instrumentrows{$iix} = { } if not exists $instrumentrows{$iix};
        $instrumentrows{$iix}{$ix} = [$cmd, $param];
    } else {
        die "Unknown line command in '$LINE'";
    }
}

# search for unused tracks
foreach my $tix (keys %trackrows) {
    if (not exists $track_rename{$tix}) {
        print STDERR "Pruning unused track $tix\n";
        delete $trackrows{$tix};
    }
}

# Rename tracks
{
    $track_rename{'00'} = 0;
    my $new_track_num = 1;
    foreach my $track (sort keys %track_rename) {
        next if $track_rename{$track} != -1;
        $track_rename{$track} = $new_track_num++;
    }
}

# search for unused instruments
foreach my $iix (keys %instrumentrows) {
    if (not exists $instrument_rename{$iix}) {
        print STDERR "Unused instrument $iix\n";
        delete $instrumentrows{$iix};
    }
}

# Rename instruments
{
    $instrument_rename{'00'} = 0;
    my $new_instr_num = 1;
    foreach my $instr (sort keys %instrument_rename) {
        next if $instrument_rename{$instr} != -1;
        $instrument_rename{$instr} = $new_instr_num++;
    }
}

print "musicchip tune\nversion 1\n\n";

while (my ($six, $w) = each %songrows) {
    print "songline $six";
    foreach my $tts (@$w) {
        my ($trk, $trn) = @$tts;
        printf " %02x %s", $track_rename{$trk}, $trn;
    }
    print "\n";
}

while (my ($tix, $w) = each %trackrows) {
    while (my ($ix, $v) = each %{$w}) {
        printf "trackline %02x %s %s\n", $track_rename{$tix}, $ix, (join ' ', @$v);
    }
}

while (my ($iix, $w) = each %instrumentrows) {
    while (my ($ix, $v) = each %$w) {
        printf "instrumentline %s %s %s\n", $iix, $ix, (join ' ', @$v);
    }
}


