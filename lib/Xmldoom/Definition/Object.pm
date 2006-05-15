
package Xmldoom::Definition::Object;

use Exception::Class::TryCatch;
use Roma::Query::Select;
use Roma::Query::Insert;
use Roma::Query::Update;
use Roma::Query::Delete;
use Roma::Query::Where;
use Roma::Query::Comparison;
use Roma::Query::Variable;
use Roma::Query::SQL::Column;
use Roma::Query::SQL::Literal;
use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $database;
	my $object_name;
	my $table_name;
	
	if ( ref($args) eq 'HASH' )
	{
		$database    = $args->{definition};
		$object_name = $args->{object_name};
		$table_name  = $args->{table_name};
	}
	else
	{
		$database    = $args;
		$object_name = shift;
		$table_name  = shift;
	}

	my $table = $database->get_table( $table_name );
	if ( not defined $table )
	{
		die "Cannot bind an object to a non-existant table.";
	}

	my $self = {
		database            => $database,
		object_name         => $object_name,
		table_name          => $table_name,
		table               => $table,
		props               => [ ],
		class               => undef,

		# generate on demand
		select_query        => undef,
		select_by_key_query => undef,
		insert_query        => undef,
		update_query        => undef,
		delete_query        => undef,
	};

	bless  $self, $class;
	return $self;
}

sub get_database   { return shift->{database}; }
sub get_table_name { return shift->{table_name}; }
sub get_table      { return shift->{table}; }
sub get_name       { return shift->{object_name}; }
sub get_properties { return shift->{props}; }
sub get_class      { return shift->{class}; }

sub get_property
{
	my ($self, $prop_name) = @_;

	foreach my $prop ( @{$self->{props}} )
	{
		if ( $prop->get_name() eq $prop_name )
		{
			return $prop;
		}
	}

	die sprintf "Unknown property '%s' on object '%s'", $prop_name, $self->get_name();
}

sub get_reportable_properties
{
	my $self = shift;
	my @list = grep { $_->get_reportable() } @{$self->{props}};
	return wantarray ? @list : \@list;
}

sub get_searchable_properties
{
	my $self = shift;
	my @list = grep { $_->get_searchable() } @{$self->{props}};
	return wantarray ? @list : \@list;
}

sub has_property
{
	my ($self, $prop_name) = @_;

	eval
	{
		$self->get_property( $prop_name );
		return 1;
	};

	return 0;
}

sub set_class
{
	my ($self, $class) = @_;

	if ( defined $self->{class} )
	{
		die "You are trying to redefine an object's class!  Why would anyone want to do that?";
	}

	$self->{class} = $class;
}

sub add_property
{
	my ($self, $prop) = @_;

	# TODO: make sure that this property will actually work, ie. are there
	# any autoload name conflicts.

	if ( $self->has_property( $prop->get_name() ) )
	{
		die "Cannot add two properties with the same name";
	}

	push @{$self->{props}}, $prop;
}

sub set_custom_property
{
	my ($self, $name, $prop_class) = @_;

	my $index = 0;
	foreach my $prop ( @{$self->get_properties()} )
	{
		if ( $prop->get_name() eq $name )
		{
			if ( $prop->isa('Xmldoom::Definition::Property::PlaceHolder') )
			{
				# All is thrill chillin
				$self->{props}->[$index] = $prop_class->new( $prop->get_prop_args() );
				return;
			}
			else
			{
				die "Property '$name' exists, but is not designated to be a custom property";
			}
		}

		$index ++;
	}

	die "No such property '$name'";
}

sub get_select_query
{
	my $self = shift;

	if ( not defined $self->{select_query} )
	{
		my $query = Roma::Query::Select->new();
		$query->add_from( $self->{table_name} );

		# add all the columns 
		foreach my $column ( @{$self->{table}->get_columns()} )
		{
			$query->add_result( Roma::Query::SQL::Column->new( $self->{table_name}, $column->{name}) );
		}

		$self->{select_query} = $query;
	}

	return $self->{select_query};
}

