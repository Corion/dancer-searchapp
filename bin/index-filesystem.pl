#!perl -w
use strict;
use AnyEvent;
use Search::Elasticsearch::Async;
use Promises qw[collect deferred];

use Getopt::Long;

use MIME::Base64;

use Data::Dumper;
use YAML 'LoadFile';

use Path::Class;
use URI::file;
use POSIX 'strftime';

use Dancer::SearchApp::Defaults 'get_defaults';
use Dancer::SearchApp::IndexSchema qw(create_mapping find_or_create_index %indices %analyzers );
use Dancer::SearchApp::Utils qw(await);
use Dancer::SearchApp::Extractor;

#use lib 'C:/Users/Corion/Projekte/Apache-Tika/lib';
use CORION::Apache::Tika::Server;

use JSON::MaybeXS;
my $true = JSON->true;
my $false = JSON->false;

=head1 USAGE

  # index a directory and its subdirectories
  index-filesytem.pl $HOME
  
  # Use defaults from ./fs-import.yml
  index-filesystem.pl -c ~/myconfig.yml

  # Drop and recreate index:
  index-filesystem.pl -f ./fs-import.yml

=cut

GetOptions(
    'force|f' => \my $force_rebuild,
    'config|c' => \my $config_file,
    # How can we easily pass the options for below as command line parameters?!
);
$config_file ||= 'fs-import.yml';

my $file_config = LoadFile($config_file);

my $config = get_defaults(
    env      => \%ENV,
    config   => $file_config,
    #defaults => \%
    names => [
        ['elastic_search/index' => 'elastic_search/index' => 'SEARCHAPP_ES_INDEX', 'dancer-searchapp'],
        ['elastic_search/nodes' => 'elastic_search/nodes' => 'SEARCHAPP_ES_NODES', 'localhost:9200'],
    ],
);

my $index_name = $config->{elastic_search}->{index};

my $e = Search::Elasticsearch::Async->new(
    nodes => [
        $config->{elastic_search}->{nodes},
    ],
    plugins => ['Langdetect'],
);

my $extractor = 'Dancer::SearchApp::Extractor';

my $tika_glob = 'C:/Users/Corion/Projekte/Apache-Tika/jar/tika-server-*.jar';
my $tika_path = (sort { my $ad; $a =~ /server-1.(\d+)/ and $ad=$1;
                my $bd; $b =~ /server-1.(\d+)/ and $bd=$1;
                $bd <=> $ad
              } glob $tika_glob)[0];
die "Tika not found in '$tika_glob'" unless -f $tika_path; 
#warn "Using '$tika_path'";
my $tika= CORION::Apache::Tika::Server->new(
    jarfile => $tika_path,
);
$tika->launch;

my $ok = AnyEvent->condvar;
my $info = await $e->cat->plugins;

# Koennen wir ElasticSearch langdetect als Fallback nehmen?
my $have_langdetect = $info =~ /langdetect/i;
if( ! $have_langdetect ) {
    warn "Language detection disabled";
};

# https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-lang-analyzer.html

use vars qw(%analyzers);

%analyzers = (
    'de' => 'german',
    'en' => 'english',
    'no' => 'norwegian',
    'it' => 'italian',
    'lt' => 'lithuanian',
    'ro' => 'english', # I don't speak "romanian"
    'sk' => 'english', # I don't speak "serbo-croatian"
);

if( $force_rebuild ) {
    print "Dropping indices\n";
    my @list;
    await $e->indices->get({index => ['*']})->then(sub{
        @list = grep { /^\Q$index_name/ } sort keys %{ $_[0]};
    });

    await collect( map { my $n=$_; $e->indices->delete( index => $n )->then(sub{warn "$n dropped" }) } @list )->then(sub{
        warn "Index cleanup complete";
        %indices = ();
    });
};

print "Reading ES indices\n";
await $e->indices->get({index => ['*']})->then(sub{
    %indices = %{ $_[0]};
});

