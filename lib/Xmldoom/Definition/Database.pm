
package Xmldoom::Definition::Database;

use Xmldoom::Definition::Table;
use Xmldoom::Definition::Object;
use Xmldoom::Definition::SAXHandler;
use Xmldoom::Definition::LinkTree;
use Xmldoom::Definition::Link;
use Xmldoom::Threads;
use Exception::Class::TryCatch;
use XML::SAX::ParserFactory;
use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $schema;

	if ( ref($args) eq 'HASH' )
	{
		$schema = $args->{schema};
	}
	else
	{
		$schema = $args;
	}

	my $self = {
		schema             => $schema,
		objects            => { },

		real_links         => Xmldoom::Definition::LinkTree->new(),
		inferred_links     => Xmldoom::Definition::LinkTree->new(),
		many_to_many_links => Xmldoom::Definition::LinkTree->new(),
		
		connection_factory => undef,
	};

	# go through and add all of the real links from the schema
	while ( my ($table_name, $table) = each %{$self->{schema}->get_tables()} )
	{
		foreach my $fkey ( @{$table->get_foreign_keys()} )
		{
			$self->{real_links}->add_link( Xmldoom::Definition::Link->new($fkey) );
		}
	}

	bless  $self, $class;
	return Xmldoom::Threads::make_shared($self, $args->{shared});
}

sub get_connection_factory { return shift->{connection_factory}; }
sub get_schema             { return shift->{schema}; }

sub get_tables { return shift->{schema}->get_tables; }
sub get_table
{
	my ($self, $name) = @_;
	return $self->{schema}->get_table($name);
}
sub has_table
{
	my ($self, $name) = @_;
	return $self->{schema}->has_table($name);
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

sub create_object
{
	my ($self, $object_name, $table_name) = @_;

	if ( defined $self->{objects}->{$object_name} )
	{
		die "Object definition for \"$object_name\" already added.";
	}

	# add and return the object definition
	my $object = Xmldoom::Definition::Object->new({
		definition  => $self,
		object_name => $object_name,
		table_name  => $table_name,
		shared      => Xmldoom::Threads::is_shared($self)
	});
	$self->{objects}->{$object_name} = $object;
	return $object;
}

sub find_links
{
	my ($self, $table1_name, $table2_name) = @_;

	if ( not $self->has_table($table1_name) or not $self->has_table($table2_name) )
	{
		die "Cannot find connections between one or more non-existant tables";
	}

	my $links = $self->{real_links}->get_links($table1_name, $table2_name);
	if ( defined $links )
	{
		return $links;
	}

	# TODO: check inferred links
	# TODO: check many-to-many links

	return [];
}

sub parse_object_string
{
	my ($self, $input) = @_;

	# build the parser
	my $handler = Xmldoom::Definition::SAXHandler->new( $self );
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);

	# phase 1 -- Create the objects and attach to respective tables
	$parser->parse_string($input);

	# phase 2 -- Actually add all the properties to the objects
	$parser->parse_string($input);
}

sub parse_object_uri
{
	my ($self, $uri) = @_;

	# build the parser
	my $handler = Xmldoom::Definition::SAXHandler->new( $self );
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);

	# phase 1 -- Create the objects and attach to respective tables
	$parser->parse_uri($uri);

	# phase 2 -- Actually add all the properties to the objects
	$parser->parse_uri($uri);
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

