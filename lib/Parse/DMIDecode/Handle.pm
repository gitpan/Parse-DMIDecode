############################################################
#
#   $Id: Handle.pm 789 2006-10-19 08:04:35Z nicolaw $
#   Parse::DMIDecode::Handle - Handle object
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

package Parse::DMIDecode::Handle;
# vim:ts=4:sw=4:tw=78

use strict;
use Parse::DMIDecode::Constants qw(@TYPES %GROUPS %TYPE2GROUP);
use Scalar::Util qw(refaddr);
use Carp qw(croak cluck confess carp);
use vars qw($VERSION $DEBUG);

$VERSION = '0.01' || sprintf('%d', q$Revision: 789 $ =~ /(\d+)/g);
$DEBUG ||= $ENV{DEBUG} ? 1 : 0;

my $objstore = {};


#
# Methods
#

sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;
#	croak sprintf('%s elements passed when one was expected',
#			(@_ > 1 ? 'Multiple' : 'No')) if @_ != 1;

	my $self = bless \(my $dummy), $class;
	$objstore->{refaddr($self)} = {@_};
	my $stor = $objstore->{refaddr($self)};

	my @validkeys = qw(raw nowarnings);
	my $validkeys = join('|',@validkeys);
	my @invalidkeys = grep(!/^$validkeys$/,keys %{$stor});
	delete $stor->{$_} for @invalidkeys;
	cluck('Unrecognised parameters passed: '.join(', ',@invalidkeys))
		if @invalidkeys && $^W;

	if (defined $stor->{raw}) {
		for (split(/\n/,$stor->{raw})) {
			if (/^Handle ([0-9A-Fx]+)(?:, DMI type (\d+), (\d+) bytes?\.?)?\s*$/) {
				$stor->{handle} = $1;
				$stor->{dmitype} = $2 if defined $2;
				$stor->{bytes} = $3 if defined $3;
			} elsif (defined $stor->{handle} &&
					/^\s*DMI type (\d+), (\d+) bytes?\.?\s*$/) {
				$stor->{dmitype} = $1 if defined $1;
				$stor->{bytes} = $2 if defined $2;
			} else {
				$stor->{raw_entries} = [] unless defined $stor->{raw_entries};
				push @{$stor->{raw_entries}}, $_;
			}
		}
		$stor->{keywords} = {};
		_parse($stor) if $stor->{raw_entries};
	}

	DUMP('$self',$self);
	DUMP('$stor',$stor);
	return $self;
}


sub keyword {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	croak sprintf('%s elements passed when one was expected',
		(@_ > 1 ? 'Multiple' : 'No')) if @_ != 1;
	return $objstore->{refaddr($self)}->{keywords}->{$_[0]};
}


sub keywords {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return sort(keys(%{$objstore->{refaddr($self)}->{keywords}}));
}


sub raw {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{raw};
}


sub bytes {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{bytes};
}


sub type { &dmitype; }
sub dmitype {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{dmitype};
}


sub address { &handle; }
sub handle {
	my $self = shift;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);
	return $objstore->{refaddr($self)}->{handle};
}


sub _parse {
	my $ref = shift;
	return unless defined $ref->{raw_entries};

	my $name_indent = 0;
	my $key_indent  = 0;
	my $name = '';
	my $key = '';

	my @errors;
	my %strct;

	for (my $l = 0; $l < @{$ref->{raw_entries}}; $l++) {
		local $_ = $ref->{raw_entries}->[$l];
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
			$ref->{keywords}->{_keyword($ref,$key)} = $strct{$name}->{$key}->[0]
				if defined $TYPE2GROUP{$ref->{dmitype}}

		} elsif ($name && $key && $indent > $key_indent && /^\s*(\S+.*?)\s*$/) {
			push @{$strct{$name}->{$key}->[1]}, $1;
			$ref->{keywords}->{_keyword($ref,$key)} = $strct{$name}->{$key}->[1]
				if defined $TYPE2GROUP{$ref->{dmitype}};# && !defined $strct{$name}->{$key}->[0];

		# unknown
		} else {
			push @errors, "Parser warning: $_";
		}
	}

	sub _keyword {
		my ($ref,$key) = @_;
		(my $keyword = $key) =~ s/[^a-z0-9]/-/gi;
		$keyword = lc("$TYPE2GROUP{$ref->{dmitype}}-$keyword");
		return $keyword;
	}

	$ref->{data} = \%strct;
	#if ($^W && @errors) {
	if (@errors && !$ref->{nowarnings}) {
		carp $_ for @errors;
	}
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

Parse::DMIDecode::Handle - 

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 new

=head2 raw

=head2 bytes

=head2 handle

=head2 address

=head2 type

=head2 dmitype

=head2 keywords

=head2 keyword

=head1 SEE ALSO

L<Parse::DMIDecode>

=head1 VERSION

$Id: Handle.pm 789 2006-10-19 08:04:35Z nicolaw $

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




