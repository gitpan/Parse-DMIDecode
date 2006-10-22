############################################################
#
#   $Id: DMIDecode.pm 803 2006-10-22 11:36:22Z nicolaw $
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
use Scalar::Util qw(refaddr);
use Parse::DMIDecode::Handle;
use Parse::DMIDecode::Constants qw(@TYPES %GROUPS);
use Carp qw(croak cluck carp);
use vars qw($VERSION $DEBUG);

$VERSION = '0.02' || sprintf('%d', q$Revision: 803 $ =~ /(\d+)/g);
$DEBUG ||= $ENV{DEBUG} ? 1 : 0;

my $objstore = {};


#
# Methods
#

sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;

	my $self = bless \(my $dummy), $class;
	$objstore->{refaddr($self)} = {@_};
	my $stor = $objstore->{refaddr($self)};

	$stor->{commands} = [qw(dmidecode)];
	my $validkeys = join('|','nowarnings',@{$stor->{commands}});
	my @invalidkeys = grep(!/^$validkeys$/,grep($_ ne 'commands',keys %{$stor}));
	delete $stor->{$_} for @invalidkeys;
	cluck('Unrecognised parameters passed: '.join(', ',@invalidkeys))
		if @invalidkeys && $^W;

	for my $command (@{$stor->{commands}}) {
		croak "Command $command '$stor->{$command}'; file not found"
			if defined $stor->{$command} && !-f $stor->{$command};
	}

	DUMP('$self',$self);
	DUMP('$stor',$stor);
	return $self;
}


sub probe {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	my $stor = $objstore->{refaddr($self)};
	eval {
		if (!defined $stor->{dmidecode}) {
			require File::Which;
			for my $command (@{$stor->{commands}}) {
				$stor->{$command} = File::Which::which($command)
					if !defined $stor->{$command};
			}
		}
	};
	croak $@ if $@;

	my ($cmd) = $stor->{dmidecode} =~ /^([\/\.\_\-a-zA-Z0-9 ]+)$/;
	TRACE($cmd);
	croak "dmidecode command '$cmd' does not exist; bum!" if !-f $cmd;

	my $fh;
	local %ENV = %ENV;
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV PATH)};
	open($fh,'-|',$cmd) || croak "Unable to open file handle for command '$cmd': $!";
	while (local $_ = <$fh>) {
		$stor->{raw} .= $_;
	}
	close($fh) || carp "Unable to close file handle for command '$cmd': $!";

	return $self->parse($stor->{raw});
}


sub parse {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	my $stor = $objstore->{refaddr($self)};
	my %data = (handles => []);

	my @lines;
	for (@_) {
		push @lines, split(/\n/,$_);
	}

	my $i = 0;
	for (; $i < @lines; $i++) {
		local $_ = $lines[$i];
		if (/^Handle [0-9A-Fx]+/) {
			last;
		} elsif (/^SYSID present\.\s*/) {
			# No-op
		} elsif (/^# dmidecode ([\d\.]+)\s*$/) {
			$data{dmidecode} = $1;
		} elsif (/^(\d+) structures occupying (\d+) bytes?\.\s*$/) {
			$data{structures} = $1;
			$data{bytes} = $2;
		} elsif (/^DMI ([\d\.]+) present\.?\s*$/) {
			$data{dmi} = $1;
		} elsif (/^SMBIOS ([\d\.]+) present\.?\s*$/) {
			$data{smbios} = $1;
		} elsif (/^(?:DMI )?[Tt]able at ([0-9A-Fx]+)\.?\s*$/) {
			$data{location} = $1;
		}
	}

	for (qw(dmidecode structures bytes dmi smbios location)) {
		$data{$_} = undef if !exists $data{$_};
	}

	my $raw_handle_data = '';
	for (; $i < @lines; $i++) {
		if ($lines[$i] =~ /^Handle [0-9A-Fx]+/) {
			push @{$data{handles}}, Parse::DMIDecode::Handle->new(
					raw => $raw_handle_data,
					nowarnings => $stor->{nowarnings}
				) if $raw_handle_data;
			$raw_handle_data = "$lines[$i]\n";
		} else {
			$raw_handle_data .= "$lines[$i]\n";
		}
	}

	push @{$data{handles}}, Parse::DMIDecode::Handle->new(
			raw => $raw_handle_data,
			nowarnings => $stor->{nowarnings}
		) if $raw_handle_data;

	carp sprintf("Only parsed %d structures when %d were expected",
			scalar(@{$data{handles}}), $data{structures}
		) if scalar(@{$data{handles}}) < $data{structures};

	$stor->{parsed} = \%data;
	DUMP('$stor->{parsed}',$stor->{parsed});

	return $stor->{parsed}->{structures};
}


