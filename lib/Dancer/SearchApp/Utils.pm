package Dancer::SearchApp::Utils;
use strict;
use Exporter 'import';
use AnyEvent;

use vars qw(@EXPORT_OK);
@EXPORT_OK = (qw(synchronous));

# Helper to convert a promise to a synchronous call
sub synchronous($) {
    my $await = AnyEvent->condvar;
    my $promise = $_[0];
    $_[0]->then(sub{ $await->send($_[0])});
    $await->recv
};

1;