package HTML::Restricted;
use strict;
use Moo;
use HTML::TreeBuilder 5 '-weak'; # we want weak references

# Clean up HTML so it doesn't contain anything bad
# Lets through only a predefined set of HTML tags
# and a predefined set of attributes
# This also enforces properly nested HTML, thanks to TreeBuilder.

# How will we handle outside links?!

use vars qw(%allowed);

%allowed = (
    a     => ['href','name'],
    b     => 1,
    blockquote => 1,
    body  => 1,
    br    => 1,
    code  => 1,
    div   => 1,
    font  => 'color',
    h1    => 1,
    h2    => 1,
    h3    => 1,
    h4    => 1,
    html  => 1,
    hr    => 1,
    i     => 1,
    img   => ['src'],
    li    => 1,
    ol    => 1,
    p     => 1,
    pre   => 1,
    span  => 1,
    table => 1,
    tbody => 1,
    td    => 1,
    th    => 1,
    tr    => 1,
    tt    => 1,
    ul    => 1,
);

has tree_class => (
    is => 'rw',
    default => 'HTML::TreeBuilder',
);

has contents => (
    is => 'ro',
    default => sub { +{ %contents } },
);

has allowed => (
    is => 'ro',
    default => sub { +{ %allowed } },
);

sub filter_element {
    my( $self, $doc, $elt ) = @_;
    if( my $attrs = $self->allowed->{ lc $elt->tag } ) {
        # Strip the attributes except for allowed attributes
        $attrs = [] if ! ref $attrs;
        my %aa = map { $_ => 1 } @$attrs;
        for my $name ($elt->all_external_attr_names) {
            warn $name;
            $elt->attr($name => undef)
                unless $aa{ lc $name };
        };
        
        # Recurse into children
        for my $child ($elt->content_list) {
            next unless ref $child;
            $self->filter_element($doc, $child);
        };
    } elsif( $self->contents->{ lc $elt->tag } ) {
        # Replace with its contents

        for my $child ($elt->content_list) {
            next unless ref $child;
            $self->filter_element($doc, $child);
        };
        
        $elt->replace_with($elt->content_list);
    } else {
        print sprintf "%s: removed\n", $elt->tag;
        $elt->delete;
    };
}

sub filter {
    my( $self, $html ) = @_;

    # We should also allow for a premade tree getting passed in here
    my $t = $self->tree_class->new;
    $t->parse($html);
    $t->eof;
    
    $self->filter_element( $t, $t->root );
    $t
}

1;