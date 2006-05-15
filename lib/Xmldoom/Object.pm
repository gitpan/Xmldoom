
package Xmldoom::Object;

use Xmldoom::Definition;
use Xmldoom::Object::Property;
use Xmldoom::ResultSet;
use Roma::Query::Function::Now;
use Roma::Query::Function::Count;
use Roma::Query::SQL::Literal;
use Roma::Query::SQL::Null;
use Exception::Class::DBI;
use Exception::Class::TryCatch;
use Scalar::Util qw(weaken isweak);
use strict;

# define our exceptions:
use Exception::Class qw( Xmldoom::Object::RollbackException );

use Data::Dumper;

# Connects registered class names to object definitions.  We can do this
# because in Perl the class namespace is global.
our %OBJECTS;

# this will bind this class to this table
sub BindToObject
{
	my $class  = shift;
	my $object = shift;

	# assign this class name to this object
	$object->set_class( $class );

	# store the definition to classname connection for future reference
	$OBJECTS{$class} = $object;
}

sub load
{
	my $class = shift;

	# The object definition does all of the actual work with regard to 
	# querying the database and getting the data.  We just pass it along
	# to the correct Perl class.
	
	my $definition = $OBJECTS{$class};
	my $data       = $definition->load( @_ );

	return $class->new({ data => $data });
}

sub SearchRS
{
	my $class    = shift;
	my $criteria = shift;

	# if no criteria, then we want to get all items
	if ( not defined $criteria )
	{
		$criteria = Xmldoom::Criteria->new();
	}

	# The object definition is responsible for performing the actual query
	# and getting a Roma result-set back for us.

	my $definition = $OBJECTS{$class};
	my $rs         = $definition->search_rs( $criteria );

	# return our fully prepared result set
	return Xmldoom::ResultSet->new({
		class  => $class,
		result => $rs,
		conn   => $rs->get_conn(),
		parent => $criteria->get_parent()
	});
}

sub Search
{
	my $class = shift;
	my $rs    = $class->SearchRS( @_ );
	
	my @ret;

	# unravel our result set
	while ( $rs->next() )
	{
		push @ret, $rs->get_object();
	}

	return wantarray ? @ret : \@ret;
}

sub SearchAttrsRS
{
	my $class    = shift;
	my $criteria = shift;

	# if no criteria, then we want to get all items
	if ( not defined $criteria )
	{
		$criteria = Xmldoom::Criteria->new();
	}

	return $OBJECTS{$class}->search_attrs_rs( $criteria, @_ );
}

sub SearchAttrs
{
	my $class = shift;
	my $rs    = $class->SearchAttrsRS( @_ );
	
	my @ret;

	# unravel our result set
	while ( $rs->next() )
	{
		push @ret, $rs->get_row();
	}

	return wantarray ? @ret : \@ret;
}

sub Count
{
	my $class    = shift;
	my $criteria = shift;

	# if no criteria, then we want to get all items
	if ( not defined $criteria )
	{
		$criteria = Xmldoom::Criteria->new();
	}

	return $OBJECTS{$class}->count( $criteria );
}

sub new
{
	my $class = shift;
	my $args = shift;

	my $parent;
	my $data;

	if ( ref($args) eq "HASH" )
	{
		$parent   = $args->{parent};
		$data     = $args->{data};
	}
	else
	{
		$parent   = $args;
		$data     = shift;
	}

	my $self = {
		parent     => $parent,
		dependents => [ ],
		original   => { },
		info       => { },
		key        => { },
		props      => [ ],
		new        => 1,

		# Now, we create references in the object to the global
		# object in the module.
		DEFINITION => $OBJECTS{$class}
	};

	# weaken reference to parent
	if ( defined $self->{parent} )
	{
		weaken( $self->{parent} );
	}

	# we are now an object
	bless $self, $class;

	# if we have data, then copy it into the info and key hashes.  Otherwise
	# we should set all the default values.
	if ( defined $data )
	{
		foreach my $column ( @{$self->{DEFINITION}->get_table()->get_columns()} )
		{
			my $col_name = $column->{name};

			# put in their places
			$self->{info}->{$col_name} = $data->{$col_name};
			if ( $column->{primary_key} )
			{
				# we need to store the keys twice so that we can pivot
				# on the key, if we need to change it.
				$self->{key}->{$col_name} = $data->{$col_name};
			}
		}

		# copy info into original
		$self->{original} = { %$data };
		
		# this is not a new object
		$self->{new} = 0;
	}
	else
	{
		# set our defaults
		foreach my $column ( @{$self->{DEFINITION}->get_table()->get_columns()} )
		{
			$self->{info}->{$column->{name}} = $column->{default};
		}
	}

	# setup the properties
	foreach my $prop ( @{$self->{DEFINITION}->get_properties()} )
	{
		push @{$self->{props}}, Xmldoom::Object::Property->new( $prop, $self );
	}

	return $self;
}

