#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Data::Compare;
use Getopt::Long;

my $OPTIMIZE = 0;
my $VERBOSE = 0;

my $TRACKOUTF = undef;

my $PACKOUTF = undef;
my $HEADOUTF = undef;
my $PACKVER = 0;

my @IVERPAR = ( undef,
    { 'channels' => 4
    , 'emptysong' => [[0,0],[0,0],[0,0],[0,0]]
    , 'emptytrack' => [0, 0, 0, 0, 0, 0]
    , 'cmdchars' => '0dfijlmtvw~+='
    , 'version' => 1
    },
);

my @OVERPAR = (
    { 'BASE_INSTR' => '1'
    , 'BASE_TRACK' => '1'
    , 'NR_CHAN' => '4'
    , 'NR_SONGS' => '1'
    , 'PACKSIZE_INSTRPAR' => '8'
    , 'PACKSIZE_INSTRCMD' => '8'
    , 'PACKSIZE_RESOURCE' => '13'
    , 'PACKSIZE_SONGTRACK' => '6'
    , 'PACKSIZE_SONGTRANS' => '4'
    , 'PACKSIZE_TRACKCMD' => '4'
    , 'PACKSIZE_TRACKINST' => '4'
    , 'PACKSIZE_TRACKNOTE' => '7'
    , 'PACKSIZE_TRACKPAR' => '8'
    , 'TRACKLEN' => '32'
    , 'INSTRPACKER' => \&pack_inst_linear
    },
    { 'BASE_INSTR' => '1'
    , 'BASE_TRACK' => '1'
    , 'NR_CHAN' => '4'
    , 'NR_SONGS' => '1'
    , 'PACKSIZE_INSTRCMD' => '4'
    , 'PACKSIZE_INSTRPAR' => '8'
    , 'PACKSIZE_RESOURCE' => '13'
    , 'PACKSIZE_SONGTRACK' => '6'
    , 'PACKSIZE_SONGTRANS' => '4'
    , 'PACKSIZE_TRACKCMD' => '5'
    , 'PACKSIZE_TRACKINST' => '4'
    , 'PACKSIZE_TRACKPAR' => '8'
    , 'PACKSIZE_TRACKNOTE' => '7'
    , 'TRACKLEN' => '32'
    , 'INSTRPACKER' => \&pack_inst_alternating
    }
);

sub h2a($) {
    my ($hash) = @_;
    my @res = ( );
    while (my ($k,$v) = each %{$hash}) {
        $res[$k] = $v;
    }
    return \@res;
}

sub hh2aa($) {
    my ($hash) = @_;
    my @res = ( );
    while (my ($k,$v) = each %{$hash}) {
        $res[$k] = [ ];
        while (my ($l,$w) = each %{$v}) {
            $res[$k][$l] = $w;
        }
    }
    return \@res;

}

sub new_pack() { return [ "", () ]; }

sub append_pack($$$) {
    my ($pack, $size, $arg) = @_;
    my ($pack_str, @pack_inprog) = @$pack;

    my @nc = split //, (sprintf "%${size}.${size}b",
                                ($arg & ((1 << $size)-1)) );
    while ($#nc > -1) {
        unshift @pack_inprog, pop @nc;

        if ($#pack_inprog == 7) {
            $pack_str .= join "", @pack_inprog;
            @pack_inprog = ();
        }
    }

    @$pack = ($pack_str, @pack_inprog);

    return $pack;
}

sub finish_pack($) {
    my ($pack) = @_;
    my ($pack_str, @pack_inprog) = @$pack;

    return $pack if $#pack_inprog == -1;

    while ($#pack_inprog < 7) {
        unshift @pack_inprog, '0';
    }
    $pack_str .= join "", @pack_inprog;
    @pack_inprog = ();

    @$pack = ($pack_str, @pack_inprog);

    return $pack;
}   

# Should produce 77002a84851F:
#
#my $pack0 = new_pack();
#append_pack($pack0, 13, 0x077);
#append_pack($pack0, 13, 0x150);
#append_pack($pack0, 13, 0x161);
#append_pack($pack0, 6, 0xFF);
#finish_pack($pack0);
#print STDERR Dumper($pack0);
#my @res = split //, (pack 'B*', ${finish_pack($pack0)}[0]);
#print STDERR (map {sprintf '%2.2x', ord $_} @res), "\n";
#exit;

