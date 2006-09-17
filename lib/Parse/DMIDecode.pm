############################################################
#
#   $Id: DMIDecode.pm 772 2006-09-17 20:27:14Z nicolaw $
#   Parse::DMIDecode - Interface to SMBIOS under Linux using dmidecode
#
#   Copyright 2006 Nicola Worthington
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
############################################################

package Parse::DMIDecode;
# vim:ts=4:sw=4:tw=78

use strict;
use Carp qw(croak cluck confess carp);
use vars qw($VERSION $DEBUG @TYPES %GROUPS);

$VERSION = '0.00' || sprintf('%d', q$Revision: 772 $ =~ /(\d+)/g);
$DEBUG ||= $ENV{DEBUG} ? 1 : 0;

@TYPES = ('BIOS', 'System', 'Base Board', 'Chassis', 'Processor',
	'Memory Controller', 'Memory Module', 'Cache', 'Port Connector',
	'System Slots', 'On Board Devices', 'OEM Strings',
	'System Configuration Options', 'BIOS Language', 'Group Associations',
	'System Event Log', 'Physical Memory Array', 'Memory Device',
	'32-bit Memory Error', 'Memory Array Mapped Address',
	'Memory Device Mapped Address', 'Built-in Pointing Device',
	'Portable Battery', 'System Reset', 'Hardware Security',
	'System Power Controls', 'Voltage Probe', 'Cooling Device',
	'Temperature Probe', 'Electrical Current Probe',
	'Out-of-band Remote Access', 'Boot Integrity Services', 'System Boot',
	'64-bit Memory Error', 'Management Device', 'Management Device Component',
	'Management Device Threshold Data', 'Memory Channel', 'IPMI Device',
	'Power Supply');

%GROUPS = (
		'bios'      => [ qw(0 13) ],
		'system'    => [ qw(1 12 15 23 32) ],
		'baseboard' => [ qw(2 10) ],
		'chassis'   => [ qw(3) ],
		'processor' => [ qw(4) ],
		'memory'    => [ qw(5 6 16 17) ],
		'cache'     => [ qw(7) ],
		'connector' => [ qw(8) ],
		'slot'      => [ qw(9) ],
	);



#
# Methods
#

sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;
	my $self = { @_ };

	#my @commands = qw(dmidecode biosdecode);
	my @commands = qw(dmidecode);
	my $validkeys = join('|',@commands);
	cluck('Unrecognised parameters passed: '.
		join(', ',grep(!/^$validkeys$/,keys %{$self})))
		if (grep(!/^$validkeys$/,keys %{$self}) && $^W);

	for my $command (@commands) {
		croak "Command $command '$self->{$command}'; file not found"
			if defined $self->{$command} && !-f $self->{$command};
	}

	if (!defined $self->{dmidecode}) {
		require File::Which;
		for my $command (@commands) {
			$self->{$command} = File::Which::which($command)
				if !defined $self->{$command};
		}
	}

	bless($self,$class);
	DUMP($class,$self);
	return $self;
}


sub probe {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	my ($cmd) = $self->{dmidecode} =~ /^([\/\.\_\-a-zA-Z0-9 >]+)$/;
	TRACE($cmd);

	my $fh;
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV PATH)};
	open($fh,'-|',$cmd) || croak "Unable to open file handle for command '$cmd': $!";
	while (local $_ = <$fh>) {
		$self->{raw} .= $_;
	}
	close($fh) || carp "Unable to close file handle for command '$cmd': $!";

	return $self->parse($self->{raw});
}


sub parse {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	$self->{parsed} = $self->_parse($_[0]);
	DUMP('$self',$self);
	return $self->{parsed}->{structures};
}


sub keyword {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	return unless defined $self->{parsed}->{handle};

	my $type = '';
	my $keyword = shift || '';
	($type,$keyword) = $keyword =~ /^\s*(\S+?)\-(\S+)\s*$/;
	croak 'Missing or invalid keyword where keyword was expected'
		unless defined $keyword && $keyword &&
		defined $type && defined $GROUPS{$type};

	my $dmitypes = '('. join('|',@{$GROUPS{$type}}) .')';
	TRACE("$type -> $keyword -> $dmitypes");

	my @rtn;

	for my $handle (grep(/\*$dmitypes$/,keys %{$self->{parsed}->{handle}})) {
		TRACE(" > $handle");
		for my $name (keys %{$self->{parsed}->{handle}->{$handle}->{data}}) {
			TRACE(" > $handle > $name");
			for my $key (keys %{$self->{parsed}->{handle}->{$handle}->{data}->{$name}}) {
				TRACE(" > $handle > $name > $key"); 
				(my $comp_key = lc($key)) =~ s/\s+/-/g;
				if ($comp_key eq $keyword) {
					TRACE(" > $handle > $name > $key > $comp_key > *MATCH*");
					if (wantarray && @{$self->{parsed}->{handle}->{$handle}->{data}->{$name}->{$key}->[1]} >= 1) {
						TRACE("[1]");
						push @rtn, $self->{parsed}->{handle}->{$handle}->{data}->{$name}->{$key}->[1];
					} else {
						TRACE("[0]");
						push @rtn, $self->{parsed}->{handle}->{$handle}->{data}->{$name}->{$key}->[0];
					}
				}
			}
		}
	}

	DUMP('@rtn',\@rtn);

	if (@rtn == 1) {
		return wantarray ? ref($rtn[0]) eq 'ARRAY' ? @{$rtn[0]} : ($rtn[0]) : $rtn[0];
	} elsif (@rtn > 1) {
		carp "Multiple (". scalar(@rtn) .") matches found; unable to return a specific value";
	}
	return;
}



