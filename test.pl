use Cwd 'abs_path';
use lib abs_path.'/modules';
use CC::mediainfo qw(videoinfo audioinfo);

do 'readConfig.pl';

print videoinfo($mediainfo_bin, $content_dir, "2c9cff0b-54c3-41ac-baab-9648f8f8d9f1", "Stefan Eiternick1.mp4.mxf", "", "cc_content" )."\n";
print audioinfo($mediainfo_bin, $content_dir, "2c9cff0b-54c3-41ac-baab-9648f8f8d9f1", "Stefan Eiternick1.mp4.mxf", "", "cc_content" )."\n";