sub parse ($) {
    my ($FH) = @_;

    my $v = 0;
    my $channels = 0;
    { 
        my $HEADLINE = <$FH>;
        chomp $HEADLINE;
        die "Header mismatch" if $HEADLINE ne "musicchip tune";

        my $VERSLINE = <$FH>;
        chomp $VERSLINE;
        if ($VERSLINE =~ /^version (.*)$/) {
            $v = $1;
        } else {
            die "Malformed version line: '$VERSLINE'";
        }

        my $BLANKLINE = <$FH>;
        chomp $BLANKLINE;
        die "Expected end of headers, but got '$BLANKLINE'\n" if $BLANKLINE ne "";
    }

    my $iverpar = $IVERPAR[$v];
    die "Wrong or unsupported version" if not defined $iverpar;
    $channels = $$iverpar{'channels'};

    my %songrows = ( );
    my %trackrows = ( );
    my %instrumentrows = ( );

    while (my $LINE = <$FH>) {
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
            my ($ix, @tts) = map { hex } split ' ', $rest;
            die "Malformed songline (channel mismatch): '$LINE'"
                if ((scalar @tts) != 2*$channels);
            die "Duplicate song row '$ix'." if exists $songrows{$ix};
            $songrows{$ix} = [ ];
            for my $i (0..$channels-1) {
                # print " '", $ix, "' '", $tts[2*$i] , "' '", $tts[2*$i+1], "'\n";
    
                push @{$songrows{$ix}}, [$tts[2*$i], $tts[2*$i+1]];
            }
        } elsif($cmd eq "trackline") {
            my ($tix, $ix, $note, $instr, $c0, $p0, $c1, $p1, @junk) = map { hex } split ' ', $rest;
            die "Malformed trackline: '$LINE'"
                if scalar @junk != 0 or not defined $p1;
            die "Duplicate track row '$tix:$ix'."
                if exists $trackrows{$tix} and exists $trackrows{$tix}{$ix};
            $trackrows{$tix} = { } if not exists $trackrows{$tix};

            if(exists $$iverpar{'cmdchars'}) {
                if($c0 != 0) {
                    my $nc0 = index $$iverpar{'cmdchars'}, chr $c0;
                    die "Unknown command $c0" if $nc0 == -1;
                    $c0 = $nc0;
                }
                if($c1 != 0) {
                    my $nc1 = index $$iverpar{'cmdchars'}, chr $c1;
                    die "Unknown command $c1" if $nc1 == -1;
                    $c1 = $nc1;
                }
            }

            $trackrows{$tix}{$ix} = [$note, $instr, $c0, $p0, $c1, $p1];
        } elsif($cmd eq "instrumentline") {
            my ($iix, $ix, $cmd, $param, @junk) = map { hex } split ' ', $rest;
            die "Malformed instrumentline: '$LINE'"
                if scalar @junk != 0 or not defined $param;
            die "Duplicate instrument row '$iix:$ix'."
                if exists $instrumentrows{$iix} and exists $instrumentrows{$iix}{$ix};
            $instrumentrows{$iix} = { } if not exists $instrumentrows{$iix};

            if(exists $$iverpar{'cmdchars'}) {
                if($cmd != 0) {
                    my $ncmd = index $$iverpar{'cmdchars'}, chr $cmd;
                    die "Unknown command $cmd" if $ncmd == -1;
                    $cmd = $ncmd;
                }
            }

            $instrumentrows{$iix}{$ix} = [$cmd, $param];
        } else {
            die "Unknown line command in '$LINE'";
        }
    }

    return ($iverpar, \%songrows, \%trackrows, \%instrumentrows);
}

