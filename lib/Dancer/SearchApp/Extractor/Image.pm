package Dancer::SearchApp::Extractor::Image;
use strict;
use Carp 'croak';
use Promises 'deferred';
no warnings 'experimental';
use feature 'signatures';
use Image::ExifTool;
use POSIX 'strftime';


sub examine( $class, %options ) {
    my $info = $options{info};
    
    my $result = deferred;
    my $mime_type = $info->meta->{"Content-Type"};
    
    if( $mime_type =~ m!^image/.*$! ) {
        my %res = (
            url    => $options{ url },
            file   => $options{ filename },
            folder => $options{ folder },
        );
            
        my $info = Image::ExifTool->new;
        my $file = $options{ filename };
        
        # If we have a filename, use that
        if( $file ) {

            $info->ExtractInfo("$file");
            
            my $ctime = (stat $file)[10];
            $res{ creation_date } = strftime('%Y-%m-%d %H:%M:%S', localtime($ctime));

        } elsif( $options{ content }) {
            $info->ExtractInfo($options{ content });

        }
        
        if( $info ) {

            # go go go
            $res{ title } = $info->GetValue( 'Title' ) || $file->basename;
            $res{ author } = $info->GetValue( 'Author' );
            $res{ language } = 'en'; # ...
            $res{ content } = join "\n", map { $_ => $info->GetValue($_) } $info->GetFoundTags('File'), $file->basename;
            # We should also generate/store a (tiny) thumbnail here
            # to generate an "HTML" page for the file

            $res{ mime_type } = $mime_type;
            
            $result->resolve( \%res );
        } else {
            # Nothing found
            $result->resolve();
        }
    } else {
        $result->resolve();
    }
    
    $result->promise
}

1;