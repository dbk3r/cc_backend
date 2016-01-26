package CC::fileio;
 
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(filesize write_log);

use File::stat;

sub filesize {
        my $file = shift;
        my $size = (stat($file)->size) ;
        my $retval = "";
        if ($size >= 1000000000) {
                $retval = int(($size / 1000000000)). " GB";
        }
        elsif ($size >= 1000000) {
                $retval = int(($size / 1000000)) .  " MB";
        }
        else {
                $retval = int(($size / 1000)) ." KB";
        }
        return $retval;
}

sub write_log {
        
        my $log_file = shift;
        my $log_text = shift;
        
        my $datum = localtime time;
        my @dat_fields = split(" ", $datum);
        $datum = "$dat_fields[0] $dat_fields[2] $dat_fields[1] $dat_fields[4] $dat_fields[3]";
        open (CC_LOG, ">>$log_file");
        print CC_LOG "[$datum] :: [$$] $log_text\n";
        close CC_LOG;
}

1;


