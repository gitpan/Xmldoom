
package Xmldoom::Definition::Property::Object;
use base qw(Xmldoom::Definition::Property);

use DBIx::Romani::Query::Variable;
use DBIx::Romani::Query::SQL::Column;
use Module::Runtime qw(use_module);
use Scalar::Util qw(weaken isweak);
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
	my $key_attributes;

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
		$key_attributes   = $args->{key_attributes};
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
	#$self->{conns}             = [ ];

	my $conns = $parent->find_connections( $object_name );

	# loop through the conns looking for conflicts, ie. When a 
	# foreign_table and foreign_column pair is used twice.  If so, and
	# there are no key_attributes set, then complain.  Otherwise, compare
	# the key_attributes against the local_table and local_column and choose
	# those connections over the others.  If the key_attributes are set
	# for no good reason, you should complain to.
	my $foreign_columns = { };
	my $ambiguous_key   = 0;

	foreach my $conn ( @$conns )
	{
		if ( defined $foreign_columns->{$conn->{foreign_column}} )
		{
			push @{$foreign_columns->{$conn->{foreign_column}}}, $conn;
			$ambiguous_key = 1;
		}
		else
		{
			$foreign_columns->{$conn->{foreign_column}} = [ $conn ];
		}
	}

	if ( not $ambiguous_key )
	{
		if ( defined $key_attributes )
		{
			print STDERR "WARNING: Specifying a key attributes for this object property when it is not ambiguous!\n";
		}

		# if the key isn't ambiguous, then just use the connections
		$self->{conns} = $conns;
	}
	elsif ( not defined $key_attributes )
	{
		die $self->{name} . ": It is ambiguous which connection to the foreign object is intended in this property.  You must specify a <key/> section to your <object/> property.";
	}
	else
	{
		$self->{conns} = [ ];

		# now we build up the list of connections disambiguated.
		conn_list: foreach my $conn_list ( values %$foreign_columns )
		{
			if ( scalar @$conn_list == 1 )
			{
				# this isn't one of the ambiguous connections, so just add it.
				push @{$self->{conns}}, $conn_list->[0];
			}
			else
			{
				# attempt to disambiguate...
				foreach my $conn ( @$conn_list )
				{
					foreach my $attr ( @$key_attributes )
					{
						if ( $conn->{local_column} eq $attr )
						{
							push @{$self->{conns}}, $conn;
							next conn_list;
						}
					}
				}

				die "It is ambiguous which connection to the foreign object is intended in this property.  The <key/> section of this <object/> property is insufficient to disambiguate.";
			}
		}
	}

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

sub get_object_definition
{
	my $self = shift;

	return $self->get_parent()->get_database()->get_object( $self->{object_name} );
}

sub get_object_class
{
	my $self = shift;

	my $class = $self->get_object_definition()->get_class();

	if ( not defined $class )
	{
		die "The object '$self->{object_name}' isn't attached to a Perl class.  Maybe you forgot to 'use' its module?";
	}

	use_module($class);

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
	my ($self, $object, $args, $object_data) = (shift, shift, shift, shift);

	my $database = $self->get_parent()->get_database();
	my $class    = $self->get_object_class();

	if ( $self->get_type() eq 'inherent' )
	{
		if ( defined $object_data->{unsaved_object} and $object_data->{unsaved_object}->{new} )
		{
			return $object_data->{unsaved_object};
		}
		else
		{
			# clear the unsaved object, if it actually exists
			if ( defined $object_data->{unsaved_object} )
			{
				$object_data->{unsaved_object} = undef;
			}
			
			# simply load the data
			my $object_key = { };
			foreach my $conn ( @{$self->{conns}} )
			{
				$object_key->{$conn->{foreign_column}} = $object->_get_attr($conn->{local_column});
			}
			my $data = $self->get_object_definition()->load( $object_key );

			# return the appropriate object
			return $class->new(undef, {
				data => $data,
				parent => $object,
				parent_conns => $self->{conns}
			});
		}
	}
	elsif ( $self->get_type() eq 'external' )
	{
		my @ret;

		if ( defined $object_data )
		{
			# check the list for undef objects (because they are weak references)
			# and objects that have been saved.
			foreach my $unsaved ( @{$object_data->{unsaved_list}} )
			{
				if ( defined $unsaved and $unsaved->{new} )
				{
					push @ret, $unsaved;
				}
			}
			if ( scalar @{$object_data->{unsaved_list}} != scalar @ret )
			{
				# copy into unsaved if there were any changes
				$object_data->{unsaved_list} = [ @ret ];
			}
		}

		if ( not $object->{new} )
		{
			my $criteria = Xmldoom::Criteria->new( $object );

			# pass any arguments as property equations on the criteria.
			if ( $self->{relationship}->[1] eq 'many' )
			{
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
			@ret = $class->Search( $criteria );
		}

		return wantarray ? @ret : \@ret;
	}
}

sub get_value_description
{
	my ($self, $value) = @_;

	my $prop = $value->_get_property( $self->{options_prop} );

	return $prop->get();
}

sub set
{
	my ($self, $object, $args, $object_data) = @_;

	if ( $self->get_type() eq 'inherent' )
	{
		# we are simply setting a value
		my $value = $args;

		# link the attributes of the value to ours
		foreach my $conn ( @{$self->{conns}} )
		{
			$object->_link_attr( $conn->{local_column}, $value, $conn->{foreign_column} );
		}

		# this object will be saved in the same transaction as us so that no
		# changes are lost.
		$object->_add_dependent( $value );

		# if this value is unsaved, we need to hang onto it
		if ( $value->{new} )
		{
			$object_data->{unsaved_object} = $value;
			weaken $object_data->{unsaved_object};
		}
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
			push @ret, $class->new($props, { parent => $object });
		}

		# create the unsaved objects list
		if ( not defined $object_data->{unsaved_list} )
		{
			$object_data->{unsaved_list} = [ ];
		}

		# add weak references to these new objects in the unsaved objects list
		foreach my $child ( @ret )
		{
			push @{$object_data->{unsaved_list}}, $child;
			weaken $object_data->{unsaved_list}->[-1];
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
		push @ret, DBIx::Romani::Query::SQL::Column->new( $conn->{local_table}, $conn->{local_column} );
	}

	return \@ret;
}

sub get_query_rval
{
	my ($self, $value) = @_;

	my @ret;
	foreach my $conn ( @{$self->{conns}} )
	{
		push @ret, DBIx::Romani::Query::SQL::Literal->new( $value->_get_attr($conn->{foreign_column}) );
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

