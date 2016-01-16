use IPC::Run qw( start pump );
use Data::UUID;
use File::stat;

sub filesize {
	my $file = shift
	return stat($file)->size;
}

sub analyze_video {

	my $filename=shift;
}

sub analyze_audio {

	my $filename=shift;
}

sub transcode {

        my $jid = shift;
        my $ff = shift; # transcode(job_id,"ffmpeg -i inputFile -vcodec libx264 outFile")
	my $outfile = shift;
        my @ffCMD = split(" ",$ff);
        my ($in, $out, $err);
	$retval = true;

          my $harness = start \@ffCMD, \$in, \$out, \$err;
          pump $harness until ($err =~ m{Duration: (\d+:\d+:\d+\.\d+)}ms);
          $error = $err;
          $err =~ m{Duration: (\d+:\d+:\d+\.\d+)}ms;
          my $duration = $1;
          if($duration) { } else {
                $error =~ s/\n/<br>/;
                $error =~ s/\r/<br>/;
                $job_state = $dbh->prepare("update cc_jobs set state='1' where id='$jid'");
                $job_state->execute();
                return false;
          }

          my ($h, $m, $s) = split /:/, $duration;
          $duration = $h * 3600 + $m * 60 + $s;
          while(1){
                pump $harness until ($err =~ m{time=(\d+:\d+:\d+\.\d+)}omsg);
              my $so_far = $1;
              my ($h1, $m1, $s1) = split /:/, $so_far;
              $time = $h1 * 3600 + $m1 * 60 + $s1;
              $progress = int($time * 100 / $duration);
                $job_state = $dbh->prepare("update cc_jobs set progress='$progress' where id='$jid'");
                $job_state->execute();
                $err = "";
              last if ( $progress >= 99);
          }

              finish $harness;
	      if(filesize($outfile) > 0) {
		$$retval = true;
	      } else {
		$retval = false;
	      }
	return $retval;
}

sub render {

	$jid = shift;
	$cmd = shift;
	my @blenderCMD = split(" ", $cmd);
	my ($in, $out, $err);
	$retval = true;

	my $harness = start \@blenderCMD, \$in, \$out, \$out;
	$in = '';

	pump $harness while length $in;

	while(1){
		pump $harness until $out =~ s/(.+)\n$//gm ;
		#pump $harness until $out =~ /^\s*Fra/;
		$full_line = $1;
		$remaining = $full_line;
		if ($remaining =~ /^\s*Fra/)
		{
			if (index($remaining, "Path Tracing Tile") > 1)
			{
				$progress = substr($remaining,index($remaining, "Path Tracing Tile") + 18,7) ;
				$job_state = $dbh->prepare("update convjobs set progress='$progress' where id='$jid'");
				$job_state->execute();
			}
		}

		last if ("Blender quit" eq $full_line);

	}
	finish $harness;
	return $retval;
}
