package Search::Elasticsearch::Plugin::Langdetect;
use strict;
use Carp qw(croak);
use JSON::MaybeXS;

=head1 SYNOPSIS

        use Search::Elasticsearch;
        use Search::Elasticsearch::Plugin::Langdetect;
        
        use Search::Elasticsearch();
        my $es = Search::Elasticsearch->new(
            nodes   => \@nodes,
            plugins => ['Langdetect']
        );
        
        my $e = Search::Elasticsearch->new(...);
        my $ld = Search::Elasticsearch::Plugin::Langdetect->new(
            elasticsearch => $e
        );

        my $lang = $ld->detect_language( "Hello World" );
        # en

=head1 METHODS

=cut

sub new {
    my( $class, %options ) = @_;
    
    if( ! $options{ transport }) {
        croak "Need Elasticsearch instance or transport for requests"
            unless $options{ elasticsearch };
        $options{ transport } = $options{ elasticsearch }->transport;
    };
    
    bless \%options => $class;
}

sub transport { $_[0]->{transport} }

=head2 C<< ->detect_language $content >>

    my $lang = $ld->detect_language( $content );

Returns the ISO-two-letter code for the detected language.

=cut

sub detect_language {
    my( $self, $content ) = @_;
    
    $self->detect_languages( $content )->[0]->{language}
}

=head2 C<< ->detect_languages $content >>

    my $languages = $ld->detect_languages( $content );

Returns an arrayref of all detected languages together with
their propabilities.

=cut

sub detect_languages {
    my( $self, $content ) = @_;
    
    my $result = $self->transport->perform_request(
        method => 'POST',
        path   => '/_langdetect',
        body   => $content
    );

    $result->{languages}
}


1;