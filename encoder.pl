#!/usr/bin/perl -w

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

$os = $Config{osname};
$SIG{INT} = \&interrupt;
#$host = hostname();

if ($os eq "MSWin32")
{
	$ipaddr = inet_ntoa(scalar(gethostbyname($name)) || 'localhost');

}
if ($os eq "linux")
{
	$ipaddr = Net::Address::IP::Local->public_ipv4;
	
}
my $script_path = $FindBin::Bin . "/" ;

$cfg = new Config::Simple();
$cfg->read('encoder.cfg');

$mysql_host = $cfg->param('mysql_host');
$mysql_user = $cfg->param('mysql_user');
$mysql_password = $cfg->param('mysql_password');
$mysql_db = $cfg->param('mysql_db');
$encoder_table = $cfg->param('encoder_table');
$max_encoding_slots = $cfg->param('max_encoding_slots');
$ffmpeg_bin = $cfg->param('ffmpeg');
$ffmbc_bin = $cfg->param('ffmbc');
$blender_bin = $cfg->param('blender');
$mediainfo_bin = $cfg->param('mediainfo');
$bmxtranswrap_bin = $cfg->param('bmxtranswrapr');
$curl_bin = $cfg->param('curl');
$content_dir = $cfg->param('content_dir');



$pm = new Parallel::ForkManager($max_encoding_slots);

$num_cpus = Sys::CpuAffinity::getNumCpus();

$dbh = DBI->connect('DBI:mysql:'.$mysql_db.';host='.$mysql_host, $mysql_user, $mysql_password) || die "Could not connect to database: $DBI::errstr";
$dbh->do("INSERT INTO ".$encoder_table." set encoder_ip='".$ipaddr."', encoder_max_slots='".$max_encoding_slots."', encoder_used_slots='0', encoder_cpus='".$num_cpus."'");

if (-e $ffmpeg_bin) { $dbh->do("update ".$encoder_table." set encoder_ffmpeg='1'") ;}
if (-e $ffmbc_bin) { $dbh->do("update ".$encoder_table." set encoder_ffmbc='1'") ;}
if (-e $blender_bin) { $dbh->do("update ".$encoder_table." set encoder_blender='1'") ;}

$dbh->disconnect();

$slot_thread = 1;
while (1) {
	
	$pm->start($slot_thread) and next;	
	runloop($slot_thread);
	$pm->finish($slot_thread);
	sleep 3;

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
	$dbh = DBI->connect('DBI:mysql:'.$mysql_db.';host='.$mysql_host, $mysql_user, $mysql_password) || die "Could not connect to database: $DBI::errstr";
	read_encoder_db();
	$av_slots = $max_slots - $used_slots; 
	
	if ($av_slots > 0 && $ip eq $ipaddr) 
	{
		# read brc_jobs
		read_jobs_db();
		
		if ($jobcount > 0)
		{
		
			# used_slots + 1
			$new_used_slots = $used_slots + 1;
			$dbh->do("UPDATE cc_encoder set encoder_used_slots='".$new_used_slots."'");
					
			
			# set jobsstate
			$dbh->do("UPDATE cc_jobs set state='1' WHERE id='".$job_id."'");
			
			# render job
			render_job();
			sleep 2;
			
			# used_slots - 1
			read_encoder_db();
			$new_used_slots = $used_slots - 1;
			$dbh->do("UPDATE cc_encoder set encoder_used_slots='".$new_used_slots."'");
			
		}
	}	
	#$dbh->disconnect();
}

sub render_job {
	
	if ($content_type eq "blender")
	{
		#its a blender file
		$cmd = $blender_bin ." -b " .  $content_dir . $uuid . "/" . $job_filename . " " . $job_cmd;
		render($job_id, $cmd);	
	}	

	elsif ($content_type eq "sequence")
	{			
		$start_number = "-start_number ". $startframe;
		$input_sequence = $sourcefile . "/%04d.png";
		$cmd = $ffmpeg_bin . " -r 25 -i ". $input_sequence . " ". $start_number. " -vcodec libx264 -b:v 4000k  ". $output_folder . "/" . $scene_name .".mp4";
		system($cmd);		
	}

	elsif ($content_type eq "video" || $content_type eq "audio")
	{
		$cmd = $ffmpeg_bin . " " .  $job_cmd . " " . $content_dir.$job_uuid."/" . $job_filename;
		transcode($job_id,$cmd);
	}
		
}

sub read_jobs_db {
	
	$jobresult = $dbh->prepare("SELECT * FROM cc_jobs WHERE state='0' ORDER BY id,prio LIMIT 1 ");
	$jobresult->execute();
	$jobcount = $jobresult->rows;
	if ($jobcount > 0)
	{
		while (my $jobrow = $jobresult->fetchrow_hashref) {
			$job_id = $jobrow->{id};
			$job_cmd = $jobrow->{cmd};	
			$content_type = $jobrow->{content_type};	
			$job_prio = $jobrow->{prio};
			$job_filename = $jobrow->{filename};
			$job_uuid = $jobrow->{uuid};
		}
	}
	
}



sub read_encoder_db {

	$result = $dbh->prepare("SELECT * FROM cc_encoder ORDER BY encoder_used_slots LIMIT 1");
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
	$dbh = DBI->connect('DBI:mysql:'.$mysql_db.';host='.$mysql_host, $mysql_user, $mysql_password) || die "Could not connect to database: $DBI::errstr";
    	$dbh->do("delete from ".$encoder_table." where encoder_ip='".$ipaddr."'");
	$dbh->disconnect();	
    	exit;  
}

