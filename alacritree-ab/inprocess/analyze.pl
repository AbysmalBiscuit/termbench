#!/usr/bin/perl
# Pairs each [<what> gated] report window with the [<what> always] window
# beside it. The arms alternate strictly, so adjacent lines are a pair that met
# the same driver, the same grid and the same second -- which is the whole
# reason to run the comparison inside one process instead of across two
# launches.
#
# The stages the experiment does not touch are identical work under both arms,
# so their ratio is the noise floor this machine imposes. Any claim about
# `total` has to clear it.
use strict;
use warnings;

my (@g, @a, $what);
while (<>) {
    next unless /gpu grid \[(deco|bg|glyph) (gated|always)\], (\d+) frames: submit ([\d.]+)us/;
    my ($subject, $arm, $frames) = ($1, $2, $3);
    $what //= $subject;
    my ($skipped) = /skipped (\d+)\//;
    my ($total)   = /total ([\d.]+)us/;
    my ($whole)   = /frame ([\d.]+)us/;
    my ($bg)      = /backgrounds ([\d.]+)us/;
    my ($gl)      = /glyphs ([\d.]+)us/;
    my ($deco)    = /decorations ([\d.]+)us/;
    next unless defined $total;
    my $r = { frames => $frames, skipped => $skipped // 0, total => $total,
              whole => $whole, bg => $bg, gl => $gl, deco => $deco };
    $arm eq 'gated' ? push @g, $r : push @a, $r;
}

my $n = @g < @a ? @g : @a;
die "not enough complete windows (gated @{[scalar @g]}, always @{[scalar @a]})\n" unless $n >= 4;

sub median {
    my @v = sort { $a <=> $b } grep { defined } @_;
    return undef unless @v;
    @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2;
}

# Two-sided sign test on how many pairs went each way.  Ties carry no direction
# and the caller drops them: GPU timings land on repeated values often enough
# that counting a tie as one side turns plain agreement into a lopsided split.
sub sign_p {
    my ($k, $m) = @_;
    return 1 if $m == 0;
    $k = $m - $k if $k > $m - $k;
    my $tail = 0;
    for my $i (0 .. $k) {
        my $c = 1;
        $c = $c * ($m - $_) / ($_ + 1) for 0 .. $i - 1;
        $tail += $c;
    }
    my $p = 2 * $tail / (2 ** $m);
    $p > 1 ? 1 : $p;
}

sub row {
    my ($label, $pick, $note) = @_;
    my (@gv, @av, @ratio);
    for my $i (0 .. $n - 1) {
        my ($gv, $av) = ($pick->($g[$i]), $pick->($a[$i]));
        push @gv, $gv;
        push @av, $av;
        push @ratio, $gv / $av if defined $gv && defined $av && $av > 0;
    }
    my $gm = median(@gv);
    my $am = median(@av);
    unless (@ratio) {
        printf "%-32s %9s %9s %8s %7s  %s\n", $label,
               defined $gm ? sprintf('%.0fus', $gm) : '-',
               defined $am ? sprintf('%.0fus', $am) : '-', '-', '-', $note // '';
        return;
    }
    my @moved = grep { $_ != 1 } @ratio;
    my $below = grep { $_ < 1 } @moved;
    printf "%-32s %8.0fus %8.0fus %8.3f %7.3f  %s\n", $label, $gm, $am,
           median(@ratio), sign_p($below, scalar @moved), $note // '';
}

$what //= 'deco';
# The control is every stage the experiment leaves alone.  Summing the stage
# under test into it would put the effect inside its own baseline.
my %control = (
    deco  => ['backgrounds + glyphs', sub { ($_[0]{bg} // 0) + ($_[0]{gl} // 0) }],
    bg    => ['glyphs + decorations', sub { ($_[0]{gl} // 0) + ($_[0]{deco} // 0) }],
    glyph => ['backgrounds + decorations', sub { ($_[0]{bg} // 0) + ($_[0]{deco} // 0) }],
);
my %subject = (
    deco  => 'the decoration pass',
    bg    => 'the background quad',
    glyph => 'the glyph coverage read',
);
my ($control_label, $control_pick) = @{ $control{$what} };

printf "%d pairs, flipping %s\n\n", $n, $subject{$what};
printf "%-32s %9s %9s %8s %7s\n", 'measurement', 'gated', 'always', 'ratio', 'p';
row('total GPU per frame', sub { $_[0]{total} });
row('whole callback', sub { $_[0]{whole} }, '<- measured, not summed');
row($control_label, $control_pick, '<- null control, same work');
row('backgrounds', sub { $_[0]{bg} });
row('glyphs', sub { $_[0]{gl} });
row('decorations', sub { $_[0]{deco} });

my @saved = map { $a[$_]{total} - $g[$_]{total} } 0 .. $n - 1;
printf "\nsaved per frame (median):  %.0fus\n", median(@saved);

# `total` adds the stages up; `whole` is one bracket around the callback,
# measured on the frames between them.  The gap is the clear, which sits in no
# stage, plus whatever a bracket charges its stage beyond the work inside it --
# so it is the ceiling on how much of any stage median is real.
my @floor = map { $g[$_]{whole} - $g[$_]{total} }
            grep { defined $g[$_]{whole} } 0 .. $n - 1;
printf "whole callback minus stage sum (median):  %.0fus\n", median(@floor) if @floor;

# Only the decoration experiment can drop its whole draw; the background
# collapse happens in the vertex shader, where no counter on this side sees it.
if ($what eq 'deco') {
    my $fired = grep { $_->{skipped} == $_->{frames} } @g;
    my $partial = grep { $_->{skipped} > 0 && $_->{skipped} < $_->{frames} } @g;
    my $drew = grep { $_->{skipped} == 0 } @g;
    printf "gated windows: %d skipped every frame, %d drew every frame, %d mixed\n",
           $fired, $drew, $partial;
    my $leak = grep { defined $_->{deco} && $_->{skipped} == $_->{frames} } @g;
    printf "gated windows that skipped yet reported a decoration time: %d\n", $leak;
}