#
# Private methods
#

sub _parse {
	my ($self,$str) = @_;
	my %data;
	my %strct;

	for (split(/\n/,$str)) {
		next if /^\s*$/;

		# dmidecode headers
		if (/^# dmidecode ([\d\.]+)\s*$/) {
			$data{dmidecode} = $1;
		} elsif (/^(\d+) structures occupying (\d+) bytes?\.\s*$/) {
			$data{structures} = $1;
			$data{bytes} = $2;
		} elsif (/^SMBIOS ([\d\.]+) present\.?\s*$/) {
			$data{smbios} = $1;
		} elsif (/^Table at ([0-9A-Fx]+)\.?\s*$/) {
			$data{location} = $1;

		# data
		} elsif (/^Handle ([0-9A-Fx]+)(?:, DMI type (\d+), (\d+) bytes?\.?)?\s*$/) {
			if (keys %strct) {
				_parse_raw(\%strct);
				$data{handle}->{"$strct{handle}*$strct{dmitype}"} = {%strct};
				%strct = ();
			}
			$strct{handle} = $1;
			$strct{dmitype} = $2 if defined $2;
			$strct{bytes} = $3 if defined $3;
		} elsif (defined $strct{handle} &&
				/^\s*DMI type (\d+), (\d+) bytes?\.?\s*$/) {
			$strct{dmitype} = $1 if defined $1;
			$strct{bytes} = $2 if defined $2;
		} else {
			$strct{raw} = [] unless defined $strct{raw};
			push @{$strct{raw}}, $_;
		}
	}

	if (keys %strct) {
		_parse_raw(\%strct);
		$data{handle}->{"$strct{handle}*$strct{dmitype}"} = {%strct};
	}

	carp sprintf("Only parsed %d structures when %d were expected",
			scalar(keys(%{$data{handle}})), $data{structures})
		if scalar(keys(%{$data{handle}})) != $data{structures};

	return \%data;
}


sub _parse_raw {
	my $ref = shift;

	my $name_indent = 0;
	my $key_indent  = 0;
	my $name = '';
	my $key = '';

	my @errors;
	my %strct;

	for (my $l = 0; $l < @{$ref->{raw}}; $l++) {
		local $_ = $ref->{raw}->[$l];
		my ($indent) = $_ =~ /^(\s+)/;
		$indent = '' unless defined $indent;
		$indent = length($indent);

		$name_indent = $indent if $l == 0;
		if ($l == 1) {
			if ($indent > $name_indent) { $key_indent = $indent; }
			else { push @errors, "Parser warning: key_indent ($indent) <= name_indent ($name_indent): $_"; }
		}

		# data
		if (/^\s{$name_indent}(\S+.*?)\s*$/) {
			$name = $1;
			$strct{$name} = {};
			$key = '';
		} elsif ($name && /^\s{$key_indent}(\S.*?)(?::|: (\S+.*?))?\s*$/) {
			$key = $1;
			$strct{$name}->{$key}->[0] = $2;
			$strct{$name}->{$key}->[1] = [] unless defined $strct{$name}->{$key}->[1];
		} elsif ($name && $key && $indent > $key_indent && /^\s*(\S+.*?)\s*$/) {
			push @{$strct{$name}->{$key}->[1]}, $1;

		# unknown
		} else { push @errors, "Parser warning: $_"; }
	}

	delete $ref->{raw};
	$ref->{data} = \%strct;
	carp $_ for @errors;
}


sub TRACE {
	return unless $DEBUG;
	carp(shift());
}


sub DUMP {
	return unless $DEBUG;
	eval {
		require Data::Dumper;
		$Data::Dumper::Indent = 2;
		$Data::Dumper::Terse = 1;
		carp(shift().': '.Data::Dumper::Dumper(shift()));
	}
}

1;



=pod

=head1 NAME

Parse::DMIDecode - Interface to SMBIOS under Linux using dmidecode

=head1 SYNOPSIS

 use strict;
 use Parse::DMIDecode ();
 
 my $dmi = new Parse::DMIDecode;
 $dmi->probe;
 
 printf("System: %s, %s",
         $dmi->keyword("system-manufacturer"),
         $dmi->keyword("system-product-name"),
     );

=head1 DESCRIPTION

This module provides an OO interface to SMBIOS information through
the I<dmidecode> command which is known to work under a number of
Linux, BSD and BeOS variants.

=head1 METHODS

=head2 new

 my $dmi = Parse::DMIDecode->new(dmidecode => "/usr/sbin/dmidecode");

=head2 probe

 $dmi->probe;

=head2 parse

 my $raw = `dmidecode`;
 $dmi->parse($raw);

=head2 keyword

 my $ = $dmi->keyword("system-serial-number");

=head1 SEE ALSO

examples/*.pl,
L<http://www.nongnu.org/dmidecode/>,
L<http://linux.dell.com/libsmbios/>,
L<http://sourceforge.net/projects/x86info/>,
L<http://www.dmtf.org/standards/smbios>,
L<biosdecode(8)>, L<dmidecode(8)>, L<vpddecode(8)>

=head1 VERSION

$Id: DMIDecode.pm 772 2006-09-17 20:27:14Z nicolaw $

=head1 AUTHOR

Nicola Worthington <nicolaw@cpan.org>

L<http://perlgirl.org.uk>

If you like this software, why not show your appreciation by sending the
author something nice from her
L<Amazon wishlist|http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority>? 
( http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority )

=head1 COPYRIGHT

Copyright 2006 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut


__END__



