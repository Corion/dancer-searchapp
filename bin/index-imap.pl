#!perl -w
use strict;
#use Search::Elasticsearch::Async;
#use Promises backend => ['AnyEvent'];
use Mail::IMAPClient;
use Search::Elasticsearch;
use Search::Elasticsearch::Bulk;
use Getopt::Long;
use Mail::IMAPClient;

use lib '../App-ImapBlog/lib';
use App::ImapBlog::Entry;
use MIME::Base64;
use Mail::Clean 'clean_subject';
use Text::CleanFragment 'clean_fragment';

use Data::Dumper;
use YAML 'LoadFile';

GetOptions(
    'force|f' => \my $force_rebuild,
    'config|c' => \my $config_file,
);
$config_file ||= 'imap-import.yml';

# Connect to localhost:9200:

#my $e = Search::Elasticsearch::Async->new();

# Round-robin between two nodes:

my $config = LoadFile($config_file)->{imap};

my $index_name = 'elasticsearch';

my $e = Search::Elasticsearch->new(
    nodes => [
        'localhost:9200',
        #'search2:9200'
    ]
);

if( $force_rebuild ) {
    $e->indices->delete( index => $index_name );
};

# Datenstruktur für ES Felder, deren Sprache wir nicht kennen
sub multilang_text() {
    my $multilang_text = { 
          "type" => "string",
          "fields" =>  {
                 # subject.en
                "en" => { 
                  "type" =>     "string",
                  "analyzer" => "english"
                },
                 # subject.de
                "de" => { 
                  "type" =>     "string",
                  "analyzer" => "light_german"
                }
        }
    };
};

if( ! $e->indices->exists( index => $index_name )) {
    $e->indices->create(index=>$index_name,
    #$e->indices->put_settings( index => $index_name,
        body => {
        "index" => {
            "number_of_replicas" => 0,
            "analysis" => {
                "analyzer" => {
                    # Der sollte dynamisch Englisch und Deutsch koennen!
                    "mail_analyzer" => {
                        "tokenizer" => "standard",
                        "filter" => ["standard", "lowercase", "de_stemmer"]
                    }
                },
                "mappings" => {
                    # Hier muessen/sollten wir wir die einzelnen Typen definieren
                    # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html
                    "mail" => {
                        "properties" => {
                            "messageid" => "string", # fuer die URL spaeter... sollte das in _id?!
                            "subject" => multilang_text(),
                            "body"    => multilang_text(),
                            "date"    => "date",
                            "from"    => { type => "string" },
                            "to"      => { type => "string" }, # eigentlich Liste...
                            
                      },
                    },
                },
          "filter" => {
                    "de_stemmer" => {
                        "type" => "stemmer",
                        "name" => "light_german"
                    },
                    # Synonyme sollten aus einer Datei kommen
                    # synonym_path statt synonyms
                    # https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-synonym-tokenfilter.html
                    "synonym" => {
                        "type" => "synonym",
                        "synonyms" => [
                            "i-pod, i pod => ipod",
                            "universe, cosmos"
                        ]
                    }
            }
        }
        }
    });
};

# Connect to cluster at search1:9200, sniff all nodes and round-robin between them:

#my $e = Search::Elasticsearch::Async->new(
#    nodes    => 'search1:9300',
#    cxn_pool => 'Async::Sniff'
#);

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