sub get_handles {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	croak 'Odd number of elements passed when even was expected' if @_ % 2;
	my %param = @_;
	my $stor = $objstore->{refaddr($self)};
	my @handles;
	my $getall = !keys(%param);

	for my $handle (@{$stor->{parsed}->{handles}}) {
		if ($getall ||
			(defined $param{address} && $handle->address eq $param{address}) ||
			(defined $param{dmitype} && $handle->dmitype == $param{dmitype}) ||
			(defined $param{group} && defined $GROUPS{$param{group}} &&
			 grep($_ == $handle->dmitype,@{$GROUPS{$param{group}}}))
			) {
			push @handles, $handle;
		}
	}

	return @handles;
}


sub structures {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{parsed}->{structures};
}


sub table_location {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{parsed}->{location};
}


sub smbios_version {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{parsed}->{smbios};
}


sub dmidecode_version {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{parsed}->{dmidecode};
}


sub handle_addresses {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return map { $_->handle }
		@{$objstore->{refaddr($self)}->{parsed}->{handles}};
}


sub keywords {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	my %keywords;
	my $stor = $objstore->{refaddr($self)};
	for my $handle (@{$stor->{parsed}->{handles}}) {
		for my $keyword ($handle->keywords) {
			$keywords{$keyword} = 1;
		}
	}

	return sort(keys(%keywords));
}


sub keyword {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	croak sprintf('%s elements passed when one was expected',
		(@_ > 1 ? 'Multiple' : 'No')) if @_ != 1;

	my $stor = $objstore->{refaddr($self)};
	for my $handle (@{$stor->{parsed}->{handles}}) {
		if (grep($_ eq $_[0],$handle->keywords)) {
			return $handle->keyword($_[0]);
		}
	}
}


sub DESTROY {
	my $self = shift;
	delete $objstore->{refaddr($self)};
}


sub TRACE {
	return unless $DEBUG;
	carp(shift());
}


sub DUMP {
	return unless $DEBUG;
	eval {
		require Data::Dumper;
		local $Data::Dumper::Indent = 2;
		local $Data::Dumper::Terse = 1;
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
 
 my $decoder = new Parse::DMIDecode;
 $decoder->probe; # Actively probe using dmidecode
  
 # Manually supply your own dmidecode output to be parsed
 # $decoder->parse(qx(sudo /usr/sbin/dmidecode));
  
 printf("System: %s, %s",
         $decoder->keyword("system-manufacturer"),
         $decoder->keyword("system-product-name"),
     );

=head1 DESCRIPTION

This module provides an OO interface to SMBIOS information through
the I<dmidecode> command which is known to work under a number of
Linux, BSD and BeOS variants.

This module is still actively under development, is no not yet
feature complete and still needs to be fully documented. There is
a possibility accessor method names may change before the final
release.

=head1 METHODS

=head2 new

 my $decoder = Parse::DMIDecode->new(
                     dmidecode => "/usr/sbin/dmidecode"),
                     nowarnings => 1
                 );

=head2 probe

 $decoder->probe;

=head2 parse

 my $raw = qx(sudo /usr/sbin/dmidecode);
 $decoder->prase($raw);

=head2 keyword

 my $serial_number = $decoder->keyword("system-serial-number");

=head2 keywords

 my @keywords = $decoder->keywords;
 my @bios_keywords = $decoder->keywords("bios");
 
 for my $keyword (@bios_keywords) {
     printf("%s => %s\n",
             $keyword,
             $decoder->keyword($keyword)
         );
 }

=head2 handle_addresses

 my @addresses = $decoder->handle_addresses;

=head2 get_handles

 use Parse::DMIDecode::Constants qw(@TYPES);
 
 # Available groups to query: bios, system, baseboard,
 #    chassis, processor, memory, cache, connector, slot
 for my $handle ($decoder->get_handles( group => "memory" )) {
     printf(">> Found handle at %s (%s):\n%s\n",
             $handle->address,
             $TYPES[$handle->dmitype],
             $handle->raw
         );
 }

=head2 smbios_version

 my $smbios_version = $decoder->smbios_version;

=head2 dmidecode_version

 my $dmidecode_version = $decoder->dmidecode_version;

Returns the version number of the copy of I<dmidecode> that was used
to create the source data that was parsed. This value may not be available
when using older versions of I<dmidecode>.

=head2 table_location

 my $memory_address = $decoder->table_location;

=head2 structures

 my $total_structures = $decoder->structures;

=head1 SEE ALSO

examples/*.pl,
L<http://www.nongnu.org/dmidecode/>,
L<http://linux.dell.com/libsmbios/>,
L<http://sourceforge.net/projects/x86info/>,
L<http://www.dmtf.org/standards/smbios>,
L<biosdecode(8)>, L<dmidecode(8)>, L<vpddecode(8)>

=head1 VERSION

$Id: DMIDecode.pm 803 2006-10-22 11:36:22Z nicolaw $

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



