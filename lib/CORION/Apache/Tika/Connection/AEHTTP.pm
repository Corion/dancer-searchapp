package CORION::Apache::Tika::Connection::AEHTTP;
use AnyEvent::HTTP qw(http_request);
use Promises qw(deferred);
use Try::Tiny;
use Moo;
with 'CORION::Apache::Tika::Connection';

use vars '$VERSION';
$VERSION = '0.01';

sub request {
    my( $self, $method, $url, $content, @content ) = @_;
    # Should initialize
    
    $method = uc $method;
    
    my $content_size = length $content;
    
    my %headers= $content
               ? (
                  "Content-Length" => $content_size,
                  "Accept" => 'application/json,text/plain',
                  # "Content-Type" => 'application/pdf',
                 )
               : ();
    
    my $p = deferred;
    http_request(
        $method => $url,
        headers => \%headers,
        body => $content,
        sub {
            my ( $body, $headers ) = @_;
            # The headers might be invalid!
            try {
                my ( $code, $response ) = $self->process_response(
                    undef,                        # request
                    delete $headers->{Status},    # code
                    delete $headers->{Reason},    # msg
                    $body,                        # body
                    $headers                      # headers
                );
                
                $p->resolve( $code, $response );
            }
            catch {
                warn "Internal error: $_";
                $p->reject($_);
            }
        },
    );
    $p->promise
}

1;