sub remove_unused ($$$) {
    my ($songrows, $trackrows, $instrumentrows) = @_;
    my %track_rename = ( );
    my %instrument_rename = ( );

    while (my ($six, $w) = each %{$songrows}) {
        foreach my $v (@$w) {
            $track_rename{$$v[0]} = -1;
        }
    }

    while (my ($tix, $w) = each %{$trackrows}) {
        while (my ($ix, $v) = each %{$w}) {
            my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;
            $instrument_rename{$iix} = -1;
        }
    }

    # search for unused tracks
    if($VERBOSE) {
    foreach my $tix (keys %{$trackrows}) {
        if (not exists $track_rename{$tix}) {
            print STDERR "Pruning unused track $tix\n";
        }
    }}

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
    if($VERBOSE) {
    foreach my $iix (keys %{$instrumentrows}) {
        if (not exists $instrument_rename{$iix}) {
            print STDERR "Pruning unused instrument $iix\n";
        }
    }}

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

    while (my ($six, $w) = each %{$songrows}) {
        my @res = map 
            { my ($trk, $trn) = @$_; [$track_rename{$trk}, $trn] }
            @$w;
        $newsongrows{$six} = \@res;
    }

    while (my ($tix, $w) = each %{$trackrows}) {
        next if not exists $track_rename{$tix};
        $newtrackrows{$track_rename{$tix}} = {};
        while (my ($ix, $v) = each %{$w}) {
            my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;
            $newtrackrows{$track_rename{$tix}}{$ix} =
                [$note, $instrument_rename{$iix}, $c0, $p0, $c1, $p1];
        }
    }

    while (my ($iix, $w) = each %{$instrumentrows}) {
        next if not exists $instrument_rename{$iix};
        $newinstrumentrows{$instrument_rename{$iix}} = $w;
    }

    return (\%newsongrows, \%newtrackrows, \%newinstrumentrows);
}

sub padsong($$$) {
    my ($v, $params, $sr) = @_;

    my $asr = h2a($sr);
    foreach my $ix (0..$#$asr) {
        if (not defined $$asr[$ix]) {
            print STDERR "Filling in song gap at $ix\n" if $VERBOSE > 1;
            $$asr[$ix] = $$v{'emptysong'};
        }
    }

    return $asr;
}

sub padtracks($$$) {
    my ($v, $params, $tr) = @_;
    my $atr = hh2aa($tr);

    foreach my $ix (0..$#$atr) {
        foreach my $iix (0..$$params{'TRACKLEN'}-1) {
            if (not defined $$atr[$ix][$iix]) {
                print STDERR "Filling in track gap at $ix:$iix\n"
                    if $VERBOSE > 1;
                $$atr[$ix][$iix] = $$v{'emptytrack'};
            } 
        }
        die "Overlong track $ix\n" if $#{$$atr[$ix]} > $$params{'TRACKLEN'}-1;
    }

    return $atr;
}

sub padinstrs($$$) {
    my ($v, $params, $ir) = @_;
    my $air = hh2aa($ir);

    foreach my $ix (0..$#$air) {
        foreach my $iix (0..$#{$$air[$ix]}) {
            die "Undef in instrument ($ix:$iix)"
                if not defined $$air[$ix][$iix];
            my ($c, $p) = @{$$air[$ix][$iix]};
            die "Command zero in instrument context." if $c == 0;
        }
    }

    return $air;
}

sub printout($$$$$) {
    my ($FH, $iverpar, $songrows, $trackrows, $instrumentrows) = @_;

    print $FH "musicchip tune\nversion $$iverpar{'version'}\n\n";

    while (my ($six, $w) = each %{$songrows}) {
        printf $FH "songline %02x", $six;
        foreach my $tts (@$w) {
            my ($trk, $trn) = @$tts;
            printf $FH " %02x %02x", $trk, $trn;
        }
        print $FH "\n";
    }

    while (my ($tix, $w) = each %{$trackrows}) {
        while (my ($ix, $v) = each %{$w}) {
            my ($note, $iix, $c0, $p0, $c1, $p1) = @$v;

            if(exists $$iverpar{'cmdchars'}) {
                if($c0 != 0) {
                    my $nc0 = substr $$iverpar{'cmdchars'}, $c0, 1;
                    die "Unknown command $c0" if not defined $nc0;
                    $c0 = ord $nc0;
                }
                if($c1 != 0) {
                    my $nc1 = substr $$iverpar{'cmdchars'}, $c1, 1;
                    die "Unknown command $c1" if not defined $nc1;
                    $c1 = ord $nc1;
                }
            }

            printf $FH "trackline %02x %02x %02x %02x %02x %02x %02x %02x\n",
                    $tix, $ix, $note, $iix, $c0, $p0, $c1, $p1;
        }
    }

    while (my ($iix, $w) = each %{$instrumentrows}) {
        while (my ($ix, $v) = each %$w) {
            my ($cmd, $param) = @$v;

            if(exists $$iverpar{'cmdchars'}) {
                if($cmd != 0) {
                    my $ncmd = substr $$iverpar{'cmdchars'}, $cmd, 1;
                    die "Unknown command $cmd" if not defined $ncmd;
                    $cmd = ord $ncmd;
                }
            }

            printf $FH "instrumentline %02x %02x %02x %02x\n",
                $iix, $ix, $cmd, $param;
        }
    }
}

