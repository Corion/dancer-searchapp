package Dancer::SearchApp::IndexSchema;
use strict;
use Exporter 'import';
use Data::Dumper;
use Promises 'deferred';

use JSON::MaybeXS;
my $true = JSON->true;
my $false = JSON->false;

use vars '@EXPORT_OK';
@EXPORT_OK = qw(create_mapping multilang_text find_or_create_index %indices %analyzers );

# Datenstruktur für ES Felder, deren Sprache wir nicht kennen
sub multilang_text($$) {
    my($name, $analyzer)= @_;
    return { 
          "type" => "multi_field",
          "fields" =>  {
               $name => {
                   "type" => "string",
                   "analyzer" => $analyzer,
                   "index" => "analyzed",
                     "store" => $true,
               },
               #"${name}_raw" => {
               #     "type" => "string",
               #     "index" => "not_analyzed",
               #      "store" => $true,
               #},
          }
    };
};

sub create_mapping {
    my( $analyzer ) = @_;
    $analyzer ||= 'english';
    my $mapping = {
        "properties" => {
            "url"        => { type => "string" }, # file://-URL
            "title"      => multilang_text('title',$analyzer),
            "author"     => multilang_text('author', $analyzer),
            "content"    => multilang_text('content',$analyzer),
            'mime_type'  => { type => "string" }, # text/html etc.
            "creation_date"    => {
              "type"  =>  "date",
              "format" => "yyyy-MM-dd kk:mm:ss", # yay for Joda, yet-another-timeparser-format
            },
        },
    };
};

use vars qw(%pending_creation %indices %analyzers );
sub find_or_create_index {
    my( $e, $index_name, $lang, $type ) = @_;
    
    my $res = deferred;
    
    my $full_name = "$index_name-$lang";
    #warn "Initializing deferred for $full_name";
    #warn join ",", sort keys %indices;
    if( ! $indices{ $full_name }) {
        #warn "Checking for '$full_name'";
        $e->indices->exists( index => $full_name )
        ->then( sub{
            if( $_[0] ) { # exists
                #warn "Full name: $full_name";
                $res->resolve( $full_name );

            # index creation in progress
            } elsif( $pending_creation{ $full_name }) {
                #warn "push Pending";
                push @{ $pending_creation{ $full_name } }, $res;

            # we need to create it ourselves
            } else {
                $pending_creation{ $full_name } = [];
                #warn "Creating";
                my $mapping = create_mapping($analyzers{$lang});
                #warn Dumper $mapping;
                $e->indices->create(index=>$full_name,
                    body => {
                    settings => {
                        mapper => { dynamic => $false }, # this is "use strict;" for ES
                        "number_of_replicas" => 0,
                        #"analysis" => {
                        #    "analyzer" => $analyzers{ $lang }
                        #},
                    },
                    "mappings" => {
                        # Hier muessen/sollten wir wir die einzelnen Typen definieren
                        # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html
                        $type => $mapping,
                    },
                })->then(sub {
                    my( $created ) = @_;
                    #warn "Full name: $full_name";
                    $res->resolve( $full_name );
                    for( @{ $pending_creation{ $full_name }}) {
                        $_->resolve( $full_name );
                    };
                    delete $pending_creation{ $full_name };
                }, sub { warn "Couldn't create index $full_name: " . Dumper \@_});
            };
        });
    } else {
        #warn "Cached '$full_name'";
        $res->resolve( $full_name );
    };
    return $res->promise
};

1;