sub get_select_by_key_query
{
	my $self = shift;

	if ( not defined $self->{select_by_key_query} )
	{
		my $query = $self->get_select_query()->clone();
		my $where = Roma::Query::Where->new( $Roma::Query::Where::AND );

		foreach my $column ( @{$self->{table}->get_columns()} )
		{
			if ( $column->{primary_key} )
			{
				my $op = Roma::Query::Comparison->new( $Roma::Query::Comparison::EQUAL );
				$op->add( Roma::Query::SQL::Column->new( $self->{table_name}, $column->{name} ) );
				$op->add( Roma::Query::Variable->new( "$self->{table_name}.$column->{name}" ) );
				$where->add( $op );
			}
		}

		$query->set_where( $where );
		$self->{select_by_key_query} = $query;
	}

	return $self->{select_by_key_query};
}

sub get_insert_query
{
	my $self = shift;

	if ( not defined $self->{insert_query} )
	{
		my $query = Roma::Query::Insert->new( $self->{table_name} );

		foreach my $column ( @{$self->{table}->get_columns()} )
		{
			$query->set_value( $column->{name}, Roma::Query::Variable->new($column->{name}) );
		}

		$self->{insert_query} = $query;
	}

	return $self->{insert_query};
}

sub get_update_query
{
	my $self = shift;

	if ( not defined $self->{update_query} )
	{
		my $query = Roma::Query::Update->new( $self->{table_name} );
		my $where = Roma::Query::Where->new( $Roma::Query::Where::AND );

		foreach my $column ( @{$self->{table}->get_columns()} )
		{
			# add the primary key to the where section
			if ( $column->{primary_key} )
			{
				my $op = Roma::Query::Comparison->new( $Roma::Query::Comparison::EQUAL );
				$op->add( Roma::Query::SQL::Column->new( undef, $column->{name} ) );
				$op->add( Roma::Query::Variable->new( "key.$column->{name}" ) );
				$where->add($op);
			}

			# set all the column values
			$query->set_value( $column->{name}, Roma::Query::Variable->new( $column->{name} ) );
		}
		$query->set_where( $where );

		$self->{update_query} = $query;
	}

	return $self->{update_query};
}

sub get_delete_query
{
	my $self = shift;

	if ( not defined $self->{delete_query} )
	{
		my $query = Roma::Query::Delete->new( $self->{table_name} );
		my $where = Roma::Query::Where->new( $Roma::Query::Where::AND );

		foreach my $column ( @{$self->{table}->get_columns()} )
		{
			if ( $column->{primary_key} )
			{
				my $op = Roma::Query::Comparison->new( $Roma::Query::Comparison::EQUAL );
				$op->add( Roma::Query::SQL::Column->new( undef, $column->{name} ) );
				$op->add( Roma::Query::Variable->new( $column->{name} ) );
				$where->add( $op );
			}
		}
		$query->set_where( $where );

		$self->{delete_query} = $query;
	}

	return $self->{delete_query};
}

# A convenience function
sub find_connections
{
	my ($self, $object_name) = @_;

	my $database = $self->get_database();
	my $object   = $database->get_object( $object_name );

	return $database->find_connections( $self->get_table_name(), $object->get_table_name() );
}

# A convenience function
sub find_relationship
{
	my ($self, $object_name) = @_;

	my $database = $self->get_database();
	my $object   = $database->get_object( $object_name );

	return $database->find_relationship( $self->get_table_name(), $object->get_table_name() );
}

# A convenience function
sub create_db_connection
{
	my $self = shift;

	my $factory = $self->get_database()->get_connection_factory();
	if ( not defined $factory )
	{
		# Programmer error
		die "This database doesn't have a Roma::Connection::Factory registered";
	}

	return $factory->create();
}

#
# The following allow you to perform all of the basic database operations that
# CS3::Object performs, except with an actual object, just the raw queries.
#

