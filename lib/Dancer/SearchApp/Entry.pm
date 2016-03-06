package Dancer::SearchApp::Entry;
use Moo;

# Convenience package to hold the information on an entry in the index
# This should basically match whatever you have in the index

# Canonical URL
has url => (
    is => 'ro',
    #isa => 'Str',
);

*id = \*url;

has mime_type => (
    is => 'ro',
    #isa => 'Str',
);

has author => (
    is => 'ro',
    #isa => 'Str',
);

has creation_date => (
    is => 'ro',
    #isa => 'Str',
);

has content => (
    is => 'ro',
    #isa => 'Str', # HTML-String
);

has title => (
    is => 'ro',
    #isa => 'Str',
);

has language => (
    is => 'ro',
    #isa => 'Str', # 'de', not (yet) de-DE
);

sub from_es {
    my( $class, $result ) = @_;
    my %args = %{ $result->{_source} };
    if( $args{ "Content-Type" } ) {
        $args{ mime_type } = delete $args{ "Content-Type" };
    };
    my $self = $class->new( %args );
    $self
}

sub basic_mime_type {
    my( $self ) = @_;
    my $mt = $self->mime_type;
    
    $mt =~ s!;.*!!;
    
    $mt
}

1;
