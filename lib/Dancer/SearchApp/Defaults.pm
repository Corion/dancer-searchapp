package Dancer::SearchApp::Defaults;
use strict;
use Exporter 'import';
use vars qw($VERSION @EXPORT_OK);
$VERSION = '0.04';

# This should move to Config::Spec::FromPod
# and maybe even Config::Collect

@EXPORT_OK = qw(
    default_index
);

use constant default_index => 'dancer-searchapp';

1;