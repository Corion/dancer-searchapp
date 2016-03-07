package Dancer::SearchApp::IndexSchema;
use strict;
use Exporter 'import';
use Data::Dumper;
use Promises 'deferred';

use JSON::MaybeXS;
my $true = JSON->true;
my $false = JSON->false;

=head1 NAME

Dancer::SearchApp::IndexSchema - schema definition for the Elasticsearch index

=cut

use vars qw(@EXPORT_OK $VERSION);
$VERSION = '0.01';
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

=head2 C<< create_mapping >>

Defines a Dancer::SearchApp index. This is currently the following
specification:

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

=cut

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

=head2 C<< find_or_create_index >>

  my $found = find_or_create_index( $es, $index_name, $lang, $type );
  $found->then( sub {
      my( $name ) = @_;
      print "Using index '$name'\n";
  });

Returns the full name for the index C<$index_name>, concatenated with the
language. The language is important to chose the correct stemmer. Existing
indices will be cached in the package global variable C<%indices>.

=cut

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