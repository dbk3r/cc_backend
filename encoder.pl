use Config::Simple;
use Config;
use Sys::CpuAffinity;
use Net::Address::IP::Local;
use Socket;
use Sys::Hostname;
use DBI;
use Parallel::ForkManager;  
use FindBin;
use IPC::Run qw(start pump);
use File::Path qw( rmtree );
use Cwd 'abs_path';
use lib abs_path.'/modules';
use CC::transcode qw(transcode genThumbnail blenderthumbnailer) ;
use CC::fileio qw(filesize write_log);
use CC::mediainfo qw(videoinfo audioinfo generalinfo);
use CC::ccDB qw(ccConnect ccClose);

$os = $Config{osname};
$SIG{INT} = \&interrupt;
#$host = hostname();

our $dbh;

if ($os eq "MSWin32")
{
	$ipaddr = inet_ntoa(scalar(gethostbyname($name)) || 'localhost');
}

if ($os eq "linux")
{
	$ipaddr = Net::Address::IP::Local->public_ipv4;
}
my $script_path = $FindBin::Bin . "/" ;

do 'readConfig.pl';

$pm = new Parallel::ForkManager($max_encoding_slots);

$num_cpus = Sys::CpuAffinity::getNumCpus();

$dbh = ccConnect($mysql_host, $mysql_user, $mysql_password, $mysql_db);  
$dbh->do("INSERT INTO ".$encoder_table." set encoder_instance='".$nodeinstance."', encoder_ip='".$ipaddr."', encoder_max_slots='".$max_encoding_slots."', encoder_used_slots='0', encoder_cpus='".$num_cpus."'");

if (-e $ffmpeg_bin) { push(@job_essentials_array,"'ffmpeg'"); } else { print "can\'t find $ffmpeg_bin, disable ffmpeg-encoding \n";}
if (-e $ffmbc_bin) { push(@job_essentials_array,"'ffmbc'"); } else {  print "can\'t find $ffmbc_bin, disable ffmbc-encoding \n";}
if (-e $blender_bin) { push(@job_essentials_array,"'blender'"); } else {  print "can\'t find $blender_bin, disable blender rendering \n";}
if (-e $mediainfo_bin) { push(@job_essentials_array,"'mediainfo'"); } else { print "can\'t find $mediainfo_bin, disable mediascan \n";}
if (-e $curl_bin) { push(@job_essentials_array,"'curl'"); } else { print "can\'t find $curl_bin, disable ftp-transfer \n";}
if (-e $bmxtranswrap_bin) { push(@job_essentials_array,"'bmxtranswrap'"); } else { print "can\'t find $bmxtranswrap_bin , disable rewrapping \n";}

$job_essentials = join(",",@job_essentials_array);

ccClose($dbh);

print "coder-unit [". $nodeinstance."] ".$ipaddr ." started \n";
write_log($log_file, "coder-unit [". $nodeinstance."] ".$ipaddr ." started");

$slot_thread = 1;
while (1) {
	
	$pm->start($slot_thread) and next;	
	runloop($slot_thread);
	$pm->finish($slot_thread);
	sleep 30;

	if ($slot_thread < $max_encoding_slots)
	{
		$slot_thread++;
	}
	else
	{
		$slot_thread = 1;
	}	
}

sub runloop {

	$p = shift;	
	$dbh = ccConnect($mysql_host, $mysql_user, $mysql_password, $mysql_db);
	read_encoder_db();
	$av_slots = $max_slots - $used_slots; 
	
	if ($av_slots > 0 && ($ip eq $ipaddr && $nodeinstance eq $instance)) 
	{
		# read cc_jobs
		read_jobs_db($dbh);
			
		if ($jobcount > 0)
		{
			# render job
			set_job_state($job_id,1);
			render_job($content_dir,$job_uuid);
			sleep 2;
		}
	}	
	#ccClose($dbh);
}


sub set_job_state {
	my $jid = shift;
	my $state = shift;
	read_encoder_db();
	
	if ($state == 1)
	{
                $new_used_slots = $used_slots + 1;
	}
	else
        {
                $new_used_slots = $used_slots - 1;
        }
	$dbh->do("UPDATE ".$jobs_table." set state='$state' WHERE id='".$jid."'");
	$dbh->do("UPDATE ".$encoder_table." set encoder_used_slots='".$new_used_slots."' where encoder_ip='".$ipaddr."' AND encoder_instance='".$nodeinstance."'");
}

