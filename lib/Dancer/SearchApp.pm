package Dancer::SearchApp;
use strict;
use File::Basename;
#use Dancer ':syntax';
use Dancer;
use Search::Elasticsearch::Async;
use URI::Escape 'uri_unescape';
use URI::file;
#use Search::Elasticsearch::TestServer;
#use Promises;

use Dancer::SearchApp::Entry;

use vars qw($VERSION $es $server);

$VERSION = '0.01';

=head1 NAME

Dancer::SearchApp - A simple local search engine

=head1 SYNOPSIS

    plackup ...

=cut

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

sub search {
    if( ! $es ) {
        #my $nodes;
        #if( config->{elastic_search}) {
        #    my $es_home = config->{elastic_search}->{home};
        #    warning "Starting local ElasticSearch instance in $es_home";
        #    $server ||= Search::Elasticsearch::TestServer->new(
        #        es_home   => $es_home,
        #    );

            #$nodes = $server->start;
        #};
        $es = Search::Elasticsearch->new(
            nodes => config->{nodes} || [],
        );
    };
    
    $es
};

$Template::Stash::PRIVATE = 1;

get '/' => sub {
    # Later, separate out the code paths between
    # search and index page only, to serve the index
    # page as a static file
    
    my $statistics;
    my $results;
    
    my $from = params->{'from'};
    $from =~ s!\D!!g;
    my $size = params->{'size'};
    $size =~ s!\D!!g;
    $size ||= 10;
    
    if( defined params->{'q'}) {
        
        warning "Reading ES indices\n";
        use vars '%indices';
        %indices = %{ search->indices->get({index => ['*']}) };
        warning $_ for sort keys %indices;

        # Move this to an async query, later
        my $search_term = params->{'q'};
        my $index = config->{elastic_search}->{index};
        $results = search->search(
            # Wir suchen in allen Sprachindices
            index => [ grep { /^\Q$index\E/ } sort keys %indices ],
            body => {
                from => $from,
                size => $size,
                query => {
                    query_string => {
                        query => $search_term,
                        fields => ['title','content', 'author'] #'creation_date'] 
                    },
                },
                sort => {
                    _score => { order => 'desc' },
                },
               "highlight" => {
                    "pre_tags" => '<b>',
                    "post_tags" => '</b>',
                    "fields" => {
                        "content" => {}
                    }
                }
            }
        );
        
        #warn Dumper $results->{hits};
    } else {
        # Update the statistics
        $statistics = search->search(
            search_type => 'count',
            index => config->{index},
            body        => {
                query       => {
                    match_all => {}
                }
            }
        );
        warn Dumper $statistics;
    };
    
    for( @{ $results->{ hits }->{hits} } ) {
        $_->{source} = Dancer::SearchApp::Entry->from_es( $_ );
        for my $key ( qw( id index type )) {
            $_->{$key} = $_->{"_$key"}; # thanks, Template::Toolkit
        };
        
    };
    
    # Output the search results
    template 'index', {
            results => $results->{hits},
            params => {
                q=> params()->{q},
                from => params()->{from},
                size => params->{size}
            },
    };
};

sub retrieve {
    my( $index, $type, $id ) = @_;
    my $document;
    if( eval {
        $document = search->get(index => $index, type => $type, id => $id);
        1
    }) {
        my $res = Dancer::SearchApp::Entry->from_es($document);
        return $res
    } else {
        warn "$@";
    };
    # Not found in the Elasticsearch index
    return undef
}

# Show (cached) elements
get '/cache/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape( params->{id} );
    my $document = retrieve($index,$type,$id);
    warn $document->basic_mime_type;
    
    $document->{type} = $type;
    $document->{index} = $index;
    
    if( $document ) {
        return template 'view_document', {
            result => $document,
            backlink => scalar( request->referer ),
        }
    } else {
        status 404;
        return <<SORRY
        That file does (not) exist anymore in the index.
SORRY
        # We could delete that item from the index here...
        # Or schedule reindexing of the resource?
    }
};

# Reproxy elements from disk
sub reproxy {
    my( $document, $local, $disposition, %options ) = @_;
    
    # Now, if the file exists both in the index and locally, let's reproxy the content
    if( $document and -f $local) {
        status 200;
        content_type( $document->mime_type );
        header( "Content-Disposition" => sprintf '%s; filename="%s"', $disposition, basename $local);
        my $abs = File::Spec->rel2abs( $local, '.' );
        open my $fh, '<', $local
            or die "Couldn't read local file '$local': $!";
        binmode $fh;
        local $/;
        <$fh>
        
    } else {
        status 404; # sorry
        return <<SORRY
        That file does (not) exist anymore or is currently unreachable
        for this webserver. We'll need to implement 
        cleaning up the index from dead items.
SORRY
        # We could delete that item from the index here...
        # Or schedule reindexing of the resource?
    }
};

get '/open/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape params->{id};
    my $document = retrieve($index,$type,$id);
    my $local = URI::file->new( $id )->file;
    
    reproxy( $document, $local, 'Attachment',
        index => $index,
        type => $type,
    );
    
};

get '/inline/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape params->{id};
    my $document = retrieve($index,$type,$id);
    my $local = URI::file->new( $id )->file;
    
    reproxy( $document, $local, 'Inline',
        index => $index,
        type => $type,
    );
    
};

true;
