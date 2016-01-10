package Dancer::SearchApp;
use Dancer ':syntax';
use Search::Elasticsearch;
#use Search::Elasticsearch::TestServer;
#use Promises;

use vars qw($VERSION $es $server);

$VERSION = '0.01';

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
        my $index = config->{index};
        $results = search->search(
            # Wir suchen in allen Sprachindices
            index => [ grep { /\Q$index\E/ } sort keys %indices ],
            body => {
                from => $from,
                size => $size,
                query => {
                    query_string => {
                        query => $search_term,
                        fields => ['subject','content', 'language', 'content.language', 'content.de', 'de', ], # 'date', 'language' 
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
        
        warn Dumper $results->{hits};
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
        for my $key ( qw( source id )) {
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

true;
