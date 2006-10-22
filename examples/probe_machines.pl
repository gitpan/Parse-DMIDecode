#!/usr/bin/perl -wT

# Database credentials
use constant DBI_DSN     => 'DBI:mysql:database:localhost';
use constant DBI_USER    => 'username';
use constant DBI_PASS    => 'password';

# Where and how to generate a list of hosts to probe
use constant HOSTS_REGEX => qr{([a-zA-|0-9\-\_\.]+)};
use constant HOSTS_SKIP  => qw{(winfs|windows|w2kfs)};
use constant HOSTS_SRC   => '/etc/hosts';

# Remote command to gather information
use constant SSH_CMD     => 'ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey -o CheckHostIP=no -l root -i ~/.ssh/id_dsa_root';
use constant REMOTE_CMD  => 'echo ==dmidecode==; dmidecode; echo ==ifconfig==; ifconfig -a; echo ==distribution==; egrep . /etc/debian_version /etc/redhat-release; echo ==listening==; netstat -ltnu; echo ==routingtable==; netstat -rn; echo ==x86info==; x86info; echo ==lspci==; lspci';


#########################################################
#
#
#    No user servicable parts inside past this point
#
#
#########################################################


use 5.6.1;
use strict;
use DBI qw();
use Parse::DMIDecode qw();

%ENV = (PATH => '/bin:/usr/bin');
$|++;


my $dbh = DBI->connect(DBI_DSN,DBI_USER,DBI_PASS,{AutoCommit => 0});
create_tables() if grep(/createTables?/i,@ARGV);

my $dmi = Parse::DMIDecode->new(nowarnings => 1);
my $skip_regex = HOSTS_SKIP;

for my $machine (sort(get_hostnames())) {
	print "Prcessing $machine ". "." x (50-length($machine));
	print_result('skipped'), next if $machine =~ /$skip_regex/;

	my $data = probe_server($machine);
	if (defined $data->{'failed-to-connect'}) {
		print_result('connect failed');
	} elsif (defined $data->{'system-uuid'} && $data->{'system-uuid'} =~ /^[A-F0-9\-]{36}$/) {
		update_database($data);
		print_result('done');
	} else {
		print_result('no uuid');
	}
}

$dbh->disconnect();


exit;


sub print_result {
	my $str = shift;
	my $width = 15;
	my $dots = $width -  length($str) - 1;
	printf("%s %s\n", '.' x $dots, $str);
}


sub probe_server {
	my $machine = shift;

	my $cmd = sprintf('%s %s "%s" 2>/dev/null', SSH_CMD, $machine, REMOTE_CMD);
	my %raw = (hostname => $machine, 'failed-to-connect' => 1);
	my $group;

	if (open(PH,'-|',$cmd)) {
		while (local $_ = <PH>) {
			if (/^==+(\S+?)==+$/) {
				$group = $1;
				delete $raw{'failed-to-connect'};
			} elsif (defined $group && $group =~ /\S+/) {
				$raw{$group} .= $_;
			} else {
				print $_;
			}
		}
		close(PH);
	}

	return \%raw if defined $raw{'failed-to-connect'};
	return parse_raw_data($machine,\%raw);
}



sub parse_raw_data {
	my ($machine,$raw) = @_;

	# ==dmidecode==
	if (defined $raw->{dmidecode}) {
		$dmi->parse($raw->{dmidecode});
		for (qw(system-uuid system-serial-number system-manufacturer system-product-name)) {
			$raw->{$_} = $dmi->keyword($_);
		}
		$raw->{'physical-cpu-qty'} = 0;
		for my $handle ($dmi->get_handles(group => 'processor')) {
			next unless $handle->keyword('processor-type') =~ /Central Processor/i;
			$raw->{'physical-cpu-qty'}++;
			for (qw(processor-family processor-manufacturer processor-current-speed
				processor-type processor-version processor-signature processor-flags)) {
				my $value = $handle->keyword($_);
				$value = undef if defined $value && $value =~ /Not Specified/i;
				$raw->{$_} = $value if !defined $raw->{$_};
			}
		}
	}

	# ==ifconfig==
	if (defined $raw->{ifconfig}) {
		$raw->{hwaddr} = [()];
		for (split(/\n/,$raw->{ifconfig})) {
			if (my ($if,$hwaddr) = $_ =~ /^(\S+)\s+.+?\s+HWaddr:?\s+(\S+)\s*$/i) {
				push @{$raw->{hwaddr}}, "$hwaddr $if" if $if !~ /:/;
			}
		}
	}

	# ==distribution==
	if (defined $raw->{distribution}) {
		if ($raw->{distribution} =~ /Red Hat Enterprise Linux/m) {
			$raw->{distribution} = 'RHEL';
		} elsif ($raw->{distribution} =~ /Ubuntu/) {
			$raw->{distribution} = 'Ubuntu';
		} elsif ($raw->{distribution} =~ /Red\s*Hat/) {
			$raw->{distribution} = 'RedHat';
		} elsif ($raw->{distribution} =~ /Debian/) {
			$raw->{distribution} = 'Debian';
		} else {
			$raw->{distribution} = 'Linux';
		}
	}	

	return $raw;
}



