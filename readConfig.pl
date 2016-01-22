use Config::Simple;

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
$mediainfo_bin = $cfg->param('mediainfo');
$bmxtranswrap_bin = $cfg->param('bmxtranswrapr');
$curl_bin = $cfg->param('curl');
$content_dir = $cfg->param('content_dir');

$nodeinstance = $cfg->param('nodeinstance');

@job_types_array = ("'copy'","'move'","'delContent'","'delContentDB'");
