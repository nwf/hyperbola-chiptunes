#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Data::Compare;

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
my %instrumentrows = ( );

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
        $ix = hex $ix;
        die "Malformed songline (channel mismatch): '$LINE'"
            if ((scalar @tts) != 2*$channels);
        die "Duplicate song row '$ix'." if exists $songrows{$ix};
        $songrows{$ix} = [ ];
        for my $i (0..$channels-1) {
            # print " '", $ix, "' '", $tts[2*$i] , "' '", $tts[2*$i+1], "'\n";

            push @{$songrows{$ix}}, [hex $tts[2*$i], hex $tts[2*$i+1]];
        }
    } elsif($cmd eq "trackline") {
        my ($tix, $ix, $note, $instr, $c0, $p0, $c1, $p1, @junk) = split ' ', $rest;
        $tix = hex $tix;
        $ix = hex $ix;
        die "Malformed trackline: '$LINE'"
            if scalar @junk != 0 or not defined $p1;
        die "Duplicate track row '$tix:$ix'."
            if exists $trackrows{$tix} and exists $trackrows{$tix}{$ix};
        $trackrows{$tix} = { } if not exists $trackrows{$tix};
        my @trackv = map {hex} ($note, $instr, $c0, $p0, $c1, $p1);
        $trackrows{$tix}{$ix} = \@trackv;
    } elsif($cmd eq "instrumentline") {
        my ($iix, $ix, $cmd, $param, @junk) = split ' ', $rest;
        $iix = hex $iix;
        $ix = hex $ix;
        die "Malformed instrumentline: '$LINE'"
            if scalar @junk != 0 or not defined $param;
        die "Duplicate instrument row '$iix:$ix'."
            if exists $instrumentrows{$iix} and exists $instrumentrows{$iix}{$ix};
        $instrumentrows{$iix} = { } if not exists $instrumentrows{$iix};
        $instrumentrows{$iix}{$ix} = [hex $cmd, hex $param];
    } else {
        die "Unknown line command in '$LINE'";
    }
}

my %track_rename = ( );
my %instrument_rename = ( );

while (my ($six, $w) = each %songrows) {
    foreach my $v (@$w) {
        $track_rename{$$v[0]} = -1;
    }
}

while (my ($tix, $w) = each %trackrows) {
    while (my ($ix, $v) = each %{$w}) {
        my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;
        $instrument_rename{$iix} = -1;
    }
}

# search for unused tracks
foreach my $tix (keys %trackrows) {
    if (not exists $track_rename{$tix}) {
        print STDERR "Pruning unused track $tix\n";
    }
}

# Compute track renames
{
    $track_rename{0} = 0;
    my $new_track_num = 1;
    foreach my $track (sort keys %track_rename) {
        next if $track_rename{$track} != -1;
        $track_rename{$track} = $new_track_num++;
    }
}

# search for unused instruments
foreach my $iix (keys %instrumentrows) {
    if (not exists $instrument_rename{$iix}) {
        print STDERR "Pruning unused instrument $iix\n";
    }
}

# Compute instrument renames
{
    $instrument_rename{0} = 0;
    my $new_instr_num = 1;
    foreach my $instr (sort keys %instrument_rename) {
        next if $instrument_rename{$instr} != -1;
        $instrument_rename{$instr} = $new_instr_num++;
    }
}

my %newsongrows = ( );
my %newtrackrows = ( );
my %newinstrumentrows = ( );

while (my ($six, $w) = each %songrows) {
    my @res = map 
        { my ($trk, $trn) = @$_; [$track_rename{$trk}, $trn] }
        @$w;
    $newsongrows{$six} = \@res;
}

while (my ($tix, $w) = each %trackrows) {
    next if not exists $track_rename{$tix};
    $newtrackrows{$track_rename{$tix}} = {};
    while (my ($ix, $v) = each %{$w}) {
        my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;
        $newtrackrows{$track_rename{$tix}}{$ix} =
            [$note, $instrument_rename{$iix}, $c0, $p0, $c1, $p1];
    }
}

while (my ($iix, $w) = each %instrumentrows) {
    next if not exists $instrument_rename{$iix};
    $newinstrumentrows{$instrument_rename{$iix}} = $w;
}

warn "Too many tracks!" if exists $newtrackrows{2**6-1};
warn "Too many instruments!" if exists $newinstrumentrows{2**4-1};

print "musicchip tune\nversion 1\n\n";

while (my ($six, $w) = each %newsongrows) {
    printf "songline %02x", $six;
    foreach my $tts (@$w) {
        my ($trk, $trn) = @$tts;
        printf " %02x %02x", $trk, $trn;
    }
    print "\n";
}

while (my ($tix, $w) = each %newtrackrows) {
    while (my ($ix, $v) = each %{$w}) {
        my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;
        printf "trackline %02x %02x %02x %02x %02x %02x %02x %02x\n",
                $tix, $ix, $note, $iix, $c0, $p0, $c1, $p1;
    }
}

while (my ($iix, $w) = each %newinstrumentrows) {
    while (my ($ix, $v) = each %$w) {
        my ($cmd, $param) = @$v;
        printf "instrumentline %02x %02x %02x %02x\n",
            $iix, $ix, $cmd, $param;
    }
}