sub load
{
	my $self = shift;

	# Convenience.
	my $table      = $self->get_table();
	my $table_name = $self->get_table_name();
	my $query      = $self->get_select_by_key_query();

	my %values;

	my $args;
	if ( ref($_[0]) eq 'HASH' )
	{
		$args = shift;
	}

	# parse the arguments into values for the SQL generator
	foreach my $column ( @{$table->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			my $col_name = $column->{name};
			my $val_name = "$table_name.$col_name";
			my $val;

			if ( $args )
			{
				$val = $args->{$col_name};
			}
			else
			{
				$val = shift;
			}

			if ( not defined $val )
			{
				die "Missing required key value \"$col_name\"";
			}

			$values{$val_name} = Roma::Query::SQL::Literal->new( $val );
		}
	}

	my $conn;

	my $data = try eval
	{
		$conn = $self->create_db_connection();

		my $stmt = $conn->prepare( $query );
		my $rs   = $stmt->execute( \%values );

		if ( $rs->next() )
		{
			return $rs->get_row();
		}
		else
		{
			# uh oh!
			die "Can't find an object with that primary key!";
		}
	};

	do
	{
		$conn->disconnect() if defined $conn;
	};

	catch my $err;
	$err->rethrow() if $err;

	return $data;
}

sub search_rs
{
	my $self = shift;
	my $criteria = shift;

	my $query = $criteria->generate_query_for_object( $self->get_database(), $self->get_name() );

	my $conn;
	my $rs;

	# connect and query
	try eval
	{
		$conn = $self->create_db_connection();
		#printf STDERR "Search(): %s\n", $conn->generate_sql($query);
		$rs = $conn->prepare( $query )->execute();
	};

	catch my $err;
	if ( $err )
	{
		$conn->disconnect() if defined $conn;
		$err->rethrow();
	}

	return $rs;
}

sub search
{
	my $self  = shift;
	my $rs    = $self->search_rs( @_ );
	
	my @ret;

	# unravel our result set
	while ( $rs->next() )
	{
		push @ret, $rs->get_row();
	}

	return wantarray ? @ret : \@ret;
}

sub search_attrs_rs
{
	my $self     = shift;
	my $criteria = shift;

	my @attrs;

	my $table_name = $self->get_table_name();

	# build object specific attrs
	foreach my $attr ( @_ )
	{
		push @attrs, "$table_name/$attr";
	}

	my $query = $criteria->generate_query_for_attrs( $self->get_database(), \@attrs );

	my $conn;
	my $rs;

	# connect and query
	try eval
	{
		$conn = $self->create_db_connection();
		#printf STDERR "Search(): %s\n", $conn->generate_sql($query);
		$rs = $conn->prepare( $query )->execute();
	};

	catch my $err;
	if ( $err )
	{
		$conn->disconnect() if defined $conn;
		$err->rethrow();
	}

	return $rs;
}

sub search_attrs
{
	my $self  = shift;
	my $rs    = $self->search_attrs_rs( @_ );
	
	my @ret;

	# unravel our result set
	while ( $rs->next() )
	{
		push @ret, $rs->get_row();
	}

	return wantarray ? @ret : \@ret;
}

sub count
{
	my $self     = shift;
	my $criteria = shift;

	my $query = $criteria->generate_query_for_object_count( $self->get_database(), $self->get_name() );

	my $conn;
	my $ret;

	try eval
	{
		$conn = $self->create_db_connection();
		
		#printf "Search(): %s\n", $conn->generate_sql($query);
		my $stmt = $conn->prepare( $query );
		my $rs   = $stmt->execute();

		if ( $rs->next() )
		{
			my $t = $rs->get_row();
			$ret = $t->{count};
		}
	};

	do
	{
		$conn->disconnect() if defined $conn;
	};

	catch my $err;
	$err->rethrow() if $err;

	return $ret;
}

1;

