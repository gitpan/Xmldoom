
package Xmldoom::Object;

use Xmldoom::Definition;
use Xmldoom::Object::Property;
use Xmldoom::Object::Attribute;
use Xmldoom::Object::LinkAttribute;
use Xmldoom::ResultSet;
use DBIx::Romani::Query::Function::Now;
use DBIx::Romani::Query::Function::Count;
use DBIx::Romani::Query::SQL::Literal;
use DBIx::Romani::Query::SQL::Null;
use Exception::Class::DBI;
use Exception::Class::TryCatch;
use Scalar::Util qw(weaken isweak);
use Module::Runtime qw/ use_module /;
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
	my $class  = shift;

	# The object definition does all of the actual work with regard to 
	# querying the database and getting the data.  We just pass it along
	# to the correct Perl class.
	
	my $definition = $OBJECTS{$class};
	my $data       = $definition->load( @_ );

	my $result = $class->new(undef, { data => $data });
	
	# call user hook
	$result->_on_load();

	return $result;
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

sub SearchDistinctAttrsRS
{
	my $class    = shift;
	my $criteria = shift;

	# if no criteria, then we want to get all items
	if ( not defined $criteria )
	{
		$criteria = Xmldoom::Criteria->new();
	}

	return $OBJECTS{$class}->search_distinct_attrs_rs( $criteria, @_ );
}

sub SearchDistinctAttrs
{
	my $class = shift;
	my $rs    = $class->SearchDistinctAttrsRS( @_ );
	
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
	my $public_args  = shift;
	my $private_args = shift;

	my $parent;
	my $parent_conns;
	my $data;
	my $sets;

	if ( ref($private_args) eq "HASH" )
	{
		$parent       = $private_args->{parent};
		$parent_conns = $private_args->{parent_conns};
		$data         = $private_args->{data};
	}
	if ( ref($public_args) eq "HASH" )
	{
		$sets = $public_args;
	}

	my $self = {
		parent      => $parent,
		dependents  => [ ],
		original    => { },
		info        => { },
		key         => { },
		props       => [ ],
		callbacks   => { },
		new         => 1,

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
			$self->{info}->{$col_name} = Xmldoom::Object::Attribute->new( $data->{$col_name} );
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
			$self->{info}->{$column->{name}} = Xmldoom::Object::Attribute->new( $column->{default} );
		}
	}

	# link our attributes to the appropriate connections in the parent
	if ( $self->{parent} )
	{
		if ( not defined $parent_conns )
		{
			# if they aren't specified then we guess...
			$parent_conns = $self->{DEFINITION}->find_connections( $self->{parent}->_get_object_name() );
		}

		foreach my $pconn ( @$parent_conns )
		{
			$self->_link_attr( $pconn->{local_column}, $self->{parent}, $pconn->{foreign_column} );
		}
	}

	# setup the properties
	foreach my $prop ( @{$self->{DEFINITION}->get_properties()} )
	{
		push @{$self->{props}}, Xmldoom::Object::Property->new( $prop, $self );
	}

	# set the initial values
	if ( defined $sets )
	{
		$self->set($sets);
	}

	return $self;
}

sub copy
{
	my $self = shift;

	my $class = ref($self);
	my $copy = $class->new();

	foreach my $column ( @{$self->{DEFINITION}->get_table()->get_columns()} )
	{
		if ( not $column->{primary_key} )
		{
			$copy->_set_attr( $column->{name}, $self->_get_attr($column->{name}) );
		}
	}

	return $copy;
}

sub _get_definition  { return shift->{DEFINITION}; }
sub _get_database    { return shift->{DEFINITION}->get_database(); }
sub _get_object_name { return shift->{DEFINITION}->get_name(); }
sub _get_properties  { return shift->{props}; }
sub _get_key         { return shift->{key}; }

sub _get_attributes
{
	my $self = shift;
	
	my $data = { };
	while ( my ($name, $attr) = each %{$self->{info}} )
	{
		$data->{$name} = $attr->get();
	}
	return $data;
}

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

	return $self->{info}->{$name}->get();
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

	if ( $self->{info}->{$name}->is_local() )
	{
		# we can only set attributes that are local to us.
		$self->{info}->{$name}->set( $value );
	}
	else
	{
		# if we are manually setting a link attribute, then this 
		# overrides it setting a local attribute.
		$self->{info}->{$name} = Xmldoom::Object::Attribute->new( $value );
	}

	# we are changed!
	$self->_changed();
}

sub _link_attr
{
	my ($self, $local_name, $object, $foreign_name) = @_;

	$self->{info}->{$local_name} = Xmldoom::Object::LinkAttribute->new( $object->{info}->{$foreign_name} );
}

sub _register_callback
{
	my ($self, $name, $cb) = @_;

	if ( not defined $self->{callbacks}->{$name} )
	{
		$self->{callbacks}->{$name} = [ $cb ];
	}
	else
	{
		push @{$self->{callbacks}->{$name}}, $cb;
	}
}

