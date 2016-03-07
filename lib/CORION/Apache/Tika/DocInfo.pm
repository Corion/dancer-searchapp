package CORION::Apache::Tika::DocInfo;
use Moo;

has meta => (
    is => 'ro',
    #isa => 'Hash',
);

has content => (
    is => 'ro',
    #isa => 'Int',
);

__PACKAGE__->meta->make_immutable;

1;