use vars qw($imap $config);
sub imap() {
    return $imap if $imap and $imap->IsConnected;
    
    my %imap_config = %{ get_defaults(
        config => $config,
        names => [
            [ Server   => 'server'   => IMAP_SERVER => 'localhost' ],
            [ Port     => 'port'     => IMAP_PORT => '993' ],
            [ User     => 'username' => IMAP_USER  => ],
            [ Password => 'password' => IMAP_PASSWORD => ],
            [ Debug    => 'debug'    => IMAP_DEBUG => ],
        ],
    ) };
    
    use IO::Socket::SSL;
    #$IO::Socket::SSL::DEBUG = 3; # all
    my $socket = IO::Socket::SSL->new
      (  Proto    => 'tcp',
         PeerAddr => $imap_config{ Server },
         PeerPort => $imap_config{ Port },
         SSL_verify_mode => SSL_VERIFY_NONE, # Yes, I know ...
      ) or die "No socket to $imap_config{ Server }:$imap_config{ Port }";

CONNECT:
    my $retry = 0;
    $imap = Mail::IMAPClient->new(
        #%imap_config,
        User => $imap_config{ User },
        Password => $imap_config{ Password },
        Socket   =>  $socket,
        #Ssl      => 1,
        Uid      => 1,
    ) or die sprintf "Can't connect to server '%s': %s",
        $config->{'server'}, "$@";
        
    if( !$imap->IsConnected and $retry++ < 5 ) {
        sleep 1;
        warn "Retrying";
        goto CONNECT;
    };
    
    if( $retry == 5 ) {
        exit 1;
    };
    $imap
};

sub in_exclude_list {
    my( $item, $list ) = @_;
    scalar grep { $item =~ /$_/ } @$list
};

# This should go into crawler::imap
sub imap_recurse {
    my( $imap, $config ) = @_;

    my @folders;
    for my $folderspec (@{$config->{folders}}) {
        if( ! ref $folderspec ) {
            # plain name, use this folder
            push @folders, $folderspec
        } else {
            if( $folderspec->{recurse}) {
                # Recurse through this tree
                $folderspec = $folderspec->{recurse};
                warn "Recursing into '$folderspec->{prefix}'";
                $folderspec->{exclude} ||= [];
                my @imap_folders;
                if( $folderspec->{prefix} ne '' ) {
                    @imap_folders = imap->folders_hash( $folderspec->{prefix} );
                } else {
                    @imap_folders = imap->folders_hash();
                };
                @imap_folders = grep { ! in_exclude_list( $_->{name}, $folderspec->{exclude} ) }
                    @imap_folders;
                push @folders, map { $_->{name} } @imap_folders;
            };
        };
    };
    
    @folders
};

sub get_messages_from_folder {
    my( $folder, @message_uids )= @_;
    # XXX Add rate-limiting counter here, so we don't flood the IMAP server
    #     with reconnect attempts
    my $ok = eval {
        imap->select( $folder )
            or die "Select '$folder' error: ", $imap->LastError, "\n";
        1;
    };
    if( ! $ok and $@ =~ /Write failed/) {
        # Try a reconnect
        undef $imap;
        imap->select( $folder )
            or die "Select '$folder' error: ", $imap->LastError, "\n";
    };

    if( ! @message_uids ) {
        # Read folder
        if( imap->has_capability('thread')) {
            @message_uids = imap->thread();
        } elsif( imap->has_capability('sort')) {
            @message_uids = imap->sort("REVERSE DATE", 'UTF-8', "ALL");
            if(! defined $message_uids[0]) {
                warn "Got an empty UID, don't know why?! " . imap->LastError;
            };
        } else {
            # read messages
            @message_uids = imap->messages();
        };
    };
    return @message_uids;
};

use App::ImapBlog::Entry;
my @folders = imap_recurse(imap, $config);
my $importer = $e->bulk_helper();
for my $folder (@folders) {
    my @messages;
    print "Reading $folder\n";
    push @messages, map {
        App::ImapBlog::Entry->from_imap_client(imap(), $_);
    } get_messages_from_folder( $folder );

    # Importieren
    print sprintf "Importing %d messages\n", 0+@messages;
    for my $msg (@messages) {
        my $body = $msg->body;
        $importer->index({
                index   => $index_name,
                type    => 'mail', # or 'attachment' ?!
                #id      => $msg->messageid,
                id      => $msg->uid,
                # index bcc, cc, to, from
                # content-type, ...
                # body    => { # "body" for non-bulk
                source    => {
                    messageid => $msg->messageid,
                    subject => $msg->subject,
                    from    => $msg->from,
                    to      => [ $msg->recipients ],
                    content => $body,
                    date    => $msg->date->strftime('%Y-%m-%d %H:%M:%S'),
                }
       });
    };
    $importer->flush;
};
$importer->flush;