sub pack_song($$$) {
    my ($v, $format, $songrows) = @_;

    my $songpack = new_pack();
    map {
        foreach my $v (@$_) {
            my ($trk, $trn) = @$v;

            my $hastrn = (defined $trn  and $trn  != 0);
            append_pack($songpack, 1, $hastrn);

            if($hastrn) {
                append_pack($songpack, $$format{'PACKSIZE_SONGTRACK'}, $trk);
                append_pack($songpack, $$format{'PACKSIZE_SONGTRANS'}, $trn);
            } else {
                append_pack($songpack, $$format{'PACKSIZE_SONGTRACK'}, $trk);
            }
        }
    } @$songrows;

    return ${finish_pack($songpack)}[0];
}

sub pack_tracks($$$) {
    my ($v, $format, $trackrows) = @_;


    return [map {
        my $pi = new_pack();
        foreach my $v (@$_) {
            my ($note, $instr, $c0, $p0, $c1, $p1) = @$v;

            my $hasnote = (defined $note  and $note  != 0);
            my $hasinst = (defined $instr and $instr != 0);
            my $hascmd0 = (defined $c0    and $c0    != 0);
            my $hascmd1 = (defined $c1    and $c1    != 0);

            if ($hascmd1 and not $hascmd0) {
                $hascmd0 = 1;
                $hascmd1 = 0;
                $c0 = $c1;
                $p0 = $p1;
            }

            my $flags = 0;
            $flags += 1 if $hasnote;
            $flags += 2 if $hasinst;
            $flags += 4 if $hascmd0 or $hascmd1;

            append_pack($pi, 3, $flags);
            append_pack($pi, 1, $hascmd1) if $hascmd0;
            append_pack($pi, $$format{'PACKSIZE_TRACKNOTE'}, $note)
                if $hasnote;
            append_pack($pi, $$format{'PACKSIZE_TRACKINST'}, $instr)
                if $hasinst;
            if($hascmd0) {
                append_pack($pi, $$format{'PACKSIZE_TRACKCMD'}, $c0);
                append_pack($pi, $$format{'PACKSIZE_TRACKPAR'}, $p0);
            }
            if($hascmd1) {
                die "Unable to encode multiple commands in track line!" if $$v{'version'} < 2;
                append_pack($pi, $$format{'PACKSIZE_TRACKCMD'}, $c1);
                append_pack($pi, $$format{'PACKSIZE_TRACKPAR'}, $p1);
            }

        }
        ${finish_pack($pi)}[0];
    } @$trackrows];
}

sub pack_inst_linear ($$) {
    my ($inst, $format) = @_;

    my $pi = new_pack();
    foreach my $v (@$inst) {
        my ($c, $p) = @$v;
        append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, $c);
        append_pack( $pi, $$format{'PACKSIZE_INSTRPAR'}, $p);
    }
    append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, 0);
    ${finish_pack($pi)}[0];
}

