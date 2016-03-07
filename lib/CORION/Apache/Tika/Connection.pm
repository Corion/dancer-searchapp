package CORION::Apache::Tika::Connection;
use strict;
use Moo::Role;
use JSON::XS;
use vars qw($VERSION);
$VERSION = '0.01';

sub decode_response {
    my( $self, $body ) = @_;
    
    return decode_json( $body );
}

sub process_response {
    my ( $self, $params, $code, $msg, $body, $headers ) = @_;
    
    my $mime_type = $headers->{"content-type"};

    my $is_encoded = $mime_type && $mime_type !~ m!^text/plain\b!;

    # Request is successful

    if ( $code >= 200 and $code <= 209 ) {
        if ( defined $body and length $body ) {
            # Let's hope it's JSON
            $body = $self->decode_response($body)
                if $is_encoded;
            return $code, $body;
        }
        return ( $code, 1 ) if $params->{method} eq 'HEAD';
        return ( $code, '' );
    }

    # Check if the error should be ignored
    return ($code, $body);
}

1;