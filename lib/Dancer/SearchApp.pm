package Dancer::SearchApp;
use strict;
use File::Basename 'basename';
use Dancer;
use Search::Elasticsearch::Async;
use URI::Escape 'uri_unescape';
use URI::file;
#use Search::Elasticsearch::TestServer;

use Dancer::SearchApp::Defaults 'default_index';

use Dancer::SearchApp::Entry;

use vars qw($VERSION $es %indices);
$VERSION = '0.03';

=head1 NAME

Dancer::SearchApp - A simple local search engine

=head1 SYNOPSIS

=head1 QUICKSTART

  cpanm --look Dancer::SearchApp
  
  # Install prerequisites
  cpanm --installdeps .

  # Install Elasticsearch https://www.elastic.co/downloads/elasticsearch
  # Start Elasticsearch
  # Install Apache Tika from https://tika.apache.org/download.html into jar/

  # Launch the web frontend
  plackup --host 127.0.0.1 -p 8080 -Ilib -a bin\app.pl

  # Edit filesystem configuration
  cat >>fs-import.yml
  fs:
    directories:
        - folder: "C:\\Users\\Corion\\Projekte\\App-StarTraders"
          recurse: true
          exclude:
             - ".git"
        - folder: "t\\documents"
          recurse: true

  # Collect some content
  perl -Ilib -w bin/index-filesystem.pl -f

  # Search in your browser

=head1 CONFIGURATION

Configuration happens through config.yml

  elastic_search:
    home: "./elasticsearch-2.1.1/"
    index: "dancer-searchapp"

=cut

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

sub search {
    if( ! $es ) {
        my $nodes;
        if( $nodes = $ENV{SEARCHAPP_ES_NODES} ) {
            $nodes = [ split /;/, $nodes ];
        } else {
            $nodes = config->{nodes} || [];
        };
        $es = Search::Elasticsearch->new(
            nodes => $nodes,
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
    
    my $from = params->{'from'} || '';
    $from =~ s!\D!!g;
    $from ||= 0;
    my $size = params->{'size'} || '';
    $size =~ s!\D!!g;
    $size ||= 10;
    
    if( defined params->{'q'}) {
        
        warning "Reading ES indices\n";
        %indices = %{ search->indices->get({index => ['*']}) };
        warning $_ for sort keys %indices;

        my @restrict_type;
        my $type;
        if( $type = params->{'type'} and $type =~ m!([a-z0-9+-]+)/[a-z0-9+-]+!i) {
            #warn "Filtering for '$type'";
            @restrict_type = (filter => { term => { mime_type => $type }});
        };
        
        # Move this to an async query, later
        my $search_term = params->{'q'};
        my $index = config->{elastic_search}->{index} || default_index;
        $results = search->search(
            # Wir suchen in allen Sprachindices
            index => [ grep { /^\Q$index\E/ } sort keys %indices ],
            body => {
                from => $from,
                size => $size,
                query => {
                    filtered => {
                        query => {
                            query_string => {
                                query => $search_term,
                                fields => ['title','content', 'author'] #'creation_date'] 
                            },
                        },
                        @restrict_type,
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
        #$statistics = search->search(
        #    search_type => 'count',
        #    index => config->{index},
        #    body        => {
        #        query       => {
        #            match_all => {}
        #        }
        #    }
        #);
        #warn Dumper $statistics;
    };
    
    if( $results ) {
        for( @{ $results->{ hits }->{hits} } ) {
            $_->{source} = Dancer::SearchApp::Entry->from_es( $_ );
            for my $key ( qw( id index type )) {
                $_->{$key} = $_->{"_$key"}; # thanks, Template::Toolkit
            };
            
        };
    };
    
    # Output the search results
    template 'index', {
            results => ($results ? $results->{hits} : undef ),
            params => {
                q=> params()->{q},
                from => $from,
                size => $size,
            },
    };
};

# Show (cached) elements
get '/cache/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape( params->{id} );
    my $document = retrieve($index,$type,$id);
    #warn $document->basic_mime_type;
    
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

get '/open/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape params->{id};
    my $document = retrieve($index,$type,$id);
    if( $type eq 'http' ) {
        return
            redirect $id
    } else {
        my $local = URI::file->new( $id )->file;
        return
        reproxy( $document, $local, 'Attachment',
            index => $index,
            type => $type,
        );
    }
};

get '/inline/:index/:type/:id' => sub {
    my $index = params->{index};
    my $type = params->{type};
    my $id = uri_unescape params->{id};
    my $document = retrieve($index,$type,$id);
    
    my $local;
    if( 'http' eq $type ) {
        $document->content
    } else {
        $local = URI::file->new( $id )->file;
    };
    
    reproxy( $document, $local, 'Inline',
        index => $index,
        type => $type,
    );
    
};

true;

__END__

=head1 SECURITY CONSIDERATIONS

=head2 Dancer::SearchApp

This web front end can serve not only the extracted content but also
the original files from your hard disk. Configure the file system crawler
to index only data that you are comfortable with sharing with whoever
gets access to the web server.

Consider making the web server only respond on requests originating from
127.0.0.1:

  plackup --host 127.0.0.1 -p 8080 -Ilib -a bin\app.pl

=head2 Elasticsearch

Elasticsearch has a long history of vulnerabilities and has little to no
concept of information segregation. This basically means that anything that
can reach Elasticsearch can read all the data you stored in it.

Configure Elasticsearch to only respond to localhost or to queries from
within a trusted network, like your home network.

Note that leaking a copy of the Elasticsearch search index is almost as
bad as leaking a copy of the original data. This is especially true if you
look at backups.

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/dancer-searchapp>.

=head1 SUPPORT

The public support forum of this module is
L<https://perlmonks.org/>.

=head1 TALKS

I've given a talk about this module at Perl conferences:

L<German Perl Workshop 2016, German|http://corion.net/talks/dancer-searchapp/dancer-searchapp.html>

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Dancer-SearchApp>
or via mail to L<dancer-searchapp-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2014-2016 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut