#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Dancer::SearchApp::HTMLSnippet;

#plan tests => 'no_plan';

# Sluurp
my $html = do { local(@ARGV,$/) = ('t/htmlsnippet.html'); <> };

my @snippets = Dancer::SearchApp::HTMLSnippet->extract_highlights(
    html => $html,
    max_length => 150,
);

is 0+@snippets, 8, "We get eight snippets back";

# All snippets should contain a matching number of em / /em tags
my @unmatched;
for my $s (@snippets) {
    my $text = substr($html, $s->{start}, $s->{length});
    my $opening = () =  ($text =~ m!<em>!g);
    my $closing = () =  ($text =~ m!</em>!g);
    push @unmatched, [$s,$text]
        if( $opening != $closing );
};
if( ! is 0+@unmatched, 0, "All matched phrases are balanced") {
    diag Dumper \@unmatched;
};

# All snippets should contain at least one matched phrases
my @phrase;
for my $s (@snippets) {
    my $text = substr($html, $s->{start}, $s->{length});
    my $opening = () = ($text =~ m!<em>!g);
    push @phrase, [$s,$text]
        if( ! $opening );
};
if( ! is 0+@phrase, 0, "All snippets contain a phrase") {
    diag Dumper \@phrase;
};

# All snippets should be within the HTML string
my @outside = grep { $_->{start} <= 0 or $_->{end} >= length $html } @snippets;
if( ! is 0+@outside, 0, "No snippet reaches outside the HTML string") {
    diag Dumper \@outside;
};

# Collext all overlapping snippets (there shouldn't be any)
# relax this - there should not be overlaps in the matched keywords
my @overlaps;

# Unaccidentially quadratic
for my $curr (@snippets) {
    for my $other (@snippets) {
        next if $curr == $other;
        
        # $curr:       |------------|
        # $other:   |-----------|

        # Only repeat each combination once
        # by only looking at things that start within others
        push @overlaps, [$curr,$other]
            if(     $curr->{start} <= $other->{start}
                and $curr->{end} >= $other->{start}
              );
    };
};

if(! is 0+@overlaps, 0, "The snippets don't overlap") {
    for( @overlaps ) {
        my ($l,$r) = @$_;
        diag sprintf <<'OVERLAP', $l->{start},$l->{end},$r->{start},$r->{end};
    |-----------|     %d - %d
        |-----------| %d - %d
OVERLAP
        diag Dumper $_;
    };
};

# Maybe count text outside of tags?!
my @too_long = grep { $_->{length} >= 150 } @snippets;
if( ! is 0+@too_long, 0, "No snippet is too long (150 chars)") {
    diag Dumper \@too_long;
};

done_testing;