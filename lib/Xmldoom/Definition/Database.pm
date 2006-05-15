
package Xmldoom::Definition::Database;

use Xmldoom::Definition::Table;
use Xmldoom::Definition::Object;
use Exception::Class::TryCatch;
use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $self = {
		tables  => { },
		objects => { },
		connection_factory => undef,
	};

	bless  $self, $class;
	return $self;
}

sub get_connection_factory { return shift->{connection_factory}; }

sub get_tables { return shift->{tables}; }
sub get_table
{
	my ($self, $name) = @_;

	if ( not defined $self->{tables}->{$name} )
	{
		die "Unknown table named '$name'";
	}

	return $self->{tables}->{$name};
}
sub has_table
{
	my ($self, $name) = @_;
	return defined $self->{tables}->{$name};
}

sub get_objects { return shift->{objects}; }
sub get_object
{
	my ($self, $name) = @_;

	if ( not defined $self->{objects}->{$name} )
	{
		die "Unknown object named '$name'";
	}
	
	return $self->{objects}->{$name};
}
sub has_object
{
	my ($self, $name) = @_;
	return defined $self->{objects}->{$name};
}

sub set_connection_factory
{
	my ($self, $factory) = @_;
	$self->{connection_factory} = $factory;
}

sub create_db_connection
{
	return shift->get_connection_factory()->create();
}

sub create_table
{
	my ($self, $name) = @_;

	if ( exists $self->{tables}->{$name} )
	{
		die "Table name \"$name\" already exists";
	}

	my $table = Xmldoom::Definition::Table->new();
	$self->{tables}->{$name} = $table;
	return $table;
}

sub create_object
{
	my ($self, $object_name, $table_name) = @_;

	if ( defined $self->{objects}->{$object_name} )
	{
		die "Object definition for \"$object_name\" already added.";
	}

	# add and return the object definition
	my $object = Xmldoom::Definition::Object->new( $self, $object_name, $table_name );
	$self->{objects}->{$object_name} = $object;
	return $object;
}

sub find_connections
{
	my ($self, $table1_name, $table2_name) = @_;

	my $table1 = $self->get_table( $table1_name );
	my $table2 = $self->get_table( $table2_name );

	if ( not defined $table1 or not defined $table2 )
	{
		die "Cannot find connections between one or more non-existant tables";
	}

	my @conns;

	# go through all foreign-keys, looks for connections between these two tables
	foreach my $conn ( @{$table1->find_connections( $table2_name )} )
	{
		# add the local table for reference...
		my $c = { %$conn, local_table => $table1_name };
		push @conns, $c;
	}
	foreach my $conn ( @{$table2->find_connections( $table1_name )} )
	{
		# we have to switch everything to relate from the first table
		my $c = {
			local_table    => $conn->{foreign_table},
			local_column   => $conn->{foreign_column},
			foreign_table  => $table2_name,
			foreign_column => $conn->{local_column},
		};
		push @conns, $c;
	}

	return \@conns;
}

sub find_relationship
{
	my ($self, $table1_name, $table2_name) = @_;

	my $table1 = $self->get_table( $table1_name );
	my $table2 = $self->get_table( $table2_name );

	my $conns = $self->find_connections( $table1_name, $table2_name );
	
	my $local_primary   = 1;
	my $foreign_primary = 1;

	# this has to loop over all the columns in the table, to make sure that
	# we only say that the connection is a primary key, if it includes ALL
	# of the primary keys.  Other keys can be included too.
	foreach my $column ( @{$table1->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			my $is_conn = 0;
			foreach my $conn ( @$conns )
			{
				if ( $conn->{local_column} eq $column->{name} )
				{
					$is_conn = 1;
					last;
				}
			}
			if ( not $is_conn )
			{
				$local_primary = 0;
				last;
			}
		}
	}
	# ... and the foreign table
	foreach my $column ( @{$table2->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			my $is_conn = 0;
			foreach my $conn ( @$conns )
			{
				if ( $conn->{foreign_column} eq $column->{name} )
				{
					$is_conn = 1;
					last;
				}
			}
			if ( not $is_conn )
			{
				$foreign_primary = 0;
				last;
			}
		}
	}

	if ( not $local_primary and $foreign_primary )
	{
		return "many-to-one";
	}
	elsif ( $local_primary and not $foreign_primary )
	{
		return "one-to-many";
	}
	elsif ( $local_primary and $foreign_primary )
	{
		return "one-to-one";
	}
	else
	{
		return "many-to-many";
	}
}

sub SearchRS
{
	my $self     = shift;
	my $criteria = shift;

	my $query = $criteria->generate_query_for_attrs( $self, @_ );

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

sub Search
{
	my $class = shift;
	my $rs    = $class->SearchRS( @_ );
	
	my @ret;

	# unravel our result set
	while ( $rs->next() )
	{
		push @ret, $rs->get_row();
	}

	return wantarray ? @ret : \@ret;
}

#sub DESTROY
#{
#	my $self = shift;
#
#	if ( $self->get_dbh() )
#	{
#		$self->get_dbh()->disconnect();
#		$self->set_dbh( undef );
#	}
#}

1;

