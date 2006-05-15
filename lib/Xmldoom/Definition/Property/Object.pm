
package Xmldoom::Definition::Property::Object;
use base qw(Xmldoom::Definition::Property);

use Roma::Query::Variable;
use Roma::Query::SQL::Column;
use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $parent;
	my $prop_name;
	my $object_name;
	my $set_name;
	my $get_name;
	my $options_prop;
	my $options_criteria;
	my $inclusive;
	my $inter_table;

	if ( ref($args) eq 'HASH' )
	{
		$parent           = $args->{parent};
		$prop_name        = $args->{name};
		$object_name      = $args->{object_name};
		$set_name         = $args->{set_name};
		$get_name         = $args->{get_name};
		$options_prop     = $args->{options_property};
		$options_criteria = $args->{options_criteria};
		$inclusive        = $args->{inclusive};
		$inter_table      = $args->{inter_table};
	}
	else
	{
		$parent      = $args;
		$prop_name   = shift;
		$object_name = shift;

		$args = {
			parent => $parent,
			name   => $prop_name,
		};
	}

	# we need to know how this object relates the other
	my $rel_string = $parent->find_relationship( $object_name );

	# get the component parts
	my @rel_parts;
	@rel_parts = split /-/, $rel_string;
	@rel_parts = ( $rel_parts[0], $rel_parts[2] );

	# conditionally prepare autoload names based on property type
	my $prop_type;
	if ( $rel_parts[1] eq 'one' )
	{
		$set_name  = "set_$prop_name" if not defined $set_name;
		$get_name  = "get_$prop_name" if not defined $get_name;
		$prop_type = "inherent";
	}
	elsif ( $rel_parts[1] eq 'many' )
	{
		$set_name  = "add_$prop_name"    if not defined $set_name;
		$get_name  = "get_${prop_name}s" if not defined $get_name;
		$prop_type = "external";
	}

	my $self = $class->SUPER::new( $args );
	$self->{object_name}       = $object_name;
	$self->{set_name}          = $set_name;
	$self->{get_name}          = $get_name;
	$self->{relationship}      = \@rel_parts;
	$self->{prop_type}         = $prop_type;
	$self->{options_prop}      = $options_prop;
	$self->{options_criteria}  = $options_criteria;
	$self->{inclusive}         = $inclusive || 0;
	$self->{inter_table}       = $inter_table;

	# cache this since every function calls it!
	$self->{conns} = $parent->find_connections( $object_name );

	bless  $self, $class;
	return $self;
}

sub get_type          { return shift->{prop_type}; }
sub get_object_name   { return shift->{object_name}; }

sub get_autoload_get_list
{
	return [ shift->{get_name} ];
}

sub get_autoload_set_list
{
	return [ shift->{set_name} ];
}

sub get_object
{
	my $self = shift;

	return $self->get_parent()->get_database()->get_object( $self->{object_name} );
}

sub get_object_class
{
	my $self = shift;

	my $class = $self->get_object()->get_class();

	if ( not defined $class )
	{
		die "The object '$self->{object_name}' isn't attached to a Perl class.  Maybe you forgot to 'use' its module?";
	}

	return $class;
}

sub get_data_type
{
	my $self = shift;
	my $args = shift;

	my $include_options;

	if ( ref($args) eq 'HASH' )
	{
		$include_options = $args->{include_options};
	}

	my $value = {
		type        => 'object',
		object_name => $self->{object_name},
	};

	# get the selectable options, baby.
	if ( $self->{inclusive} and defined $self->{options_prop} and $include_options )
	{
		my $criteria;
		
		if ( defined $self->{options_criteria} )
		{
			$criteria = $self->{options_criteria}->clone();
		}
		else
		{
			$criteria = Xmldoom::Criteria->new();
		}

		my $class = $self->get_object_class();
		my @options;

		my $rs = $class->SearchRS( $criteria );
		while ( $rs->next() )
		{
			my $obj  = $rs->get_object();
			my $prop = $obj->_get_property( $self->{options_prop} );

			push @options, { value => $obj->_get_key(), description => $prop->get() };
		}

		$value->{options} = \@options;
	}

	return $value;
}

