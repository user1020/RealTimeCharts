##
#ver 0.01
#TODO feature
#--- allow dynamic addition of curves.
#########################################################
use IO::Socket;
use IO::Select;
use Data::Dumper;

my $MAX_NUM = 60; #max data points.

my $offset = 0;
my @points = ();

my %ips;
my @events;
my @a;
my @ipsInThisFrame = ();
my @ips2study = ();

my ($isContinue, $intermediate,$ip2search) = (0,0, "none");
my $all_pos = 0;
my $ip_pos  = 0;
my $frameCnt = 0;
my $maxFrames = 22; #at most display this many event per frames.
$eventId = 0;
$ipField = 3; 
$s = IO::Select->new();


#open ($logFd, "tail -f $ARGV[0]|") || die "Failed to open $ARGV[0]\n";
#$s->add($logFd);

my @fds = ();
my @values = ();
my $index = 0;
$fileId = -1;
my @files = ();
my $initTs = time();
my $prevTs = 0;
my $ts = 0;
my @stats = (0,0,0);
my @v;
my $num;

$cfgInJson = readCfgFile("cfg");

print "fileId=$fileId\n";
for ($i=0; $i<=$fileId; $i ++) {
	printf "|%s\n", join(",", @{$files[$i]}); 
}


$srvSock = IO::Socket::INET->new( Proto    => 'tcp', 
				LocalPort => 8081,
				Reuse     => 1,
				Listen    => 10	) ||
		 die "failed to open server sock for port 8880 $!\n";
$s->add($srvSock);
my %clientSocks;
$clientSock = "";
select(STDOUT);
$| = 1;
while (1) {
	foreach $sock ($s->can_read(1)) {
		if ($sock eq $srvSock) {
			$clientSock = $sock->accept();
			$s->add($clientSock);
			$clientSocks{$clientSock} = $clientSock;
			#printf("got client connection\n");
			next;
		} 
		if (defined  $clientSocks{$sock}) {
			$clientSock = $sock;
			#print "got client sock\n";
			handleClient();
			next;
		}
		for ($i=0; $i<=$fileId; $i ++) {
			if ($sock eq $fds[$i]) {
				$line = <$sock>;
				#print "fd $i has data\n";
				foreach $e (@{$files[$i]}) {
					$pattern = $regexs[$e];
					if ($line =~ /$pattern/) { 
						$values[$e] = $1;
						#printf "value is $1 at %d\n", time();
					}
				}
			}
		}
	}
}


sub handleClient {
	$buff = "";
	my $ret = recv($clientSock, $buff, 0x1000, 0);
	#print "recved1 buff $buff";
	if ((! defined $ret) || (length($buff) == 0)) {
		print("recved null data\n");
		$s->remove($clientSock); close $clientSock; return;
	}
	if ($buff =~ /^(GET|POST) \/ajax\/(\S*).*\r\n\r\n/s) {
		handleDynamicReq($2);
	} elsif ($buff =~ /^GET \/(\S*)/) {
		$f = $1;
		if ($f eq "") { $f = "index.html";}
		sendStaticPage($f);
	} else {
		print "unexpected req $buff";
	}
	$s->remove($clientSock);
	close $clientSock;
}

sub sendStaticPage {	
	my ($f) = @_;
	if ($f =~ /\.([^\.]+)$/) { $extension = $1; }
	if ($extension eq "js") { $extension = "javascript";}
	#my $ctType = $ctMapping{$extension}/$extension;
	my $buf;
	print "debug f=$f\n";
	if ($f eq "index.html") {
		$buf = getBasicHtml($query);
	} else {
	    $buf = readFile($f);
    }
	my $len = length($buf);
	print "file $f with $len bytes\n";
	my $msg = "HTTP/1.1 200 OK\r\nContent-Type: text/$extension\r\nContent-Length: $len\r\n\r\n$buf";
	#printf "msg len %d\n", length($msg);
	send($clientSock, $msg,0);
}


sub handleDynamicReq {
	my ($uri) = @_;
	my $msg;
	my $i, $j;
	my $l;
	my $zoomFactor = 1;

	#print "uri=$uri data=$postData\n";
	if ($uri =~ /^poll/) {
		$ts = (time() - 18000)*1000 ;
		$msg = "";
		for ($i=0; $i < $index; $i++) {
			if ($msg ne "") { $msg .= ",";}
			$msg .= sprintf("[%d, $values[$i]]", $ts);
		}
		$msg = "[$msg]";
	} 
	my $len = length($msg);
	$msg = "HTTP/1.1 200 OK\r\nContent-Type: text/json\r\nContent-Length: $len\r\n\r\n$msg";
	#printf "msg len %d\n", length($msg);
	send $clientSock, $msg, 0;
	
}


