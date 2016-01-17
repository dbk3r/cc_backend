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
use CC::transcode qw(transcode genThumbnail);
use CC::fileio;
use CC::mediainfo qw(videoinfo audioinfo);
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
$dbh->do("INSERT INTO ".$encoder_table." set encoder_ip='".$ipaddr."', encoder_max_slots='".$max_encoding_slots."', encoder_used_slots='0', encoder_cpus='".$num_cpus."'");

if (-e $ffmpeg_bin) { $dbh->do("update ".$encoder_table." set encoder_ffmpeg='1'") ;} else {  print "can\'t find ffmpeg, disable ffmpeg-encoding \n";}
if (-e $ffmbc_bin) { $dbh->do("update ".$encoder_table." set encoder_ffmbc='1'") ;} else {  print "can\'t find ffmbc, disable ffmbc-encoding \n";}
if (-e $blender_bin) { $dbh->do("update ".$encoder_table." set encoder_blender='1'") ;} else {  print "can\'t find blender, disable blender rendering \n";}
if (-e $mediainfo_bin) { $dbh->do("update ".$encoder_table." set encoder_mediainfo='1'") ;} else {  print "can\'t find mediainfo, disable media analyzer \n";}

ccClose($dbh);

print "encoder-unit is running \n";

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
	
	if ($av_slots > 0 && $ip eq $ipaddr) 
	{
		# read cc_jobs
		read_jobs_db();
		
		if ($jobcount > 0)
		{
			# render job
			render_job($content_dir,$job_uuid);
			sleep 2;
		}
	}	
	#ccClose($dbh);
}

sub deldb {
	my $uuid = shift;
	$retval = true;
	$dbh->do("DELETE FROM ".$content_table." WHERE content_uuid='".$uuid."'");		
	$dbh->do("DELETE FROM ".$jobs_table." WHERE (uuid='".$uuid."' and state<>0)");	
	
	return $retval;
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
	$dbh->do("UPDATE ".$encoder_table." set encoder_used_slots='".$new_used_slots."' where encoder_ip='".$ipaddr."'");
}

