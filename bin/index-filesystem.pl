#!perl -w
use strict;
use AnyEvent;
use Search::Elasticsearch::Async;
use Promises qw[collect deferred];

use Getopt::Long;

use MIME::Base64;
use Text::CleanFragment 'clean_fragment';

use Data::Dumper;
use YAML 'LoadFile';

use Path::Class;
use URI::file;
use POSIX 'strftime';

use JSON::MaybeXS;
my $true = JSON->true;
my $false = JSON->false;

GetOptions(
    'force|f' => \my $force_rebuild,
    'config|c' => \my $config_file,
);
$config_file ||= 'fs-import.yml';

my $config = LoadFile($config_file)->{fs};

my $index_name = 'dancer-searchapp';

my $e = Search::Elasticsearch::Async->new(
    nodes => [
        'localhost:9200',
        #'search2:9200'
    ],
    plugins => ['Langdetect'],
    #trace_to => 'Stderr',
);

# Helper to do synchronous calls
sub synchronous($) {
    my $await = AnyEvent->condvar;
    my $promise = $_[0];
    $_[0]->then(sub{ $await->send($_[0])});
    $await->recv
};

my $ok = AnyEvent->condvar;
my $info = synchronous $e->cat->plugins;

my $have_langdetect = $info =~ /langdetect/i;
if( ! $have_langdetect ) {
    warn "Language detection disabled";
};

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
               "raw" => {
                    "type" => "string",
                    "index" => "not_analyzed",
                     "store" => $true,
               },
        }
    };
};

sub create_mapping {
    my( $analyzer ) = @_;
    my $mapping = {
        "properties" => {
            "url"        => { type => "string" }, # file://-URL
            "subject"    => multilang_text('subject',$analyzer),
            "content"    => multilang_text('content',$analyzer),
            "date"    => {
              "type"  =>  "date",
              "format" => "yyyy-MM-dd kk:mm:ss", # yay for Joda, yet-another-timeparser-format
            },
        },
    };
};

# https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-lang-analyzer.html

use vars qw(%analyzers %indices);

%analyzers = (
    'de' => 'german',
    'en' => 'english',
    'ro' => 'english', # I don't speak "romanian"
);

if( $force_rebuild ) {
    print "Dropping indices\n";
    my @list;
    my $indices_done = AnyEvent->condvar;
    $e->indices->get({index => ['*']})->then(sub{
        @list = grep { /^\Q$index_name/ } sort keys %{ $_[0]};
        $indices_done->send;
    });
    $indices_done->recv;

    my $deletion_done = AnyEvent->condvar;
    collect( map { $e->indices->delete( index => $_ ) } @list )->then(sub{
        %indices = ();
        $deletion_done->send
    });
    $deletion_done->recv;
};

print "Reading ES indices\n";
my $indices_done = AnyEvent->condvar;
$e->indices->get({index => ['*']})->then(sub{
    %indices = %{ $_[0]};
    $indices_done->send;
});
$indices_done->recv;

warn "Index: $_\n" for keys %indices;

my %pending_creation;
sub find_or_create_index {
    my( $index_name, $lang ) = @_;
    
    my $res = deferred;
    my $done = AnyEvent->condvar;
    
    my $full_name = "$index_name.$lang";
    #warn "Initializing deferred for $full_name";
    #warn join ",", sort keys %indices;
    if( ! $indices{ $full_name }) {
        #warn "Checking for '$full_name'";
        $e->indices->exists( index => $full_name )
        ->then( sub{
            if( $_[0] ) { # exists
                $res->resolve( $full_name );
            } elsif( $pending_creation{ $full_name }) {
                    # index creation in progress
                    push @{ $pending_creation{ $full_name } }, $res;
            } else {
                # we need to create it ourselves
                $pending_creation{ $full_name } = [];
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
                        "file" => create_mapping($analyzers{$lang}),
                    },
                })->then(sub {
                    my( $created ) = @_;
                    $res->resolve( $full_name );
                    for( @{ $pending_creation{ $full_name }}) {
                        $_->resolve( $full_name );
                    };
                    delete $pending_creation{ $full_name };
                });
            };
        });
    } else {
        #warn "Cached '$full_name'";
        $res->resolve( $full_name );
    };
    return $res->promise
};

# Connect to cluster at search1:9200, sniff all nodes and round-robin between them:

# Lame-ass config cascade
# Read from %ENV, $config, hard defaults, with different names,
# write to yet more different names
# Should merge with other config cascade
sub get_defaults {
    my( %options ) = @_;
    $options{ defaults } ||= {}; # premade defaults
    
    my @names = @{ $options{ names } };
    if( ! exists $options{ env }) {
        $options{ env } = \%ENV;
    };
    my $env = $options{ env };
    my $config = $options{ config };
    
    for my $entry (@{ $options{ names }}) {
        my ($result_name, $config_name, $env_name, $hard_default) = @$entry;
        if( defined $env_name and exists $env->{ $env_name } ) {
            #print "Using $env_name from environment\n";
            $options{ defaults }->{ $result_name } //= $env->{ $env_name };
        };
        if( defined $config_name and exists $config->{ $config_name } ) {
            #print "Using $config_name from config\n";
            $options{ defaults }->{ $result_name } //= $config->{ $config_name };
        };
        if( ! exists $options{ defaults }->{$result_name} ) {
            print "No $config_name from config, using hardcoded default\n";
            print "Using $env_name from hard defaults ($hard_default)\n";
            $options{ defaults }->{ $result_name } = $hard_default;
        };
    };
    $options{ defaults };
};

sub in_exclude_list {
    my( $item, $list ) = @_;
    scalar grep { $item =~ /$_/ } @$list
};

# This should go into crawler::imap
# make folders a parameter
sub fs_recurse {
    my( $x, $config ) = @_;

    my @folders;

    for my $folderspec (@{$config->{directories}}) {
        if( ! ref $folderspec ) {
            # plain name, use this folder
            push @folders, dir($folderspec)
        } else {
            if( $folderspec->{recurse}) {
                # Recurse through this tree
                my $dir = $folderspec->{folder};
                warn "Scanning into '$dir'";
                $folderspec->{exclude} ||= [];
                my @child_folders;
                my $p;
                if( $folderspec->{recurse} ) {
                    @child_folders = grep { $_->is_dir } dir($dir)->children;
                };
                @child_folders = grep { ! in_exclude_list( $_, $folderspec->{exclude} ) }
                    @child_folders;
                push @folders, @child_folders;
            };
        };
    };
    
    @folders
};

sub get_entries_from_folder {
    my( $folder, @message_uids )= @_;
    # XXX Add rate-limiting counter here, so we don't flood
    
    return grep { !$_->is_dir } $folder->children();
};

sub get_file_info {
    my( $file ) = @_;
    my %res;
    $res{ url } = URI::file->new( $file )->as_string;
    $res{ subject } = $file->basename;
    $res{ language } = 'en';
    $res{ content } = do { local(@ARGV,$/)= $file; <> };
    my $mtime = (stat $file)[9];
    $res{ date } = strftime('%Y-%m-%d %H:%M:%S', localtime($mtime));
    \%res
}

my $ld = $e->langdetect;
sub detect_language {
    my( $content ) = @_;
    my $res;
    if($have_langdetect) {
        $res = $ld->detect_languages({ body => $content });
        $res->then( sub {
            my $l = $_[0]->[0]->{language};
            warn "Language detected: $l";
            $l
        });
    } else {
        $res = deferred;
        $res->resolve('en');
    }
    $res
}

if( @ARGV) {
    $config->{directories} = [@ARGV];
};
my @folders = fs_recurse(undef, $config);
for my $folder (@folders) {
    my @entries;
    print "Reading $folder\n";
    push @entries, map {
        # analyze file
        # mime type
        # File::MIMEType?
        # extract text
        # Apache::Tika?
        # recurse into file parts?!
        # SHA1
        # language
        get_file_info($_)
    } get_entries_from_folder( $folder );

    my $done = AnyEvent->condvar;

    # Importieren
    print sprintf "Importing %d messages\n", 0+@entries;
    collect(
        map {
            my $msg = $_;
            my $body = $msg->{content};
            my $lang = detect_language($body);
            
            $lang->then(sub{
                my $lang = $_[0]; #'en';
                find_or_create_index($index_name,$lang)
            })
            ->then( sub {
                my( $full_name ) = @_;
                # https://www.elastic.co/guide/en/elasticsearch/guide/current/one-lang-docs.html
                #warn "Storing document into $full_name";
                $e->index({
                        index   => $full_name, # XXX put into language-separate indices!
                        type    => 'file', # or 'attachment' ?!
                        id      => $msg->{url},
                        # index bcc, cc, to, from
                        # content-type, ...
                        body    => { # "body" for non-bulk, "source" for bulk ...
                        #source    => {
                            %$msg
                        }
                 });
               })->then(sub{ }, sub {warn $_ for @_ });
       } @entries
    )->then(sub {
        print "$folder done\n";
        $done->send;
    });
    
    $done->recv;
    #$importer->flush;
};
#$importer->flush;
