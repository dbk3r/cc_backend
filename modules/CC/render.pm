package CC::render;
 
use strict;
use warnings;

use Exporter qw(import);
use IPC::Run qw( start pump );

our @EXPORT_OK = qw(render);


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

1;