sub _get_definition  { return shift->{DEFINITION}; }
sub _get_database    { return shift->{DEFINITION}->get_database(); }
sub _get_object_name { return shift->{DEFINITION}->get_name(); }
sub _get_properties  { return shift->{props}; }
sub _get_attributes  { return shift->{info}; }
sub _get_key         { return shift->{key}; }

sub _get_property
{
	my ($self, $name) = @_;

	foreach my $prop ( @{$self->_get_properties()} )
	{
		if ( $prop->get_name() eq $name )
		{
			return $prop;
		}
	}

	die "There is no property named '$name' on this object";
}

sub _get_attr
{
	my ($self, $name) = @_;

	my $col = $self->{DEFINITION}->get_table()->get_column( $name );
	if ( not defined $col )
	{
		die "Cannot get non-existant attribute \"$name\".";
	}

	return $self->{info}->{$name};
}

sub _set_attr
{
	my ($self, $name, $value) = @_;

	my $col = $self->{DEFINITION}->get_table()->get_column( $name );
	if ( not defined $col )
	{
		die "Cannot set non-existant attribute \"$name\".";
	}

	# TODO: validate the attribute.

	$self->{info}->{$name} = $value;

	# we are changed!
	$self->_changed();
}

sub save
{
	my $self = shift;
	my $args = shift;

	my $commit = 1;
	my $conn;

	if ( ref($args) eq 'HASH' )
	{
		$conn   = $args->{conn};
		$commit = $args->{commit} if defined $args->{commit};
	}
	else
	{
		$conn = $args;
		
		# DRS: dumb dumb kludge -- I hate you, Perl ...
		my $tmp = shift;
		$commit = $tmp if defined $tmp;
	}

	my $status     = $self->{new} ? 'insert' : 'update';
	my $conn_owner = 0;

	if ( not defined $conn )
	{
		$conn = $self->{DEFINITION}->create_db_connection();
		$conn->begin();

		# we are the connection owner (or, ALL YOUR CONNECTION ARE BELONG TO US)
		$conn_owner = 1;
		$commit     = 1;
	}

	try eval
	{
		# save yourself!
		$self->do_save( $conn );

		# loop through child references and call save()
		if ( defined $self->{dependents} )
		{
			while ( scalar @{$self->{dependents}} )
			{
				my $child = pop @{$self->{dependents}};
				$child->save({ conn => $conn, commit => 0 });
			}
		}

		# if an exception isn't thrown, we assume that all is well and commit
		$conn->commit() if $commit;
	};


	my $error = catch;
	if ( $error )
	{
		# make sure we are not attempting to rollback multiple times from the
		# same transaction.
		if ( not $error->isa( 'Xmldoom::Object::RollbackException' ) )
		{
			# on the condition of error, we rollback() !!
			$conn->rollback() if $conn;

			# change the error to RollbackException so that the calling code knows
			# that we have already rollback()'d.
			$error = Xmldoom::Object::RollbackException->new( error => $error );
		}
	}

	$conn->disconnect() if $conn and $conn_owner;
	$error->rethrow()   if $error;

	# call the user handler
	$self->_on_save( $status );

	# copy current values into the orginals stuff
	$self->{original} = { %$self->{info} };
}

