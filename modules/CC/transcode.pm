package CC::transcode;
use strict;
use warnings;
use Exporter qw(import);
use IPC::Run qw( start pump );


our @EXPORT_OK = qw(transcode genThumbnail blenderthumbnailer);

sub transcode {				# Syntax transcode(JOB-ID, FFCMD, OUTFILE, DB-CONNECTION)

        my $jid = shift; 		# Job ID
        my $ff = shift; 		# FFCMD
	my $outfile = shift; 		# OUTFILE
	my $dbh = shift;		# DB-CONNECTION
        my @ffCMD = split(" ",$ff);
        my ($in, $out, $err);
	my $retval = 1;

          my $harness = start \@ffCMD, \$in, \$out, \$err;
          pump $harness until ($err =~ m{Duration: (\d+:\d+:\d+\.\d+)}ms);
          our $error = $err;
          $err =~ m{Duration: (\d+:\d+:\d+\.\d+)}ms;
          my $duration = $1;
          if($duration) { } else {
                $error =~ s/\n/<br>/;
                $error =~ s/\r/<br>/;
                my $job_state = $dbh->prepare("update cc_jobs set state='1' where id='$jid'");
                $job_state->execute();
                return 0;
          }

          my ($h, $m, $s) = split /:/, $duration;
          $duration = $h * 3600 + $m * 60 + $s;
          while(1){
                pump $harness until ($err =~ m{time=(\d+:\d+:\d+\.\d+)}omsg);
              my $so_far = $1;
              my ($h1, $m1, $s1) = split /:/, $so_far;
              my $time = $h1 * 3600 + $m1 * 60 + $s1;
              my $progress = int($time * 100 / $duration);
              my $job_state = $dbh->prepare("update cc_jobs set progress='$progress' where id='$jid'");
                 $job_state->execute();
                 $err = "";
                 
              
              if ($progress >= 99) {
		my $job_state = $dbh->prepare("update cc_jobs set progress='100' where id='$jid'");
		$job_state->execute();
		last;      
              }
          }
	      
              finish $harness;
	      
}

sub genThumbnail {
	my $ffmpeg_bin = shift;
	my $content_dir = shift;
	my $uuid = shift;
	my $src_filename = shift;

	my $genCMD = $ffmpeg_bin . " -loglevel quiet -y -i \"". $content_dir.$uuid."/".$src_filename."\" -vframes 1 -s 106x60 \"". $content_dir.$uuid."/".$src_filename.".png\"";
	#print $genCMD."\n";	
	my $genResult = system($genCMD);
	return $genResult;
}
sub blenderthumbnailer {
	my $thumbnailer_bin = shift;
	my $content_dir = shift;
	my $uuid = shift;
	my $src_filename = shift;
	my $genthumbnail = $thumbnailer_bin . " ". $content_dir.$uuid."/".$src_filename." ".$content_dir.$uuid."/".$src_filename.".png";
	my $genResult = system($genthumbnail);
	return $genResult;
}


1;

