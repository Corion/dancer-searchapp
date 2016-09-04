package Dancer::SearchApp::HTMLSnippet;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use HTML::Restrict;

=head2 C<< Dancer::SearchApp::HTMLSnippet->extract_highlights >>

    my @document_snippets = Dancer::SearchApp::HTMLSnippet->extract_highlights(
        html => $html,
        hl_tag => '<em>',
        hl_end => '</em>',
        snippet_length => 150,
        max_snippets => 8,
    );

This extract the highlight snippets and metadata from the HTML
as prepared by Tika and highlightedd by Elasticsearch. It
returns a list of hash references, each containing a (well-formed)
HTML snippet containing the highlights and a C<page> entry
noting the original page number if the snippet originated from
within a C<< <p class="page\d+"> >> section (or crosses that)

  {
      html => 'this is a <b>result</b> you searched for',
      page => 42,
  }

=cut

sub make_snippet( $html, $from, $to, $max_length ) {
    my $start = $from->{start};
    my $end = $to->{end};
    my $fudge = int(( $max_length - ($end-$start)) / 2);
    
    # We want to start at something akin to a word boundary
    if( substr($html,$start-$fudge-1,$fudge+2) =~ /\s+(.*)$/ ) {
        $start-= length($1)
    };

    $fudge = $max_length - ($end-$start);
    $end += length($1)
        if( substr($html,$end,$fudge) =~ /(.*)\s+/ );
    
    return +{
         start  => $start,
         end    => $end,
         length => $end-$start,
    };
};

sub extract_highlights( $class, %options ) {
    $options{ max_snippets } ||= 8;
    $options{ max_length } ||= 150;
    $options{ hl_tag } ||= '<em>';
    $options{ hl_end } ||= '</em>';
    my $html = $options{ html };
    my @highlights;
    while( $html =~ /(\Q$options{hl_tag}\E(.*?)\Q$options{hl_end}\E)/g ) {
        push @highlights, {
            start  => pos($html)-length($1),
            # Maybe count text outside of tags instead?!
            length => length($1),
            end    => pos($html),
            word   => "$1",
        };
    };
    
    # Now, find the first matches (hardcoded, instead of finding the 
    # best snippets in the document)
    
    my @snippets;
    
    if( @highlights ) {
        # We can stop once we are by
        my $last = $highlights[-1]->{start};
        my $curr = 0;
        my $gather = 0;
        while(     @snippets < $options{ max_snippets }
               and ($curr+$gather) < @highlights
             ) {
            # gather up as many highlights as fit for the next snippet
            my $snippet_length =   $highlights[$curr+$gather]->{end}
                                 - $highlights[$curr]->{start}
                                 ;
            if( $snippet_length < $options{ max_length }) {
                $gather++

            } else {
                # Snippet got too long
                # XXX readjust / center the snippet on the match(es)
                push @snippets,
                  make_snippet( $html,
                                $highlights[$curr],
                                $highlights[$curr+$gather-1],
                                $options{ max_length });
                $curr += $gather;
                $gather = 0;
            };
        };
        
        if( ! @snippets) {
                push @snippets,
                  make_snippet( $html,
                                $highlights[$curr],
                                $highlights[$curr],
                                $options{max_length});
        };
    };
    
    @snippets
}

sub cleanup_tika( $class, $html ) {
    my $p = HTML::Restrict->new(
    #    rules => { div => ['class'], },
        rules => {
            #p     => ['class'],
            div   => ['class', { class => qr/^page$/i }],
            table => [],
            tbody => [],
            thead => [],
            tr    => [],
            td    => [],
            a     => [],
            ul    => [],
            ol    => [],
            li    => [],
        },
        replace_img => 1,
        strip_enclosed_content => [ 'script', 'style', 'head' ]
    );
        
    # rewrite the HTML to have the page numbers!
    # Later
my $r = $p->process($html);
#warn $r;
    return $r
}

1;