sub render_job {
	
	my $content_dir=shift;
	my $uuid = shift;	
	if ($job_type eq "blender" && -e $blender_bin)
	{
		
		set_job_state($job_id,1);
		$cmd = $blender_bin ." -b " .  $content_dir . $uuid . "/" . $job_filename . " " . $job_cmd;
		
		if (render($job_id, $cmd))
		{ set_job_state($job_id,2); }
		else
		{ set_job_state($job_id.3); }	
	}	

	elsif ($job_type eq "sequence" && -e $ffmpeg_bin)
	{			
		set_job_state($job_id,1);
		$start_number = "-start_number ". $startframe;
		$input_sequence = $sourcefile . "/%04d.png";
		$cmd = $ffmpeg_bin . " -r 25 -i ". $input_sequence . " ". $start_number. " -vcodec libx264 -b:v 4000k  ". $output_folder . "/" . $scene_name .".mp4";
		system($cmd);		
	}

	elsif ($job_type eq "transcode")
	{
		set_job_state($job_id,1);
		if($coder_bin eq "ffmpeg") { $coder=$ffmpeg_bin; }
		if($coder_bin eq "ffmbc") { $coder=$ffmbc_bin; }
		$cmd = $coder . " " .  $job_cmd . " " . $content_dir.$job_uuid."/" . $dest_filename;
		if (transcode($job_id,$cmd,$dest_filename,$dbh))
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
	elsif ($job_type eq "genThumbnail" && -e $ffmpeg_bin)
        {
		set_job_state($job_id,1);
		if(genThumbnail($ffmpeg_bin, $content_dir, $uuid, $src_filename)==0)
		{
			set_job_state($job_id,2);
		}
		else
		{
			set_job_state($job_id,3);
		}
        }

	elsif ($job_type eq "mediainfo" && -e $mediainfo_bin)
        {
		if($ontent_type eq "Video")
		{
			set_job_state($job_id,1);
			my $videoResults = video_info($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my $audioResults = audio_info($mediainfo_bin, $content_dir, $uuid, $src_filename);
			my @vR = split(",",$videoReults);
			my @aR = split(",",$audioResults);
			if($vR[0] == 0)
			{
				$dbh->do("UPDATE ".$content_table." set content_duration='".$vR[2]."',content_videoCodec='". $vR[3] ."',videoBitrate='". $vR[4] ."',content_videoCodec='". $vR[3] ."' WHERE uuid='".$uuid."'");
				set_job_state($job_id,2);
			}
			else
                	{
				$dbh->do("UPDATE ".$content_table." set content_duration='unknown',content_videoCodec='unknown',videoBitrate='unknown',content_videoCodec='unknown' WHERE uuid='".$uuid."'");
				set_job_state($job_id,3);
			}
		}
		if($content_type eq "Audio")
		{
			set_job_state($job_id,1);
			my $audioResults = audio_info($mediainfo_bin, $content_dir, $uuid, $src_filename);
                        my @aR = split(",",$audioResults);
			if($aR[0] == 0)
                        {
                                $dbh->do("UPDATE ".$content_table." set content_audioCodec='". $vR[2] ."',content_audioSamplingrate='". $vR[4] ."',content_audioChannel='". $vR[3] ."' WHERE uuid='".$uuid."'");
                                set_job_state($job_id,2);
                        }
                        else
                        {
                                $dbh->do("UPDATE ".$content_table." set content_audioCodec='unknown',content_audioSamplingrate='unknown',audioChannel='unknown' WHERE uuid='".$uuid."'");
                                set_job_state($job_id,3);
                        }

		}
        }

	elsif ($job_type eq "delContent")
	{
		set_job_state($job_id,1);
		$del_file = $content_dir . $uuid;
		print "del: ".$del_file ."\n";
		
		if(rmtree($content_dir.$uuid))
		{ set_job_state($job_id,2); }
                else
                { set_job_state($job_id,3); }	
                $dbh->do("DELETE FROM ".$jobs_table." WHERE (uuid='".$uuid."' and state<>0)");	
	}
	elsif ($job_type eq "delContentDB")
	{
		set_job_state($job_id,1);
		if(deldb($uuid))
		{ set_job_state($job_id,2); }
                else
                { set_job_state($job_id,3); }	
	}
		
}

sub read_jobs_db {
	
	
	$jobresult = $dbh->prepare("SELECT * FROM ".$jobs_table." WHERE state='0' ORDER BY id,prio LIMIT 1 ");


	$jobresult->execute();
	$jobcount = $jobresult->rows;
	if ($jobcount > 0)
	{
		while (my $jobrow = $jobresult->fetchrow_hashref) {
			$job_id = $jobrow->{id};
			$job_cmd = $jobrow->{cmd};	
			$content_type = $jobrow->{content_type};	
			$job_type = $jobrow->{job_type};
			$coder_bin = $jobrow->{coder_bin};		
			$job_prio = $jobrow->{prio};
			$src_filename = $jobrow->{src_filename};
			$dest_filename = $jobrow->{dest_filename};
			$job_uuid = $jobrow->{uuid};
		}
	}
	
}



sub read_encoder_db {

	$result = $dbh->prepare("SELECT * FROM " .$encoder_table." ORDER BY encoder_used_slots LIMIT 1");
	$result->execute();
	while (my $row = $result->fetchrow_hashref) {
		$max_slots= $row->{encoder_max_slots};
		$used_slots= $row->{encoder_used_slots};
		$ip = $row->{encoder_ip};
	}

}

sub interrupt {
	print "encoding unit removed. bye!\n";
	$pm->wait_all_children;
	$dbh = ccConnect($mysql_host, $mysql_user, $mysql_password, $mysql_db);	
    	$dbh->do("delete from ".$encoder_table." where encoder_ip='".$ipaddr."'");
	$dbh->disconnect();	
    	exit;  
}

