package CORION::Apache::Tika::DocInfo;
use Moo;
use vars qw($VERSION);
$VERSION = '0.01';

has meta => (
    is => 'ro',
    #isa => 'Hash',
);

has content => (
    is => 'ro',
    #isa => 'Int',
);

1;