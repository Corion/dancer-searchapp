#!perl -w
use strict;
use AnyEvent;
use Search::Elasticsearch::Async;
use Dancer::SearchApp::Defaults 'default_index';
use Promises qw[collect deferred];

use Getopt::Long;

use MIME::Base64;
use Text::CleanFragment 'clean_fragment';

use Data::Dumper;
use YAML 'LoadFile';

use Path::Class;
use URI::file;
use POSIX 'strftime';

use Dancer::SearchApp::IndexSchema qw(create_mapping find_or_create_index %indices %analyzers );
use Dancer::SearchApp::Utils qw(await);

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
);
$config_file ||= 'fs-import.yml';

my $config = LoadFile($config_file);

my $index_name = $config->{index} || default_index;
$config = $config->{fs};

my $e = Search::Elasticsearch::Async->new(
    nodes => [
        'localhost:9200',
        #'search2:9200'
    ],
    plugins => ['Langdetect'],
    #trace_to => 'Stderr',
);

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
    
    return grep { !$_->is_dir } $folder->children();
};

sub get_file_info {
    my( $file ) = @_;
    my %res;
    $res{ url } = URI::file->new( $file )->as_string;
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
        
        # This should be general dispatching
        # so the IMAP import can benefit from that
        if( $res{ mime_type } =~ m!^audio/mpeg$! ) {
            require MP3::Tag;
            my $mp3 = MP3::Tag->new($file);
            my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
            $res{ title } = $title || $file->basename;
            $res{ author } = $artist;
            $res{ language } = 'en'; # ...
            $res{ content } = join "-", $artist, $album, $track, $comment, $genre, $file->basename, 'mp3';
            # We should also calculate the duration here, and some more information
            # to generate an "HTML" page for the file
            # These special pages should be named "cards"
            
        } elsif( $res{ mime_type } =~ m!^image/.*$! ) {
            require Image::ExifTool;
            my $info = Image::ExifTool->new;
            $info->ExtractInfo("$file");
            
            $res{ title } = $info->GetValue( 'Title' ) || $file->basename;
            $res{ author } = $info->GetValue( 'Author' );
            $res{ language } = 'en'; # ...
            $res{ content } = join "-", map { $_ => $info->GetValue($_) } $info->GetFoundTags('File'), $file->basename;
            # We should also generate/store a (tiny) thumbnail here
            # to generate an "HTML" page for the file

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
    $config->{directories} = [@ARGV];
};
my @folders = fs_recurse(undef, $config);
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
    print sprintf "Importing %d messages\n", 0+@entries;
    collect(
        map {
            my $msg = $_;
            my $body = $msg->{content};
            
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
