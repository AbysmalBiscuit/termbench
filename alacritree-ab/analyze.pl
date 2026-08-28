#!/usr/bin/perl
# Reads the paired result files and reports, per measurement, the per-pair ratio
# of the new binary's time to the old one's. Pairing is the point: each ratio
# comes from two runs a minute apart, so machine load largely divides out, where
# two absolute numbers taken hours apart carry it whole.
#
# ratio > 1 means the new binary took longer on that pair.

use strict;
use warnings;

use File::Basename qw(dirname);
my $dir = dirname($0) . '/results';

sub read_run {
    my ($path) = @_;
    return undef unless -e $path;
    open my $fh, '<', $path or return undef;
    my (%t, @order);
    my ($tb_secs, $tb_bytes) = (0, 0);
    while (<$fh>) {
        chomp;
        my ($name, $secs, $bytes, $gbs) = split /\t/;
        next unless defined $gbs && length $gbs;
        $t{$name} = { secs => $secs, bytes => $bytes, gbs => $gbs };
        push @order, $name;
        if ($name =~ /^tb\./) { $tb_secs += $secs; $tb_bytes += $bytes; }
    }
    close $fh;
    return undef unless @order;

    # termbench's own closing line is the sum of its tests; rebuild it so the
    # headline number the tool prints on screen is in the comparison too.
    if ($tb_secs > 0) {
        $t{'tb.TOTAL'} = {
            secs  => $tb_secs,
            bytes => $tb_bytes,
            gbs   => $tb_bytes / (1024 ** 3) / $tb_secs,
        };
        push @order, 'tb.TOTAL';
    }
    return { tests => \%t, order => \@order };
}

sub median {
    my @v = sort { $a <=> $b } @_;
    return undef unless @v;
    return @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2;
}

# Two-sided sign test: probability of a split at least this lopsided by chance.
sub sign_p {
    my ($k, $n) = @_;
    return 1 if $n == 0;
    $k = $n - $k if $k > $n - $k;
    my $tail = 0;
    for my $i (0 .. $k) {
        my $c = 1;
        $c = $c * ($n - $_) / ($_ + 1) for 0 .. $i - 1;
        $tail += $c;
    }
    my $p = 2 * $tail / (2 ** $n);
    return $p > 1 ? 1 : $p;
}

opendir my $dh, $dir or die "no results dir: $dir\n";
my @tags = sort map { /^(pair\d+)-old\.tsv$/ ? $1 : () } readdir $dh;
closedir $dh;
die "no completed pairs in $dir\n" unless @tags;

my (@names, %seen, %ratios, %old_secs, %new_secs, %old_gbs, %new_gbs);
my @complete;

for my $tag (@tags) {
    my $old = read_run("$dir/$tag-old.tsv");
    my $new = read_run("$dir/$tag-new.tsv");
    next unless $old && $new;
    push @complete, $tag;
    for my $n (@{ $old->{order} }) {
        next unless $new->{tests}{$n};
        unless ($seen{$n}++) { push @names, $n }
        push @{ $ratios{$n} },   $new->{tests}{$n}{secs} / $old->{tests}{$n}{secs};
        push @{ $old_secs{$n} }, $old->{tests}{$n}{secs};
        push @{ $new_secs{$n} }, $new->{tests}{$n}{secs};
        push @{ $old_gbs{$n} },  $old->{tests}{$n}{gbs};
        push @{ $new_gbs{$n} },  $new->{tests}{$n}{gbs};
    }
}

die "no pair has both arms yet\n" unless @complete;

# A round that painted a different grid measured different work. Say so loudly:
# such a pair belongs out of the comparison, not inside a median.
sub grid_of {
    my ($path) = @_;
    return '?' unless -e $path;
    open my $fh, '<', $path or return '?';
    chomp(my $g = <$fh> // '?');
    close $fh;
    return $g;
}
my %grid_count;
my @odd;
for my $tag (@complete) {
    for my $arm ('old', 'new') {
        my $g = grid_of("$dir/$tag-$arm.tsv.grid");
        $grid_count{$g}++ unless $g eq '?';
    }
}
my ($modal) = sort { $grid_count{$b} <=> $grid_count{$a} } keys %grid_count;
# A run predating the grid sidecar records none at all, which is silence rather
# than disagreement: there is nothing to compare rounds against.
for my $tag (defined $modal ? @complete : ()) {
    for my $arm ('old', 'new') {
        my $g = grid_of("$dir/$tag-$arm.tsv.grid");
        push @odd, "$tag-$arm painted $g" if $g ne $modal && $g ne '?';
    }
}
if (@odd) {
    print "WARNING: not every round painted the same grid (most were $modal)\n";
    print "  $_\n" for @odd;
    print "  those pairs compare different amounts of work; exclude them.\n\n";
}

printf "%d complete pair(s): %s\n\n", scalar @complete, join(' ', @complete);
printf "%-14s %5s %8s %8s %8s %8s %8s %7s  %s\n",
       'measurement', 'pairs', 'old s', 'new s', 'old gb/s', 'new gb/s',
       'ratio', 'p', 'per-pair ratios';

for my $n (@names) {
    my $r = $ratios{$n};
    my $count = scalar @$r;
    my $slower = grep { $_ > 1 } @$r;
    printf "%-14s %5d %8.3f %8.3f %8.4f %8.4f %8.3f %7.3f  %s\n",
           $n, $count,
           median(@{ $old_secs{$n} }), median(@{ $new_secs{$n} }),
           median(@{ $old_gbs{$n} }),  median(@{ $new_gbs{$n} }),
           median(@$r), sign_p($slower, $count),
           join(' ', map { sprintf '%.3f', $_ } @$r);
}

# A pair is only trustworthy if both its arms met the same machine. Printing the
# absolute termbench totals per pair puts a hot window on the page instead of
# leaving it to hide inside a median.
if ($old_secs{'tb.TOTAL'}) {
    my $base = median(@{ $old_secs{'tb.TOTAL'} });
    print "\ntermbench total per pair (load check; a run far above the rest met a busy machine)\n";
    printf "%-10s %9s %9s %9s\n", 'pair', 'old s', 'new s', 'max dev';
    for my $i (0 .. $#complete) {
        my ($o, $n) = ($old_secs{'tb.TOTAL'}[$i], $new_secs{'tb.TOTAL'}[$i]);
        my $dev = ($o > $n ? $o : $n) / $base - 1;
        printf "%-10s %9.2f %9.2f %8.0f%%\n", $complete[$i], $o, $n, 100 * $dev;
    }
}

print "\nratio = new/old wall time per pair; >1 means the new binary was slower.\n";
print "p is a two-sided sign test on how many pairs went each way.\n";
print "tb.=termbench  sg.=sgrtest  sc.=scrolltest  tb.TOTAL=termbench's closing line.\n";
