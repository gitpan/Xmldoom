
package Xmldoom::Definition;

use Xmldoom::Definition::DatabaseSAXHandler;
use Xmldoom::Definition::ObjectSAXHandler;
use XML::SAX::ParserFactory;
use strict;

use Data::Dumper;

sub parse_database_string
{
	my $input = shift;

	# build the parser
	my $handler = Xmldoom::Definition::DatabaseSAXHandler->new();
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);
	$parser->parse_string($input);

	return $handler->{database};
}

sub parse_database_uri
{
	my $uri = shift;

	# build the parser
	my $handler = Xmldoom::Definition::DatabaseSAXHandler->new();
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);
	$parser->parse_uri($uri);

	return $handler->{database};
}

sub parse_object_string
{
	my ($database, $input) = @_;

	# build the parser
	my $handler = Xmldoom::Definition::ObjectSAXHandler->new( $database );
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);

	# phase 1 -- Create the objects and attach to respective tables
	$parser->parse_string($input);

	# phase 2 -- Actually add all the properties to the objects
	$parser->parse_string($input);
}

sub parse_object_uri
{
	my ($database, $uri) = @_;

	# build the parser
	my $handler = Xmldoom::Definition::ObjectSAXHandler->new( $database );
	my $parser = XML::SAX::ParserFactory->parser(Handler => $handler);

	# phase 1 -- Create the objects and attach to respective tables
	$parser->parse_uri($uri);

	# phase 2 -- Actually add all the properties to the objects
	$parser->parse_uri($uri);
}

1;