sub render_job {
	
	my $content_dir=shift;
	my $uuid = shift;	
	
	if ($job_type eq "render" && -e $blender_bin)
	{
		
		$cmd = $blender_bin ." -b " .  $content_dir . $uuid . "/" . $job_filename . " " . $job_cmd;
		
		if (render($job_id, $cmd))
		{ set_job_state($job_id,2); }
		else
		{ set_job_state($job_id.3); }	
	}	

	elsif ($job_type eq "sequence" && -e $ffmpeg_bin)
	{			
		$start_number = "-start_number ". $startframe;
		$input_sequence = $sourcefile . "/%04d.png";
		$cmd = $ffmpeg_bin . " -r 25 -i ". $input_sequence . " ". $start_number. " -vcodec libx264 -b:v 4000k  ". $output_folder . "/" . $scene_name .".mp4";
		system($cmd);		
	}

	elsif ($job_type eq "transcode")
	{
		if($job_essential eq "ffmpeg") { $coder=$ffmpeg_bin; }
		if($job_essential eq "ffmbc") { $coder=$ffmbc_bin; }
		$cmd = $coder . " -y -i ". $content_dir.$job_uuid."/" .$src_filename . " " . $job_cmd . " " . $content_dir.$job_uuid."/" . $dest_filename;
		write_log($log_file, $cmd );
		
		if (transcode($job_id,$cmd,$dest_filename,$dbh) == 0)
		{ set_job_state($job_id,2); }
                else
                { set_job_state($job_id,3); }
	}
	
	elsif ($job_type eq "ftp")
        {
                
        }
	elsif ($job_type eq "copy")
	{
		
	}
	elsif ($job_type eq "move")
	{
		
	}
	elsif ($job_type eq "genThumbnail")
        {
        	if($job_essential eq "ffmpeg")
        	{
			if(genThumbnail($ffmpeg_bin, $content_dir, $uuid, $src_filename) == 0)
			{
				$dbh->do("UPDATE ".$content_table." set content_thumbnail='".$src_filename.".png' WHERE content_uuid='".$uuid."'");
				set_job_state($job_id,2);
			}
			else
			{
				set_job_state($job_id,3);
			}
		}
		elsif($job_essential eq "blender")
		{
			write_log($log_file, $blender_thumbnailer_bin . " ". $content_dir.$uuid."/".$src_filename." ".$content_dir.$uuid."/".$src_filename.".png");
			if(blenderthumbnailer($blender_thumbnailer_bin, $content_dir, $uuid, $src_filename) == 0)			
			{				
				$dbh->do("UPDATE ".$content_table." set content_thumbnail='".$src_filename.".png' WHERE content_uuid='".$uuid."'");
				set_job_state($job_id,2);
			}
			else
			{
				if(! -e $blender_thumbnailer_bin) { write_log($log_file, $blender_thumbnailer_bin," not found!");}
				set_job_state($job_id,3);
			}
		}
        }

	elsif ($job_type eq "mediainfo" && -e $mediainfo_bin)
        {
		if($content_type eq "Video")
		{			
			write_log($log_file,"mediainfo: ".$content_dir.$uuid."/".$src_filename);
			my $videoResults = videoinfo($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my $audioResults = audioinfo($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my $generalResults = generalinfo($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my @gR = split(",",$generalResults);
			my @vR = split(",",$videoResults);
			my @aR = split(",",$audioResults);
			if($vR[0] == 0)
			{				
				$dbh->do("UPDATE ".$content_table." set content_filesize='".$gR[1]."',content_videoDimension='".$vR[1]."',content_duration='".$vR[2]."',content_videoCodec='". $vR[3] ."',content_videoBitrate='". $vR[4] ."',content_videoCodec='". $vR[3] ."' WHERE content_uuid='".$uuid."'");
				$dbh->do("UPDATE ".$content_table." set content_audioCodec='". $aR[2] ."',content_audioSamplingrate='". $aR[4] ."',content_audioChannel='". $aR[3] ."' WHERE content_uuid='".$uuid."'");
				set_job_state($job_id,2);
			}
			else
                	{
				$dbh->do("UPDATE ".$content_table." set content_duration='unknown',content_videoCodec='unknown',content_videoBitrate='unknown',content_videoCodec='unknown' WHERE content_uuid='".$uuid."'");
				set_job_state($job_id,3);
			}
		}
		if($content_type eq "Audio")
		{
			my $audioResults = audioinfo($mediainfo_bin, $content_dir, $uuid, $src_filename);			
			my $generalResults = generalinfo($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my @gR = split(",",$generalResults);
                        my @aR = split(",",$audioResults);
                        #my $fs = filesize($content_dir.$uuid."/".$src_filename);
			if($aR[0] == 0)
                        {
                                $dbh->do("UPDATE ".$content_table." set content_duration='".$aR[5]."',content_filesize='".$gR[1]."',content_audioCodec='". $aR[2] ."',content_audioSamplingrate='". $aR[4] ."',content_audioChannel='". $aR[3] ."' WHERE content_uuid='".$uuid."'");
                                set_job_state($job_id,2);
                        }
                        else
                        {
                                $dbh->do("UPDATE ".$content_table." set content_duration='"."unknown"."',content_audioCodec='unknown',content_audioSamplingrate='unknown',audioChannel='unknown' WHERE content_uuid='".$uuid."'");
                                set_job_state($job_id,3);
                        }

		}
        }

	elsif ($job_type eq "delete")
	{
		
			$del_file = $content_dir . $uuid;
			write_log($log_file, "deleting : ".$del_file);
			
			if(rmtree($content_dir.$uuid))
			{ set_job_state($job_id,2); write_log($log_file, "deleting : ".$del_file ."success! "); }
			else
			{ set_job_state($job_id,3); write_log($log_file, "deleting : ".$del_file ."failed! ");}
		
			write_log($log_file, "deleting Content with UUID: ".$uuid);
			if(deldb($uuid))
			{ set_job_state($job_id,2); }
			else
			{ set_job_state($job_id,3); }				
	}	
		
}

sub deldb {
	my $uuid = shift;
	$retval = true;
	$dbh->do("DELETE FROM ".$content_table." WHERE content_uuid='".$uuid."'");		
	$dbh->do("DELETE FROM ".$jobs_table." WHERE (uuid='".$uuid."' and state<>0)");	
	
	return $retval;
}

sub read_jobs_db {
	
	my $dbh = shift;	
	$jobresult = $dbh->prepare("SELECT * FROM ".$jobs_table." WHERE state='0' AND job_essential IN (".$job_essentials.") ORDER BY id,prio LIMIT 1 ");

	$jobresult->execute();
	$jobcount = $jobresult->rows;
	if ($jobcount > 0)
	{
		while (my $jobrow = $jobresult->fetchrow_hashref) {
			$job_id = $jobrow->{id};
			$job_cmd = $jobrow->{job_cmd};	
			$content_type = $jobrow->{content_type};	
			$job_type = $jobrow->{job_type};
			$job_shortName = $jobrow->{job_shortName};
			$job_essential = $jobrow->{job_essential};		
			$job_prio = $jobrow->{prio};
			$src_filename = $jobrow->{src_filename};
			$dest_filename = $jobrow->{dest_filename};
			$job_uuid = $jobrow->{uuid};
		}
	}
	
}



sub read_encoder_db {

	$result = $dbh->prepare("SELECT * FROM " .$encoder_table." where encoder_ip='".$ipaddr."' AND encoder_instance='".$nodeinstance."' ORDER BY encoder_used_slots LIMIT 1");
	$result->execute();
	while (my $row = $result->fetchrow_hashref) {
		$max_slots= $row->{encoder_max_slots};
		$used_slots= $row->{encoder_used_slots};
		$ip = $row->{encoder_ip};
		$instance = $row->{encoder_instance};
	}

}

sub interrupt {
	print "encoding unit removed. bye!\n";
	$pm->wait_all_children;
	$dbh = ccConnect($mysql_host, $mysql_user, $mysql_password, $mysql_db);	
    	$dbh->do("delete from ".$encoder_table." where encoder_ip='".$ipaddr."' AND encoder_instance='".$nodeinstance."'");
	$dbh->disconnect();	
    	exit;  
}