sub get
{
	my ($self, $object) = (shift, shift);

	my $database = $self->get_parent()->get_database();
	my $class    = $self->get_object_class();

	my $criteria = Xmldoom::Criteria->new( $object );

	# pass any arguments as property equations on the criteria.
	if ( $self->{relationship}->[1] eq 'many' )
	{
		my $args = shift;
		if ( ref($args) eq 'HASH' )
		{
			while( my ($key, $val) = each %$args )
			{
				my $prop = sprintf "%s/%s", $self->{object_name}, $key;
				$criteria->add( $prop, $val );
			}
		}
	}

	# connect via the intertable
	if ( defined $self->{inter_table} )
	{
		# TODO: this should work, but doesn't!  There are problems with our
		# implementation of Criteria in this regard, but I don't have the mind
		# to debug it right now.

		my $parent_table_name = $self->get_parent()->get_table_name();
		my $object_table_name = $database->get_object( $self->{object_name} )->get_table_name();

		# join the parent table to the inter-table
		my $parent_conns = $database->find_connections( $parent_table_name, $self->{inter_table} );
		foreach my $conn ( @$parent_conns )
		{
			$criteria->join_attr(
				sprintf("%s/%s", $conn->{local_table},   $conn->{local_column}),
				sprintf("%s/%s", $conn->{foreign_table}, $conn->{foreign_column})
			);

			#print Dumper $conn;
		}

		# join the inter-table to the object table
		my $object_conns = $database->find_connections( $self->{inter_table}, $object_table_name );
		foreach my $conn ( @$object_conns )
		{
			$criteria->join_attr(
				sprintf("%s/%s", $conn->{local_table},   $conn->{local_column}),
				sprintf("%s/%s", $conn->{foreign_table}, $conn->{foreign_column})
			);

			#print Dumper $conn;
		}
	}
		
	# execute
	my @ret = $class->Search( $criteria );

	# return
	if ( $self->{relationship}->[1] eq 'one' )
	{
		return $ret[0];
	}

	return wantarray ? @ret : \@ret;
}

sub get_value_description
{
	my ($self, $value) = @_;

	my $prop = $value->_get_property( $self->{options_prop} );

	return $prop->get();
}

sub set
{
	my ($self, $object, $args) = @_;

	if ( $self->get_type() eq 'inherent' )
	{
		# we are simply setting a value
		my $value = $args;

		# copy its connected attributes into our object
		foreach my $conn ( @{$self->{conns}} )
		{
			$object->_set_attr( $conn->{local_column}, $value->_get_attr($conn->{foreign_column}) );
		}

		# this object will be saved in the same transaction as us so that no
		# changes are lost.
		$object->_add_dependent( $value );
	}
	elsif ( $self->get_type() eq 'external' )
	{
		# Here we accept an array of hashs (or a single hash), to "add", creating
		# and returning new objects for each.

		if ( ref($args) ne 'ARRAY' )
		{
			$args = [ $args ];
		}

		my $database = $self->get_parent()->get_database();
		my $class    = $self->get_object_class();
		my @ret;

		# create new objects
		foreach my $props ( @$args )
		{
			my $new_obj;
			$new_obj = $class->new({ parent => $object });
			$new_obj->set( $props );

			# set properties from us
			foreach my $conn ( @{$self->{conns}} )
			{
				$new_obj->_set_attr( $conn->{foreign_column}, $object->_get_attr($conn->{local_column}) );
			}
			
			# Don't save!  Maybe not all the required information is filled in!!
			#$new_obj->save();

			push @ret, $new_obj;
		}

		if ( scalar @$args == 1 )
		{
			return $ret[0];
		}

		return wantarray ? @ret : \@ret;
	}
}

sub get_query_lval
{
	my $self = shift;

	my @ret;
	foreach my $conn ( @{$self->{conns}} )
	{
		push @ret, Roma::Query::SQL::Column->new( $conn->{local_table}, $conn->{local_column} );
	}

	return \@ret;
}

sub get_query_rval
{
	my ($self, $value) = @_;

	my @ret;
	foreach my $conn ( @{$self->{conns}} )
	{
		push @ret, Roma::Query::SQL::Literal->new( $value->_get_attr($conn->{foreign_column}) );
	}

	return \@ret;
}

sub autoload
{
	my ($self, $object, $func_name) = (shift, shift, shift);

	if ( $func_name eq $self->{set_name} )
	{
		$self->set($object, @_);
	}
	elsif ( $func_name eq $self->{get_name} )
	{
		return $self->get($object, @_);
	}
	else
	{
		die "$func_name is not defined by this property";
	}
}

1;