sub create_tables {
	my @statements;
	my $statement;

	while (local $_ = <DATA>) {
		chomp;
		next if /^\s*(#|\-\-|;)/;
		last if /^__END__$/;
		s/\t/ /;

		if (/;\s*$/) {
			$statement .= $_;
			push @statements, $statement;
			$statement = '';
		} else {
			$statement .= $_;
		}
	}

	for my $statement (@statements) {
		$statement =~ s/;\s*//;
		my $sth = $dbh->prepare($statement);
		$sth->execute;
	}
	$dbh->commit;
}



sub get_model_id {
	my ($make,$model) = @_;
	my $sth = $dbh->prepare('SELECT model_id FROM model WHERE make = ? AND model = ?');
	$sth->execute($make,$model);
	my ($model_id) = $sth->rows == 1 ? $sth->fetchrow_array : undef;

	if (!defined $model_id && $sth->rows <= 1) {
		my $form = undef;
		if ($make =~ /^Dell (Inc\.|Computer Corporation)$/ && $model =~ /^PowerEdge (?:750|([12])\d\d0)$/) {
			$form = defined $1 ? "${1}U" : '1U';
		}
		$sth = $dbh->prepare('INSERT INTO model (make,model,form) VALUES (?,?,?)');
		$sth->execute($make,$model,$form);
		$model_id = $dbh->{'mysql_insertid'};
	}

	$sth->finish;
	return $model_id;
}



sub update_database {
	my $data = shift;

	my $model_id = get_model_id($data->{'system-manufacturer'},$data->{'system-product-name'});

	my $sth = $dbh->prepare('SELECT COUNT(*) FROM machine WHERE uuid = ?');
	$sth->execute($data->{'system-uuid'});
	my ($exists) = $sth->fetchrow_array;

	if ($exists && defined $model_id) {
		$sth = $dbh->prepare('UPDATE machine SET model_id = ?, serial = ? WHERE uuid = ?');
		$sth->execute($model_id,$data->{'system-serial-number'},$data->{'system-uuid'});
	} else {
		$sth = $dbh->prepare('INSERT INTO machine (uuid,serial,model_id) VALUES (?,?,?)');
		$sth->execute($data->{'system-uuid'},$data->{'system-serial-number'},$model_id);
	}

	$sth = $dbh->prepare('SELECT hostname FROM host WHERE hostname = ?');
	$sth->execute($data->{hostname});
	if ($sth->rows) {
		my $sth = $dbh->prepare('UPDATE host SET uuid = ?, os = ? WHERE hostname = ?');
		$sth->execute($data->{'system-uuid'},$data->{distribution},$data->{hostname});
	} else {
		my $sth = $dbh->prepare('INSERT INTO host (hostname,uuid,os) VALUES (?,?,?)');
		$sth->execute($data->{hostname},$data->{'system-uuid'},$data->{distribution});
	}

	$sth = $dbh->prepare('SELECT uuid FROM probes WHERE uuid = ?');
	$sth->execute($data->{'system-uuid'});
	if ($sth->rows) {
		my $sth = $dbh->prepare('UPDATE probes SET listening = ?, routes = ?, dmidecode = ? WHERE uuid = ?');
		$sth->execute($data->{listening},$data->{routes},$data->{dmidecode},$data->{'system-uuid'});
	} else {
		my $sth = $dbh->prepare('INSERT INTO probes (listening,routes,dmidecode,uuid) VALUES (?,?,?,?)');
		$sth->execute($data->{listening},$data->{routes},$data->{dmidecode},$data->{'system-uuid'});
	}

	$sth = $dbh->prepare('SELECT uuid FROM cpu WHERE uuid = ?');
	$sth->execute($data->{'system-uuid'});
	my ($processor_current_speed) = $data->{'processor-current-speed'} =~ /(\d+)/;
	my @processor_flags = ();
	for (@{$data->{'processor-flags'}}) {
		if (/^(\S+)/) { push @processor_flags, $1; }
	}
	my $processor_flags = join(',',@processor_flags);
	my @processor_bindings = ($data->{'processor-manufacturer'},$data->{'processor-family'},
			$data->{'processor-version'},$processor_current_speed,$data->{'processor-signature'},
			$processor_flags,$data->{'physical-cpu-qty'},$data->{'system-uuid'});
	if ($sth->rows) {
		my $sth = $dbh->prepare('UPDATE cpu SET manufacturer = ?, family = ?,
			version = ?, speed = ?, signature = ?, flags = ?, qty = ? WHERE uuid = ?');
		$sth->execute(@processor_bindings);
	} else {
		my $sth = $dbh->prepare('INSERT INTO cpu (manufacturer,family,version,speed,
			signature,flags,qty,uuid) VALUES (?,?,?,?,?,?,?,?)');
		$sth->execute(@processor_bindings);
	}

	$sth = $dbh->prepare('DELETE FROM host WHERE uuid = ? AND hostname != ?');
	$sth->execute($data->{'system-uuid'},$data->{hostname});

	$sth = $dbh->prepare('DELETE FROM nic WHERE uuid = ?');
	$sth->execute($data->{'system-uuid'});
	for (@{$data->{hwaddr}}) {
		my ($hwaddr,$interface) = split(/\s+/,$_);
		next if $interface =~ /:/;
		$hwaddr =~ s/[^0-9a-f]+//gi;
		$sth = $dbh->prepare('INSERT INTO nic (hwaddr,uuid,interface) VALUES (?,?,?)');
		$sth->execute($hwaddr,$data->{'system-uuid'},$interface);
	}

	$sth->finish;
	$dbh->commit;
}



sub get_hostnames {
	print "Getting hostnames ...";

	my @data;
	if (-f HOSTS_SRC && -r HOSTS_SRC) {
		if (open(FH,'<',HOSTS_SRC)) {
			@data = <FH>;
			close(FH);
		}
	} else {
		eval {
			require LWP::Simple;
			@data = split(/\n/, LWP::Simple::get(HOSTS_SRC));
		};
		warn $@ if $@;
	}

	my $regex = HOSTS_REGEX;
	my %hosts;
	for (@data) {
		if (/$regex/) {
			$hosts{$1} = 1;
		}
	}

	my $hosts = scalar(keys %hosts) || 0;
	print " found $hosts host".($hosts == 1 ? '' : 's').".\n";
	return sort keys %hosts;
}



__DATA__
DROP TABLE IF EXISTS nic;
DROP TABLE IF EXISTS cpu;
DROP TABLE IF EXISTS probes;
DROP TABLE IF EXISTS service;
DROP TABLE IF EXISTS host;
DROP TABLE IF EXISTS machine;
DROP TABLE IF EXISTS model;
#DROP TABLE IF EXISTS contact;
#DROP TABLE IF EXISTS history;

CREATE TABLE model (
		model_id INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
		make VARCHAR(32) NOT NULL,
		model VARCHAR(32) NOT NULL,
		form ENUM('1U','2U','3U','Desktop','MiniTower','MidiTower','FullTower')
	) ENGINE=InnoDB;

CREATE TABLE machine (
		uuid CHAR(36) NOT NULL PRIMARY KEY,
		serial VARCHAR(16),
		model_id INT UNSIGNED,
		FOREIGN KEY (model_id) REFERENCES model(model_id)
	) ENGINE=InnoDB;

CREATE TABLE host (
		hostname VARCHAR(32) NOT NULL PRIMARY KEY,
		uuid CHAR(36) NOT NULL,
		os ENUM('Debian','RedHat','RHEL','Ubuntu','SuSE','Windows','Linux'),
		FOREIGN KEY (uuid) REFERENCES machine(uuid) ON DELETE CASCADE
	) ENGINE=InnoDB;

CREATE TABLE service (
		hostname VARCHAR(32) NOT NULL,
		servicename VARCHAR(32) NOT NULL,
		description VARCHAR(255),
		type ENUM('Production','Staging','Development','Infrastructure','Research','Other') NOT NULL,
		PRIMARY KEY (hostname,servicename),
		FOREIGN KEY (hostname) REFERENCES host(hostname) ON DELETE CASCADE
	) ENGINE=InnoDB;

CREATE TABLE nic (
		hwaddr CHAR(12) NOT NULL,
		uuid CHAR(36) NOT NULL,
		interface CHAR(4),
		PRIMARY KEY (hwaddr,uuid),
		FOREIGN KEY (uuid) REFERENCES machine(uuid) ON DELETE CASCADE
	) ENGINE=InnoDB;

CREATE TABLE cpu (
		uuid CHAR(36) NOT NULL PRIMARY KEY,
		manufacturer VARCHAR(16),
		family VARCHAR(16),
		version VARCHAR(64),
		speed INT(4) UNSIGNED,
		signature VARCHAR(64),
		flags VARCHAR(255),
		qty INT(2) UNSIGNED,
		FOREIGN KEY (uuid) REFERENCES machine(uuid) ON DELETE CASCADE
	) ENGINE=InnoDB;

CREATE TABLE probes (
		uuid CHAR(36) NOT NULL PRIMARY KEY,
		routes TEXT,
		listening TEXT,
		dmidecode TEXT,
		FOREIGN KEY (uuid) REFERENCES machine(uuid) ON DELETE CASCADE
	) ENGINE=InnoDB;

__END__


