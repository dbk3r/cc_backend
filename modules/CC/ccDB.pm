package CC::ccDB;
use strict;
use warnings;
use DBI;
use Exporter qw(import);

our @EXPORT_OK = qw(ccConnect ccClose);


sub ccConnect{
	my $host = shift;
	my $user = shift;
	my $pass = shift;
	my $db = shift;
	my $dbh = DBI->connect('DBI:mysql:'.$db.';host='.$host, $user, $pass) || die "Could not connect to database: $DBI::errstr"; 

return $dbh;

}

sub ccClose{
	my $conn = shift;
	$conn->disconnect();
}

1;