sub pack_inst_alternating ($$) {
    my ($inst, $format) = @_;

    my $pi = new_pack();
    my $phase = 0;
    foreach my $v (@$inst) {
        my ($c, $p) = @$v;
        if($phase == 1) {
            append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, $c);
            append_pack( $pi, $$format{'PACKSIZE_INSTRPAR'}, $p);
        } else {
            append_pack( $pi, $$format{'PACKSIZE_INSTRPAR'}, $p);
            append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, $c);
        }
        $phase = 1 - $phase;
    }
    if($phase == 0) {
        append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, 0);
    } else {
        append_pack( $pi, $$format{'PACKSIZE_INSTRPAR'}, 0);
        append_pack( $pi, $$format{'PACKSIZE_INSTRCMD'}, 0);
    }
    ${finish_pack($pi)}[0];
}

sub pack_instrs($$$) {
    my ($v, $format, $instrumentrows) = @_;

    return [map {&{$$format{'INSTRPACKER'}}($_, $format)} @$instrumentrows];
}

sub packout($$$$$$) {
    my ($FH, $v, $params, $asr, $atr, $air) = @_;

    my $psong = pack_song($v, $params, $asr);
    my $ptrks = pack_tracks($v, $params, $atr);
    my $pinss = pack_instrs($v, $params, $air);

    # resource header
    my $offset = int(((1+15+$#$atr)*$$params{'PACKSIZE_RESOURCE'} + 7)/8);
    my $rpack = new_pack();
    append_pack($rpack, $$params{'PACKSIZE_RESOURCE'}, $offset);

    # song
    $offset += (length $psong)/8;

    # instruments
    for my $iix ($$params{'BASE_INSTR'}..$#$pinss) {
        append_pack($rpack, $$params{'PACKSIZE_RESOURCE'}, $offset);
        $offset += (length $$pinss[$iix])/8;
    }
    # missing instruments
    for my $iix ($#$pinss+1..2**$$params{'PACKSIZE_TRACKINST'}-1) {
        append_pack($rpack, $$params{'PACKSIZE_RESOURCE'}, $offset);
        $offset += 1;
    }

    # tracks
    for my $tix (1..$#$ptrks) {
        append_pack($rpack, $$params{'PACKSIZE_RESOURCE'}, $offset);
        $offset += (length $$ptrks[$tix])/8;
    }

    # header
    print $FH "\t.global\tsongdata\n\nsongdata:\n";

    # resources
    print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
        split //, pack 'B*', ${finish_pack($rpack)}[0], "\n";

    # song
    print $FH "\nsongdata_song:\n";
    print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
        split //, pack 'B*', $psong, "\n";

    #instruments
    for my $iix ($$params{'BASE_INSTR'}..$#$pinss) {
        print $FH "\nsongdata_instrument$iix:\n";
        print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
            split //, pack 'B*', $$pinss[$iix], "\n";
    }
    # missing instruments
    for my $iix ($#$pinss+1..2**$$params{'PACKSIZE_TRACKINST'}-1) {
        print $FH "\nsongdata_instrument$iix:\n\t.byte\t0x00\n";
    }

    # tracks
    for my $tix ($$params{'BASE_TRACK'}..$#$ptrks) {
        print $FH "\nsongdata_track$tix:\n";
        print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
            split //, pack 'B*', $$ptrks[$tix], "\n";
    }

    print $FH "songdata_end:\n";
}

sub packout_new($$$$$$) {
    my ($FH, $v, $params, $asr, $atr, $air) = @_;

    my $psong = pack_song($v, $params, $asr);
    my $ptrks = pack_tracks($v, $params, $atr);
    my $pinss = pack_instrs($v, $params, $air);

    # header
    print $FH ".section .rosdata,\"a\"\n";

    # song
    print $FH "\t.global\tsongdata\n\nsongdata:\n";
    printf $FH "\t.byte\t0x%02x\n", (scalar $#$asr)+1;
    print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
        split //, pack 'B*', $psong, "\n";
    print $FH "songdata_end:\n";

    # ptrtab for instruments
    print $FH "\n.global\titab\n\nitab:\n";
    for my $iix ($$params{'BASE_INSTR'}..$#$pinss) {
        printf $FH "\t.word\titab_$iix\n";
    }
#    # lentab for instruments
#    print $FH "\n.global\tilentab\n\nilentab:\n";
#    printf $FH "\t.byte\t0x%02x\n", $#$pinss - $$params{'BASE_INSTR'} + 1;
#    for my $iix ($$params{'BASE_INSTR'}..$#$pinss) {
#        printf $FH "\t.byte\t0x%02x\n", (length $$pinss[$iix])/8;
#    }
    for my $iix ($$params{'BASE_INSTR'}..$#$pinss) {
#        print $FH "\nilentab_$iix:\n";
        print $FH "\nitab_$iix:\n";
        print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
            split //, pack 'B*', $$pinss[$iix], "\n";
    }

    # ptrtab for instruments
    print $FH "\n.global\tttab\n\nttab:\n";
    for my $iix ($$params{'BASE_TRACK'}..$#$ptrks) {
        printf $FH "\t.word\tttab_$iix\n";
    }
#    # lentab for tracks
#    print $FH "\n.global\ttlentab\n\ntlentab:\n";
#    printf $FH "\t.byte\t0x%02x\n", $#$ptrks + 1;
#    for my $iix ($$params{'BASE_TRACK'}..$#$ptrks) {
#        printf $FH "\t.byte\t0x%02x\n", (length $$ptrks[$iix])/8;
#    }
    for my $iix ($$params{'BASE_TRACK'}..$#$ptrks) {
#        print $FH "\ntlentab_$iix:\n";
        print $FH "\nttab_$iix:\n";
        print $FH map { sprintf "\t.byte\t0x%02x\n", ord $_ }
            split //, pack 'B*', $$ptrks[$iix], "\n";
    }
}


sub packheadout($$$$$$) {
    my ($FH, $v, $params, $asr, $atr, $air) = @_;

    printf $FH "#define MAXTRACK 0x%x\n", (scalar $#$atr);
    printf $FH "#define SONGLEN 0x%x\n", (scalar $#$asr)+1;
}


GetOptions ( 'verbose=i' => \$VERBOSE
           , 'optimize'  => \$OPTIMIZE
           , 'trackout=s' => \$TRACKOUTF
           , 'packout=s' => \$PACKOUTF
           , 'headout=s' => \$HEADOUTF
           , 'packver=i' => \$PACKVER
           )
or die "Unable to parse command line: $!";

my $overpar = $OVERPAR[$PACKVER];
my ($iverpar, $sr, $tr, $ir) = parse(*STDIN);

my ($nsr, $ntr, $nir) = $OPTIMIZE ? remove_unused($sr, $tr, $ir)
                                  : ($sr, $tr, $ir);

($sr, $tr, $ir) = undef;

my $air = padinstrs($iverpar, $overpar, $nir);
my $atr = padtracks($iverpar, $overpar, $ntr);
my $asr = padsong  ($iverpar, $overpar, $nsr);

if (defined $TRACKOUTF) {
    open TRACKOUT,">$TRACKOUTF" or die "Can't open $TRACKOUTF: $!";
    printout(*TRACKOUT, $iverpar, $nsr, $ntr, $nir);
    close TRACKOUT
}

if (defined $PACKOUTF) {
    die "Also need --headout"
        if not defined $HEADOUTF and $PACKVER < 1;

    die "Too many input channels"
        if $$iverpar{'channels'} > $$overpar{'NR_CHAN'};
    die "Too many instruments!"
        if $#$air > 2**$$overpar{'PACKSIZE_TRACKINST'}-1;
    die "Too many tracks!"
        if $#$atr > 2**$$overpar{'PACKSIZE_SONGTRACK'}-1;

    if ($PACKVER < 1) {
        open PACKOUT,">$PACKOUTF" or die "Can't open $PACKOUTF: $!";
        packout(*PACKOUT, $iverpar, $overpar, $asr, $atr, $air);
        close PACKOUT;

        open HEADOUT,">$HEADOUTF" or die "Can't open $HEADOUTF: $!";
        packheadout(*HEADOUT, $iverpar, $overpar, $asr, $atr, $air);
        close HEADOUT;
    } else {
        open PACKOUT,">$PACKOUTF" or die "Can't open $PACKOUTF: $!";
        packout_new(*PACKOUT, $iverpar, $overpar, $asr, $atr, $air);
        close PACKOUT;
    }
}

