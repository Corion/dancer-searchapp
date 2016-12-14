#!perl -w
use Test::More tests => 2;
use strict;
use warnings;

# the order is important
use Dancer::SearchApp;
use Dancer::Test;
use Data::Dumper;

# http://localhost:5000/suggest/distribution.json
route_exists [GET => '/suggest/distr.json'], 'a route handler is defined for /suggest/';

# This doesn't find the view in views/ . I don't care why.
response_status_is ['GET' => '/suggest/distr.json'], 200, 'response status is 200 for /suggest/'
    or diag Dumper read_logs();

done_testing;