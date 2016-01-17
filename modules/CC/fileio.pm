package CC::fileio;
 
use strict;
use warnings;

use Exporter qw(import);
use IPC::Run qw( start pump );

our @EXPORT_OK = qw(filesize);

use File::stat;

sub filesize {
        my $file = shift;
        return stat($file)->size;
}
1;


