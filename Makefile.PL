use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME                => 'Dancer::SearchApp',
    AUTHOR              => q{Max Maischein <corion@cpan.org>},
    VERSION_FROM        => 'lib/Dancer/SearchApp.pm',
    ABSTRACT            => 'A simple local search engine',
    ($eumm_version >= 6.3001
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'Dancer'     => 1.3132,
        'Template'   => 0,
        'Search::Elasticsearch' => 2,
        'Search::Elasticsearch::Async' => 2,
        'Promises'   => 0,
        'Path::Class' => 0,
        'URI::file' => 0,
        'Moo' => 0,
        'Exporter' => 5, # for use Exporter 'import'
        'URI::file' => 0,
        'URI::Escape' => 0,
        },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Dancer-SearchApp-*' },
);

