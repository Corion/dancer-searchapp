package Dancer::SearchApp::Extractor;
use strict;
no warnings 'experimental';
use feature 'signatures';
use Module::Pluggable search_path => __PACKAGE__, require => 1;
use Promises 'collect';
use Carp 'croak';
#use Moo;

=head1 NAME

Dancer::SearchApp::Extractor - metadata extractors

=cut

=head1 METHODS

=head2 C<< ->extract( %options ) >>

  my $info = $tika->get_meta( $content );
  my $entry = $extractor->extract(
      url => $url,
      info => $info,
      content => \$content, # if we have it
      filename => $filename, # if we have it
  )->then(sub { ... });
  
  # Do something with the Dancer::SearchApp::Entry,
  # like insert it into Elasticsearch

This method goes through all installed plugins and
offers the file for inspection. The C<$info> parameter
will contain the information and content extracted by Apache Tika,
so especially the MIME type will be available.

The method returns a promise so that analysis can happen in the background.
The promise will be passed a list of the found items that were not C<undef>.
Currently no ranking is performed and all plugins are treated as equally
applicable.

=cut

sub examine( $self, %options ) {
    $options{ url }
        or croak "Need URL option";
    $options{ info }
        or croak "Need info option";
        
    return collect( map {
        my $plugin = $_;
        $plugin->examine(
            # Yes, copying is a bit inefficient but saves us later headaches
            %options
        )
    } ($self->plugins))->then(sub {
        map { @$_ }
        grep { defined $_ and @$_ } @_
    });
}

1;