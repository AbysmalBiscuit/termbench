#!/usr/bin/perl
# Prints one arm's stage medians in the order the windows were logged.
#
# `analyze.pl` pairs adjacent windows and reports ratios, which is deliberately
# blind to drift: both arms of a pair meet the same clocks, so a ratio survives
# a GPU that is still ramping.  The absolute microseconds do not, and the only
# way to see that is to read one arm down the run.
use strict;
use warnings;

my ($arm) = @ARGV ? ($ARGV[0]) : ('gated');
shift @ARGV if @ARGV;

my @w;
while (<>) {
    next unless /gpu grid \[(?:\w+) (gated|always)\], (\d+) frames:/;
    next unless $1 eq $arm;
    my ($total) = /total ([\d.]+)us/;
    my ($whole) = /frame ([\d.]+)us/;
    my ($bg)    = /backgrounds ([\d.]+)us/;
    my ($gl)    = /glyphs ([\d.]+)us/;
    push @w, { total => $total, whole => $whole, bg => $bg, gl => $gl };
}
die "no [$arm] windows in the input\n" unless @w;

sub median {
    my @v = sort { $a <=> $b } grep { defined } @_;
    return undef unless @v;
    @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2;
}

printf "%d [%s] windows\n\n", scalar @w, $arm;
printf "%5s %9s %9s %9s %9s\n", 'window', 'total', 'whole', 'bg', 'glyphs';
for my $i (0 .. $#w) {
    printf "%5d %8s %8s %8s %8s\n", $i,
           map { defined $w[$i]{$_} ? sprintf('%.0fus', $w[$i]{$_}) : '-' }
           qw(total whole bg gl);
}

# A GPU that starts a run at an idle clock and ramps shows up as the head of
# the run costing a multiple of the tail on identical work.  Nothing else in
# this harness changes across a run.
my $q = int(@w / 4) || 1;
for my $field (['total', 'total'], ['whole', 'whole'], ['gl', 'glyphs']) {
    my ($key, $label) = @$field;
    my $head = median(map { $_->{$key} } @w[0 .. $q - 1]);
    my $tail = median(map { $_->{$key} } @w[$#w - $q + 1 .. $#w]);
    next unless defined $head && defined $tail && $tail > 0;
    printf "\n%-8s first %d: %.0fus   last %d: %.0fus   ratio %.2f",
           $label, $q, $head, $q, $tail, $head / $tail;
}
print "\n";
