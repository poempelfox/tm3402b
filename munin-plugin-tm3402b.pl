#!/usr/bin/perl -w

# You should put a symlink to this plugin into the munin plugindir.
#
# If you want to show the modem status under the hostname of your router,
# the name of the symlink should be formed like this:
#  SOMETHING_HOSTNAME-OR-IP, e.g. tm3402bstats_192.168.100.1
# HOSTNAME-OR-IP should be the IP of the modem.
# Note: In this case you can only feed info from one modem per host into munin.
#
# If you want to show the modem status as an individual host in munin instead,
# use the following naming scheme for the symlink instead:
#  HOSTNAME-OR-IP_SOMETHING,  e.g. 192.168.100.1_tm3402bstats
# In this case you will also have to configure your munin-server accordingly to
# query the new "host" (called virtual node in munin lingo).
#
# You can use environment variables to configure this script - you'll
# definitely need to do that if you changed the default username/password
# on the modem. This has to go into the munin plugin configuration on the host
# where this script will be executed.
#
# The following variables are supported:
#   hostname      Hostname or IP of the modem  (default: 192.168.100.1)

# Some tuneables:
# Timeout for requests.
my $timeout = 10; # the LWP default of 180 secs would be way too long

# ----------------------------------------------------------------------------

use LWP::UserAgent;

# Par. 0: Hostname/IP
# Returns: The contents of the website
sub getmodemstatuspage($) {
  my $hn = shift();
  my $ua = LWP::UserAgent->new();
  $ua->agent($0);
  $ua->timeout($timeout);
  $ua->requests_redirectable([]); # Do not automatically follow redirects
  $ua->ssl_opts( 'verify_hostname' => 0, 'SSL_verify_mode' => 0x00);
  $res = $ua->get("https://${hn}/cgi-bin/status_cgi");
  unless ($res->is_success()) {
    print("# ERROR fetching status info: " . $res->status_line . "\n");
    return undef;
  }
  my $rv = $res->content();
  return $rv;
}

# Par. 0: The full webpage
# Par. 1: The headline above the table we're interested in.
# Returns: The first table below that headline, with <table> tags already stripped away.
sub getwpsection($$) {
  my $wp = $_[0];
  my $se = $_[1];
  $wp =~ s|.*${se}\s+</h.>||sg;
  $wp =~ s|</table>.*||sg;
  $wp =~ s/.*?<table[^>]*>//sg;
  return $wp;
}

# Par. 0: the table to be parsed
sub parsetable($) {
  my $s = $_[0];
  my @res = ();
  my $c = 0; my $r = 0;
  while ($s =~ m|<tr[^>]*>(.*?)</tr>|si) {
    my $actrow = $1;
    my @allcols = ();
    $c = 0;
    while ($actrow =~ m|<td[^>]*>(.*?)</td>|si) {
      push(@allcols, $1);
      $c++;
      $actrow=~s|<td[^>]*>(.*?)</td>||si;
    }
    push(@res, \@allcols);
    $r++;
    $s =~ s|<tr[^>]*>(.*?)</tr>||si;
  }
  return @res;
}

