package CC::mediainfo;
 
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(videoinfo audioinfo generalinfo);

sub generalinfo {
	my $mediainfo_bin = shift;
	my $content_dir = shift;
	my $uuid = shift;
        my $src_filename=shift;
	my $content_table = shift;
	my $err = 0;

	my $miCMD = " --Inform=\"General;%FileSize/String%\"";	
	my $media_infos = `\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"`;
	chop $media_infos;
	#print "\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"\n";
	if (length($media_infos)) { $err = 0; } else { $err = 1;}	
	return $err.",".$media_infos;
	
}


sub videoinfo {
	my $mediainfo_bin = shift;
	my $content_dir = shift;
	my $uuid = shift;
        my $src_filename=shift;
	my $content_table = shift;
	my $err = 0;

	my $miCMD = " --Inform=\"Video;%Width%:%Height%,%Duration/String4%,%Codec/String%,%BitRate/String%\"";	
	my $media_infos = `\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"`;
	chop $media_infos;
	#print "\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"\n";
	if (length($media_infos)) { $err = 0; } else { $err = 1;}	
	return $err.",".$media_infos;
}

sub audioinfo {
	my $mediainfo_bin = shift;
	my $content_dir = shift;
        my $uuid = shift;
        my $src_filename=shift;
        my $content_table = shift;
	my $err = 0;
	
	my $miCMD = " --Inform=\"Audio;%StreamCount%,%Codec%,%Channels%,%SamplingRate/String%,%Duration/String3%\"";	
	my $media_infos =  `\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"`;
	chop $media_infos;
	#print "\"$mediainfo_bin\" $miCMD \"$content_dir$uuid/$src_filename\"\n";
	if (length($media_infos)) { $err = 0; } else { $err = 1;}
        return $err.",".$media_infos;
}

1;