warn "Index: $_\n" for grep { /^\Q$index_name/ } keys %indices;

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
        
        #if( ! exists $folderspec->{exclude} ) {
        #    # By default, exclude hidden files
        #    $folderspec->{exclude} = [qr/^\./];
        #};
        if( ! ref $folderspec ) {
            # plain name, use this folder
            push @folders, dir($folderspec)
            
        } else {
            my $dir = dir($folderspec->{folder});
            push @folders, $dir;
            $folderspec->{exclude} ||= [];
            if( $folderspec->{recurse}) {
                # Recurse through this tree
                warn "Recursing into '$dir'";
                my @child_folders;
                my $p;
                if( $folderspec->{recurse} ) {
                    @child_folders = grep { $_->is_dir } $dir->children;
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
    # Add rate-limiting counter here, so we don't flood
    
    my @directories = eval { $folder->children() };
    if( $@ ) {
        warn "Skipped $folder, no permissions\n";
    };
    
    return grep { !$_->is_dir and ! /^\./ } @directories;
};


sub get_file_info {
    my( $file ) = @_;
    my %res;
    my $url = URI::file->new( $file )->as_string;
    $res{ folder } = "" . $file->dir;
    $res{ folder } =~ s![\\/ ]! !g;
    
    eval {
        $info = $tika->get_all( $file );
    };
    if( $@ ) {
        # Einfach so indizieren
        $res{ title } = $file->basename;
        $res{ author } = undef;
        $res{ language } = undef;
        $res{ content } = undef;
    } else {
    
        my $meta = $info->meta;
        $res{ mime_type } = $meta->{"Content-Type"};
        
        my @info = await $extractor->examine(
              url => $url,
              info => $info,
              #content => \$content, # if we have it
              filename => $file, # if we have it
              folder => $res{ folder }, # if we have it
        );
        
        # This should be general dispatching
        # so the IMAP import can benefit from that
        if( @info ) {
            # generate an "HTML" page for the file
            # These special pages should be named "cards"
            %res = %{$info[ 0 ]}; # just take the first item ...
            
        } else {
            
            # Just use what Tika found

            use HTML::Restricted;            
            my $p = HTML::Restricted->new();
            my $r = $p->filter( $info->content );

            $res{ title } = $meta->{"meta:title"} || $file->basename;
            $res{ author } = $meta->{"meta:author"}; # as HTML
            $res{ language } = $meta->{"meta:language"};
            $res{ content } = $r->as_HTML; # as HTML
        }
    }
    
    my $ctime = (stat $file)[10];
    $res{ creation_date } = strftime('%Y-%m-%d %H:%M:%S', localtime($ctime));
    $res{ url } ||= "$file";
    \%res
}

my $ld = $e->langdetect;
sub detect_language {
    my( $content, $meta ) = @_;
    my $res;
    $have_langdetect = 0;
    if($have_langdetect and ! $meta->{language}) {
        $res = $ld->detect_languages({ body => $content })
        ->then( sub {
            my $l = $_[0]->{languages}->[0]->{language};
            warn "Language detected: $l";
            return $l
        }, sub {
            my $default = $config->{default_language} || 'en';
            warn "Error while detecting language: $_[0], defaulting to '$default'";
            return $default
        });
    } else {
        $res = deferred;
        $res->resolve( $meta->{language} || $config->{default_language} || 'en');
        $res = $res->promise
    }
    $res
}

sub url_stored {
}

if( @ARGV) {
    $config->{fs}->{directories} = [@ARGV];
};

if( ! @ARGV ) {
    # If we don't know better, scan the (complete) profile
    my $userhome = $ENV{USERPROFILE} || $ENV{HOME};
    $config->{fs}->{directories} = [{ folder => $userhome, recurse => 1 }];
}

my @folders = fs_recurse(undef, $config->{fs});
for my $folder (@folders) {
    my @entries;
    print "Reading $folder\n";
    push @entries, map {
        # analyze file
        # recurse into file parts for (ZIP) archives?!
        # SHA1
        get_file_info($_)
    } get_entries_from_folder( $folder );

    my $done = AnyEvent->condvar;

    # Importieren
    print sprintf "Importing %d files\n", 0+@entries;
    collect(
        map {
            my $msg = $_;
            my $body = $msg->{content};
            
            # Stringify some fields that are prone to be objects:
            for(qw(file url)) {
                if( $msg->{$_} ) {
                    $msg->{ $_} = "$msg->{$_}";
                };
            };
            
            my $lang = detect_language($body, $msg);
            
            $lang->then(sub{
                my $found_lang = $_[0]; #'en';
                #warn "Have language '$found_lang'";
                return find_or_create_index($e, $index_name,$found_lang, 'file')
            })
            ->then( sub {
                my( $full_name ) = @_;
                #warn $msg->{mime_type};
                # https://www.elastic.co/guide/en/elasticsearch/guide/current/one-lang-docs.html
                #warn "Storing document into $full_name";
                $e->index({
                        index   => $full_name,
                        type    => 'file', # or 'attachment' ?!
                        id      => $msg->{url}, # we want to overwrite
                        # index bcc, cc, to, from
                        body    => $msg # "body" for non-bulk, "source" for bulk ...
                        #source    => $msg
                 });
               })->then(sub{
                   #warn "Done."
               }, sub {warn $_ for @_ });
       } @entries
    )->then(sub {
        print "$folder done\n";
        $done->send;
    });
    
    $done->recv;
    #$importer->flush;
};
#$importer->flush;