if ((@ARGV > 0) && ($ARGV[0] eq "autoconf")) {
  print("No\n");
  exit(0);
}
my $progname = $0;
my $hostname = '192.168.100.1';  # This is the default ip mandated by the docsis standard, so this very likely will work.
my $fakehost = '';
if ($progname =~ m/([a-zA-Z0-9]+\.[a-zA-Z0-9.]+)_.+/) {
  $fakehost = $1;
  $hostname = $1;
} elsif ($progname =~ m/.+_(.+)/) {
  $hostname = $1;
}
if (defined($ENV{'hostname'})) { $hostname = $ENV{'hostname'} }
$modemsp = getmodemstatuspage($hostname);
unless (defined($modemsp)) {
  exit(1);
}
my $dsqams = getwpsection($modemsp, "Downstream QAM");
my @dsqamt = parsetable($dsqams);
my $usqams = getwpsection($modemsp, "Upstream QAM");
my @usqamt = parsetable($usqams);
#for ($r = 0; $r < 5; $r++) {
#  print("[$r]: " . $dsqamt[$r] . "\n");
#  for ($c = 0; $c <5; $c++) {
#    print("[$r][$c]: " . $dsqamt[$r]->[$c] . "\n");
#  }
#}
if ((@ARGV > 0) && ($ARGV[0] eq "config")) {
  if (length($fakehost) > 0) { print("host_name $fakehost\n"); }
  
  print("multigraph tm3402b_ds_qamlev\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream QAM levels\n");
  print("graph_args --base 1000 --lower-limit 0\n");
  print("graph_vlabel bits per symbol\n");
  print("graph_info This shows what QAM-level is used on an downstream-channel and thus, how many bits are packed into one symbol. For example, QAM16 = 4 bits per symbol, QAM64 = 6, QAM256 = 8. Lower QAM numbers are more robust against interference, but also mean lower transfer speeds. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dsqamlev_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_ds_freq\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream Frequencies\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel MHz\n");
  print("graph_info This shows what frequency is used by which Downstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dsfreq_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_ds_power\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream Power\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel dBmV\n");
  print("graph_info This shows what the power is on each Downstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dspower_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_ds_snr\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream SNR\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel dB\n");
  print("graph_info This shows what the signal-to-noise-ration (SNR) is on each Downstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dssnr_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_ds_octets\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream octets\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel who knows\n");
  print("graph_info This shows whatever the 'octets' column on the modem status page shows. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dsoctets_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type DERIVE\n");
      print("${fl}.min 0\n");
    }
  }

  print("multigraph tm3402b_ds_coerr\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream corrected errors\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel errors/s\n");
  print("graph_info This shows how many errors per second were corrected on each Downstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dscoerr_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type DERIVE\n");
      print("${fl}.min 0\n");
    }
  }

  print("multigraph tm3402b_ds_ucerr\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Downstream uncorrected errors\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel errors/s\n");
  print("graph_info This shows how many uncorrected errors per second were on each Downstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @dsqamt; $r++) {
    if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "dsucerr_dcid" . $dsqamt[$r]->[1];
      print("${fl}.label DCID " . $dsqamt[$r]->[1] . "\n");
      print("${fl}.type DERIVE\n");
      print("${fl}.min 0\n");
    }
  }

  print("multigraph tm3402b_us_qamlev\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Upstream QAM levels\n");
  print("graph_args --base 1000 --lower-limit 0\n");
  print("graph_vlabel bits per symbol\n");
  print("graph_info This shows what QAM-level is used on an upstream-channel and thus, how many bits are packed into one symbol. For example, QAM16 = 4 bits per symbol, QAM64 = 6, QAM256 = 8. Lower QAM numbers are more robust against interference, but also mean lower transfer speeds. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @usqamt; $r++) {
    if ($usqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "usqamlev_ucid" . $usqamt[$r]->[1];
      print("${fl}.label UCID " . $usqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_us_freq\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Upstream Frequencies\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel MHz\n");
  print("graph_info This shows what frequency is used by which Upstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @usqamt; $r++) {
    if ($usqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "usfreq_ucid" . $usqamt[$r]->[1];
      print("${fl}.label UCID " . $usqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  print("multigraph tm3402b_us_power\n");
  print("graph_category cablemodem\n");
  print("graph_title TM3402b Upstream Power\n");
  print("graph_args --base 1000\n");
  print("graph_vlabel dBmV\n");
  print("graph_info This shows what the power is on each Upstream CID. This only shows the <= DOCSIS 3.0 channels.\n");
  for ($r = 0; $r < @usqamt; $r++) {
    if ($usqamt[$r]->[1] =~ m/^\d+$/) {
      my $fl = "uspower_ucid" . $usqamt[$r]->[1];
      print("${fl}.label UCID " . $usqamt[$r]->[1] . "\n");
      print("${fl}.type GAUGE\n");
    }
  }

  exit(0);
}

print("multigraph tm3402b_ds_qamlev\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dsqamlev_dcid" . $dsqamt[$r]->[1];
    my $qaml = -1;
    if ($dsqamt[$r]->[5] =~ m/(\d+)QAM/) {
      $qaml = int(log($1)/log(2));
    }
    print("${fl}.value $qaml\n");
  }
}

print("multigraph tm3402b_ds_freq\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dsfreq_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[2] =~ m/([0-9.]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_ds_power\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dspower_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[3] =~ m/([0-9\-.]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_ds_snr\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dssnr_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[4] =~ m/([0-9\-.]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_ds_octets\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dsoctets_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[6] =~ m/([0-9]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_ds_coerr\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dscoerr_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[7] =~ m/([0-9]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_ds_ucerr\n");
for ($r = 0; $r < @dsqamt; $r++) {
  if ($dsqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "dsucerr_dcid" . $dsqamt[$r]->[1];
    if ($dsqamt[$r]->[8] =~ m/([0-9]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_us_qamlev\n");
for ($r = 0; $r < @usqamt; $r++) {
  if ($usqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "usqamlev_ucid" . $usqamt[$r]->[1];
    my $qaml = -1;
    if ($usqamt[$r]->[6] =~ m/(\d+)QAM/) {
      $qaml = int(log($1)/log(2));
    } elsif ($usqamt[$r]->[6] =~ m/QPSK/) {
      $qaml = 2; # like 4QAM
    }
    print("${fl}.value $qaml\n");
  }
}

print("multigraph tm3402b_us_freq\n");
for ($r = 0; $r < @usqamt; $r++) {
  if ($usqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "usfreq_ucid" . $usqamt[$r]->[1];
    if ($usqamt[$r]->[2] =~ m/([0-9.]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

print("multigraph tm3402b_us_power\n");
for ($r = 0; $r < @usqamt; $r++) {
  if ($usqamt[$r]->[1] =~ m/^\d+$/) {
    my $fl = "uspower_ucid" . $usqamt[$r]->[1];
    if ($usqamt[$r]->[3] =~ m/([0-9\-.]+)/) {
      print("${fl}.value $1\n");
    }
  }
}

exit(0);
#print($dslsp);
# Remove non-tables, colors, table attributes and all that useless stuff
$dslsp =~ s/(<[a-zA-Z]*) (.*?)>/$1>/sg;
$dslsp =~ s|.*?<table>(.*)</table>.*|$1|sgi;
$dslsp =~ s|</{0,1}font>||g;
if (defined($ENV{'VERBOSE'}) && ($ENV{'VERBOSE'} eq '1')) {
  print("$dslsp\n");
}
my $curdnrate = 'U';
my $curuprate = 'U';
my $attdnrate = 'U';
my $attuprate = 'U';
my $snrmargindn = 'U';
my $snrmarginup = 'U';
my $attenuationdn = 'U';
my $attenuationup = 'U';
my $crcerrsdn = 'U';
my $crcerrsup = 'U';
my $fecsdn = 'U';
my $fecsup = 'U';
my $esdn = 'U';
my $esup = 'U';
my $sesdn = 'U';
my $sesup = 'U';
my $lossdn = 'U';
my $lossup = 'U';
my $uasdn = 'U';
my $uasup = 'U';
if ($dslsp =~ m!Attainable Rate</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $attdnrate = int($1) * 1000;
  $attuprate = int($2) * 1000;
}
if ($dslsp =~ m!Actual Rate</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $curdnrate = int($1) * 1000;
  $curuprate = int($2) * 1000;
}
if ($dslsp =~ m!SNR Margin</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $snrmargindn = $1;
  $snrmarginup = $2;
}
if ($dslsp =~ m!Attenuation</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $attenuationdn = $1;
  $attenuationup = $2;
}
if ($dslsp =~ m!<td>CRC</td><td>(.*?)</td><td>(.*?)</td>!) { # different because of colspan=2!
  $crcerrsdn = int($1);
  $crcerrsup = int($2);
}
if ($dslsp =~ m!FECS</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $fecsdn = int($1);
  $fecsup = int($2);
}
if ($dslsp =~ m!<td>ES</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $esdn = int($1);
  $esup = int($2);
}
if ($dslsp =~ m!<td>SES</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $sesdn = int($1);
  $sesup = int($2);
}
if ($dslsp =~ m!<td>LOSS</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $lossdn = int($1);
  $lossup = int($2);
}
if ($dslsp =~ m!<td>UAS</td><td>(.*?)</td><td>.*?</td><td>(.*?)</td>!) {
  $uasdn = int($1);
  $uasup = int($2);
}
if (length($fakehost) > 0) { print("host_name $fakehost\n"); }
print("multigraph vig130_datarates\n");
print("attdnrate.value $attdnrate\n");
print("attuprate.value $attuprate\n");
print("curdnrate.value $curdnrate\n");
print("curuprate.value $curuprate\n");
print("multigraph vig130_snrmargins\n");
print("snrmargindn.value $snrmargindn\n");
print("snrmarginup.value $snrmarginup\n");
print("multigraph vig130_attenuation\n");
print("attenuationdn.value $attenuationdn\n");
print("attenuationup.value $attenuationup\n");
print("multigraph vig130_errors1_dn\n");
print("crcerrsdn.value $crcerrsdn\n");
print("fecsdn.value $fecsdn\n");
print("esdn.value $esdn\n");
print("sesdn.value $sesdn\n");
print("lossdn.value $lossdn\n");
print("uasdn.value $uasdn\n");
print("multigraph vig130_errors1_up\n");
print("crcerrsup.value $crcerrsup\n");
print("fecsup.value $fecsup\n");
print("esup.value $esup\n");
print("sesup.value $sesup\n");
print("lossup.value $lossup\n");
print("uasup.value $uasup\n");
