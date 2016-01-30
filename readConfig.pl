use Config::Simple;
use Getopt::Std;
 

our %options=();
getopts("hwti:", \%options);

if (defined $options{h})
{
	print "options:\n -i [instanceName] -w [run_as_ioWorker] -t [run_as_transcoder]\n";
	exit;
}


$cfg = new Config::Simple();
$cfg->read('encoder.cfg');

$mysql_host = $cfg->param('mysql_host');
$mysql_user = $cfg->param('mysql_user');
$mysql_password = $cfg->param('mysql_password');
$mysql_db = $cfg->param('mysql_db');

$encoder_table = $cfg->param('encoder_table');
$jobs_table = $cfg->param('jobs_table');
$content_table = "cc_content";

$max_encoding_slots = $cfg->param('max_encoding_slots');

$ffmpeg_bin = $cfg->param('ffmpeg');
$ffmbc_bin = $cfg->param('ffmbc');
$blender_bin = $cfg->param('blender');
$blender_thumbnailer_bin  = $cfg->param('blender-thumbnailer');
$blender_info_bin  = $cfg->param('blender-info');
$mediainfo_bin = $cfg->param('mediainfo');
$bmxtranswrap_bin = $cfg->param('bmxtranswrap');
$curl_bin = $cfg->param('curl');
$content_dir = $cfg->param('content_dir');
if (defined $options{i})
{
	$nodeinstance = $options{i};
	
}
else
{
	$nodeinstance = $cfg->param('nodeinstance');
}

$log_file = $cfg->param('logfile');

@job_essentials_array = ("'test'");