sub do_save
{
	my ($self, $conn) = @_;

	my $definition = $self->{DEFINITION};
	my $table      = $definition->get_table();
	my $table_name = $definition->get_table_name();

	my $id_gen;
	my $query;
	my $values = { };

	if ( $self->{new} )
	{
		$query = $definition->get_insert_query();
		foreach my $column ( @{$table->get_columns()} )
		{
			my $col_name = $column->{name};

			if ( not defined $self->{info}->{$col_name} )
			{
				# if the value is not defined, special behavior is required for
				# some special types.
				if ( $column->{auto_increment} )
				{
					$id_gen = $conn->create_id_generator();
					if ( $id_gen->is_before_insert() )
					{
						$values->{$col_name} = Roma::Query::SQL::Literal->new( $id_gen->get_id() );

						# discard the id generator because this is already
						# taken care of.
						$id_gen = undef;
					}
					else
					{
						# insert null, and grab the id from the id generator
						# after the insert.
						$values->{$col_name} = Roma::Query::SQL::Null->new();
					}
				}
				elsif ( $column->{timestamp} )
				{
					$values->{$col_name} = Roma::Query::Function::Now->new();
				}

				# TODO: else, insert a NULL!
			}
			else
			{
				# straigt simple value...
				$values->{$col_name} = Roma::Query::SQL::Literal->new( $self->{info}->{$col_name} );;
			}
		}
	}
	else
	{
		$query = $definition->get_update_query();
		foreach my $column ( @{$table->get_columns()} )
		{
			my $col_name = $column->{name};

			# add the primary key
			if ( $column->{primary_key} )
			{
				$values->{"key.$col_name"} = Roma::Query::SQL::Literal->new( $self->{key}->{$col_name} );
			}

			if ( $column->{timestamp} eq 'current' )
			{
				$values->{$col_name} = Roma::Query::Function::Now->new();
			}
			else
			{
				# ... and the normal values
				$values->{$col_name} = Roma::Query::SQL::Literal->new( $self->{info}->{$col_name} );
			}
		}
	}


	# execute, yo!
	#printf "save(): %s\n", $conn->generate_sql( $query, $values );
	$conn->prepare( $query )->execute( $values );

	# copy from the info, into the key, either for a newly db'd object or
	# for the primary key pivot.
	foreach my $column ( @{$table->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			my $col_name = $column->{name};

			if ( $column->{auto_increment} and defined $id_gen )
			{
				# we saved the id generator because its a get
				# after insert.  So, get, now...

				my $id = $id_gen->get_id();
				$self->{key}->{$col_name}  = $id;
				$self->{info}->{$col_name} = $id;
			}
			else
			{
				$self->{key}->{$col_name} = $self->{info}->{$col_name};
			}
		}
	}

	if ( $self->{new} )
	{
		$self->{new} = 0;
	}
}

sub _on_save
{
	my ($self, $type) = @_;
	# Virtual.
}

sub delete
{
	my $self = shift;

	# TODO: cascading deletes are cool too...
	
	my $definition = $self->{DEFINITION};
	my $table      = $definition->get_table();
	
	my $query = $definition->get_delete_query();

	my %values;
	foreach my $column ( @{$table->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			$values{$column->{name}} = Roma::Query::SQL::Literal->new( $self->{key}->{$column->{name}} );
		}
	}

	my $conn = $definition->create_db_connection();

	# TODO: add error checking if ever we implement cascading deletes

	$conn->prepare( $query )->execute( \%values );

	$conn->disconnect();
}

# a private function that adds a child to list of dependent objects.  This should only
# be called by the child itself when it has changed.
sub _add_dependent
{
	my ($self, $child) = @_;
	push @{$self->{dependents}}, $child;
}

# manually marks this object as changed
sub _changed
{
	my $self = shift;

	# we tell our parent that we are modified
	if ( defined $self->{parent} )
	{
		$self->{parent}->_add_dependent($self);
	}
}

sub set
{
	my $self = shift;
	my $args = shift;

	foreach my $prop ( @{$self->{props}} )
	{
		my $prop_name = $prop->get_name();
		if ( defined $args->{$prop_name} )
		{
			$prop->set( $args->{$prop_name} );
			delete $args->{$prop_name};
		}
	}

	if ( scalar keys %$args )
	{
		my $unknown = join ", ", keys %$args;
		die "Unknown properties: $unknown";
	}
}

sub AUTOLOAD
{
	my $self     = shift;
	my $function = our $AUTOLOAD;

	# remove the package name
	$function =~ s/.*:://;

	foreach my $prop ( @{$self->{props}} )
	{
		foreach my $autoload_name ( @{$prop->get_autoload_list()} )
		{
			if ( $function eq $autoload_name )
			{
				return $prop->autoload( $function, @_ );
			}
		}
	}

	die sprintf "%s not a valid property function of %s.", $function, ref($self);
}

sub DESTROY
{
	# TODO: some kind of clean-up?
}

1;