sub _unregister_callback
{
	my ($self, $name, $cb) = @_;

	if ( defined $self->{callbacks}->{$name} )
	{
		for( my $i = 0; $i < scalar @{$self->{callbacks}->{$name}}; $i++ )
		{
			if ( $self->{callbacks}->{$name}->[$i] == $cb )
			{
				splice @{$self->{callbacks}->{$name}}, $i, 1;
				last;
			}
		}
	}
}

sub _execute_callback
{
	my $self = shift;
	my $name = shift;

	if ( defined $self->{callbacks}->{$name} )
	{
		foreach my $cb ( @{$self->{callbacks}->{$name}} )
		{
			$cb->call( $cb, @_ );
		}
	}
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
		# call the user handler
		$self->_before_save( $status );

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
	$self->{original} = $self->_get_attributes();

	# call the user callbacks
	$self->_execute_callback("onsave", $self, $status);
}

sub do_save
{
	my ($self, $conn) = @_;

	my $definition = $self->{DEFINITION};
	my $table      = $definition->get_table();
	my $table_name = $definition->get_table_name();

	my $query;
	my $values = { };
	my $id_gen = { };

	if ( $self->{new} )
	{
		$query = $definition->get_insert_query();
		foreach my $column ( @{$table->get_columns()} )
		{
			my $col_name = $column->{name};

			if ( $self->{info}->{$col_name}->is_local() and
			     not defined $self->{info}->{$col_name}->get() )
			{
				# if the value is not defined, special behavior is required for
				# some special types.
				if ( $column->{primary_key} and ($column->{auto_increment} or $column->{id_generator}) )
				{
					if ( $column->{auto_increment} )
					{
						# use the default connection id generator
						$id_gen->{$col_name} = $conn->create_id_generator();
					}
					else
					{
						# use the module, yo!
						use_module($column->{id_generator});
						
						# use the custom id generator
						$id_gen->{$col_name} = $column->{id_generator}->new({
							conn        => $conn,
							object      => $self,
							table_name  => $table_name,
							column_name => $col_name
						});
					}

					if ( $id_gen->{$col_name}->is_before_insert() )
					{
						my $id = $id_gen->{$col_name}->get_id();

						# stash the contents of the id in the info hash
						$self->{info}->{$col_name}->set( $id );

						# put our newly found value into the query
						$values->{$col_name} = DBIx::Romani::Query::SQL::Literal->new( $id );

						# discard the id generator because this is already
						# taken care of.
						$id_gen->{$col_name} = undef;
					}
					else
					{
						# insert null, and grab the id from the id generator
						# after the insert.
						$values->{$col_name} = DBIx::Romani::Query::SQL::Null->new();
					}
				}
				elsif ( $column->{timestamp} )
				{
					$values->{$col_name} = DBIx::Romani::Query::Function::Now->new();
				}
				else
				{
					# else, insert a NULL!
					$values->{$col_name} = DBIx::Romani::Query::SQL::Null->new();
				}
			}
			else
			{
				# straigt simple value...
				$values->{$col_name} = DBIx::Romani::Query::SQL::Literal->new( $self->_get_attr($col_name) );
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
				$values->{"key.$col_name"} = DBIx::Romani::Query::SQL::Literal->new( $self->{key}->{$col_name} );
			}

			if ( $column->{timestamp} eq 'current' )
			{
				$values->{$col_name} = DBIx::Romani::Query::Function::Now->new();
			}
			else
			{
				# ... and the normal values
				$values->{$col_name} = DBIx::Romani::Query::SQL::Literal->new( $self->_get_attr($col_name) );
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

			if ( defined $id_gen->{$col_name} )
			{
				# we saved the id generator because its a get
				# after insert.  So, get, now...

				my $id = $id_gen->{$col_name}->get_id();
				$self->{key}->{$col_name}  = $id;
				$self->{info}->{$col_name}->set( $id );
			}
			else
			{
				$self->{key}->{$col_name} = $self->{info}->{$col_name}->get();
			}
		}
	}

	if ( $self->{new} )
	{
		$self->{new} = 0;
	}
}

sub _before_save
{
	my ($self, $type) = @_;

	# Virtual.
}

sub _on_save
{
	my ($self, $type) = @_;

	# Virtual.
}

sub _on_load
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
			$values{$column->{name}} = DBIx::Romani::Query::SQL::Literal->new( $self->{key}->{$column->{name}} );
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

sub get
{
	my $self = shift;
	
	my $values = { };

	foreach my $prop ( @{$self->{props}} )
	{
		$values->{$prop->get_name()} = $prop->get();
	}

	return $values;
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

__END__

=pod

=head1 NAME

Xmldoom::Object

=head1 SYNOPSIS

  # Assuming that 'MyObject' is a child of (->isa) Xmldoom::Object 
  use MyObject;

=head1 DESCRIPTION

This is the base class for all Xmldoom managed classes.  It defines their interfaces and the how they may be extended.