sub readFile {
	my $f = shift;
	open (FD, "<$f") || return "";
	read(FD, $buff, 0x1000000);
	close FD;
	return $buff;
}

sub mysplit {
	my $str = shift;
	my $inQuote = 0;
	@a = ();
	while (1) {
		if ($inQuote) {
			$str =~ /^([^\"]*)\"/;
			push @a, $1; $str = $'; $inQuote = 0; next;
		}
		if ($str =~ /^\s*\"/) {
			$inQuote = 1; 
		} elsif ($str =~ /^\s*([^\s]+)/)  {
			push @a, $1;
		} else { last;}
		$str = $';
	}
}

sub match {
	return 1;
}

sub getBasicHtml {
	my $query = shift;
	print "query=$query\n";
	my $ip = "none";
	if ($query =~ /ip=/) {
		$ip = $'; print "ip=$ip\n";
	}
	my $code = q|
<html>
<header>
	<script src="js/jquery.min.js"></script>
	<script src="js/highstock.js"></script>
	<script src="js/modules/exporting.js"></script>
</header>
<body>
<div id="container0" style="height: 300px; min-width: 500px"></div>
<div id="container1" style="height: 300px; min-width: 500px"></div>
<script>
var seriesVars = [];
var charts = new Array();// global
|;
	$code .= $cfgInJson;
	$code .= q|
/**
 * Request data from the server, add it to the graph and set a timeout to request again
 */
function requestData() {
    request = $.ajax({
        url: '/ajax/poll',
        cache: false
    });
	request.done(function(points) {
		            var series;
            for (i=0; i<points.length; i++) {
				chartId  = desc[i].chart;
				seriesId = desc[i].series;
				//console.log("debugA " + chartId + " " + seriesId);
				series = charts[chartId].series[seriesId];     shift = series.data.length > 40;
				charts[chartId].series[seriesId].addPoint(points[i], true, shift);
			}
            setTimeout(requestData, 1000);    
	})
}

$(document).ready(function() {
	for (i=0; i<2; i++) {
		seriesVars[i] = [];
	}
	for (i=0; i<desc.length; i++) {
		console.log("debug " + desc[i].chart + " " + desc[i].series);
		seriesVars[desc[i].chart][desc[i].series] = {name: desc[i].name, data: [] };
	}
	for (i=0; i<2; i++) {
		console.log(seriesVars[i]);
	}
	for (i=0; i<2; i++) {
		charts[i] = new Highcharts.Chart({
			chart: {
				renderTo: 'container'+i,
				defaultSeriesType: 'spline',
				events: {
					load: requestData
				}
			},
			title: {
				text: chartNames[i]
			},
			xAxis: {
				type: 'datetime',
				tickPixelInterval: 150,
				maxZoom: 20 * 1000
			},
			yAxis: {
				minPadding: 0.2,
				maxPadding: 0.2,
				title: {
					text: 'Value',
					margin: 80
				}
			},
			series: seriesVars[i]
		});   
	}  
});
</script></body></html>
	|;
	return $code;
}

sub readCfgFile {
	my $f = shift;
	my $chartNames = "";
	my $ret = "";
	open (CFGFD, "<$f") || die "failed to open cfg file $f $!\n";
	while (<CFGFD>) {
		if (/^#/) { next;}
		if (/^\s*[\r\n]+/) { next;}
		$line = $_; $line =~ s/[\r\n]+//;
		if ($line =~ /^chart\s+(\d+)\s+/) {
			if ($chartNames ne "") {  $chartNames .= ","; }
			$chartNames .= "\"$'\"";
		} elsif ($line =~ /^\S/) { #file
			$fileId ++;
			open ($fds[$fileId], "tail -f $line | ") || die "Failed to open $line $!\n";
			$s->add($fds[$fileId]);
		}  else {
			@a = split(/\s+/, $line, 5);
			if ($ret ne "") { $ret .= ",\n";}
			$ret .= "{name: \"$a[3]\", chart: $a[1], series: $a[2] } ";
			$regexs[$index] = $a[4];
			if (! defined $files[$fileId]) { $files[$fileId] = [];}
			push (@{$files[$fileId]}, $index);
			$values[$index] = 0;
			$index ++;
		}
	}
	close CFGFD;
	return "var chartNames = [$chartNames];\ndesc = [$ret];\n";
}
