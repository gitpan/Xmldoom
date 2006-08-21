
package Xmldoom::Definition::Link;
use base qw(Exporter);

use strict;

use Data::Dumper;

our @EXPORT_OK = qw(
	ONE_TO_ONE,
	MANY_TO_ONE,
	ONE_TO_MANY,
	MANY_TO_MANY
);

our $ONE_TO_ONE   = 'one-to-one';
our $MANY_TO_ONE  = 'many-to-one';
our $ONE_TO_MANY  = 'one-to-many';
our $MANY_TO_MANY = 'many-to-many';

sub new
{
	my $class = shift;
	my $args  = shift;

	if ( not defined $args )
	{
		$args = [ ];
	}
	elsif ( ref($args) ne 'ARRAY' )
	{
		$args = [ $args ];
	}

	my $relationship;

	if ( scalar @$args > 1 )
	{
		# TODO: is this really that simple?
		$relationship = $MANY_TO_MANY;
	}
	else
	{
		my $fn = $args->[0];

		my $local_key = $fn->get_table()->get_column_names({ primary_key => 1 });
		my $foreign_key = $fn->get_reference_table()->get_column_names({ primary_key => 1 });

		# check if the local or foreign connection has the complete table key
		my $has_local_key = $fn->is_local_column_names( $local_key );
		my $has_foreign_key = $fn->is_foreign_column_names( $foreign_key );

		# look-up the appropriate relationship
		if ( not $has_local_key and $has_foreign_key )
		{
			$relationship = $MANY_TO_ONE;
		}
		elsif ( $has_local_key and not $has_foreign_key )
		{
			$relationship = $ONE_TO_MANY;
		}
		elsif ( $has_local_key and $has_foreign_key )
		{
			$relationship = $ONE_TO_ONE;
		}
		else
		{
			$relationship = $MANY_TO_MANY;
		}
	}

	my $self =
	{
		foreign_keys => $args,
		relationship => $relationship
	};

	bless  $self, $class;
	return $self;
}

sub get_foreign_keys     { return shift->{foreign_keys}; }
sub get_count            { return scalar @{shift->{foreign_keys}}; }
sub get_start            { return shift->{foreign_keys}->[0]; }
sub get_end              { return shift->{foreign_keys}->[-1]; }
sub get_start_table_name { return shift->get_start()->get_table_name(); }
sub get_end_table_name   { return shift->get_end()->get_reference_table_name(); }
sub get_relationship     { return shift->{relationship}; }

sub equals
{
	my ($self, $link) = @_;

	if ( $self->get_count() != $link->get_count() )
	{
		return 0;
	}

	for( my $i = 0; $i < $self->get_count(); $i++ )
	{
		if ( not $self->{foreign_keys}->[$i]->equals( $link->{foreign_keys}->[$i] ) )
		{
			return 0;
		}
	}

	return 1;
}

sub clone_reverse
{
	my $self = shift;

	my @foreign_keys;
	foreach my $fkey ( @{$self->{foreign_keys}} )
	{
		unshift @foreign_keys, $fkey->clone_reverse();
	}

	return Xmldoom::Definition::Link->new( \@foreign_keys );
}

1;

