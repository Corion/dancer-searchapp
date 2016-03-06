package Dancer::SearchApp::IndexSchema;
use strict;
use Exporter 'import';

use JSON::MaybeXS;
my $true = JSON->true;
my $false = JSON->false;

use vars '@EXPORT_OK';
@EXPORT_OK = qw(create_mapping multilang_text);

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

1;