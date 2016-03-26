package Plack::Middleware::Pod;
use strict;
use Pod::POM;
use parent qw( Plack::Middleware );
use vars qw($VERSION);
$VERSION = '0.04';

use Plack::Util::Accessor qw(
    path
    root
    pass_through
    pod_view
);

=head1 NAME

Plack::Middleware::Pod - render POD files as HTML

=head1 SYNOPSIS

  enable "Plack::Middleware::Pod",
      path => qr{^/pod/},
      root => './',
      pod_view => 'Pod::POM::View::HTMl', # the default
      ;

=cut

sub call {
    my $self = shift;
    my $env  = shift;
    
    my $res = $self->_handle_pod($env);
    if ($res && not ($self->pass_through and $res->[0] == 404)) {
        return $res;
    }

    return $self->app->($env);
}

sub _handle_pod {
    my($self, $env) = @_;
    
    my $path_match = $self->path;

    $path_match or return;
    my $path = $env->{PATH_INFO};

    # We don't allow relative names, just to be sure
    $path =~ s!^(\.\./)+!!g;
    1 while $path =~ s!([^/]+/\.\./)!/!;
    
    # Sorry if you want to use whitespace in pod filenames
    $path =~ m!^[-_./\w\d]+$!
        or return;

    #warn "[$path]";
    #warn "Checking against $path_match";

    for ($path) {
        my $matched = 'CODE' eq ref $path_match ? $path_match->($_, $env) : $_ =~ $path_match;
        return unless $matched;
    }

    my $r = $self->root || './';
    #warn "Stripping '$path_match' from $path, replacing by '$r'";
    $path =~ s!$path_match!$r!;
    #warn "Rendering [$path]";

    if( -f $path) {
        # Render the Pod to HTML
        my $v = $self->pod_view || 'Pod::POM::View::HTML';
        my $pod_viewer = $v;
        # Load the viewer class
        $pod_viewer =~ s!::!/!g;
        require "$pod_viewer.pm"; # will crash if not found
        
        my $pom = Pod::POM->new->parse_file($path);
        
        return [
            200, ["Content-Type" => "text/html"], [$v->print($pom)]
        ];
    } else {
        #warn "[$path] not found";
        return
    }
}

1;