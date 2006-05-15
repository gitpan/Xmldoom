
package Xmldoom::ORB::Apache;

use Xmldoom::Definition;
use Apache;
use XML::Writer;
use CGI;
use strict;

use Data::Dumper;

my $DATABASE = undef;

sub write_object
{
	my ($xml, $object) = (shift, shift);

	# write our attribute base object XML jobber
	$xml->startTag('object');
	$xml->startTag('attributes');
	while ( my ($name, $value) = each %$object ) 
	{
		$xml->startTag( 'value', name => $name );
		$xml->characters( $value );
		$xml->endTag( 'value' );
	}
	$xml->endTag('attributes');
	$xml->endTag('object');
}

sub handler {
	my $r = shift;

	# setup our database definitions if they haven't been already
	if ( not defined $DATABASE )
	{
		$DATABASE = Xmldoom::Definition::parse_database_uri( $r->dir_config( 'XmldoomDatabaseXML' ) );
		Xmldoom::Definition::parse_object_uri( $DATABASE, $r->dir_config( 'XmldoomObjectsXML' ) );
		
		my $conn_factory_class = $r->dir_config( 'XmldoomConnFactory' );
		$DATABASE->set_connection_factory( $conn_factory_class->new() );
	}

	my $req_location = $r->location;
	my $req_uri      = $r->uri;

	my $obj_and_op;

	# attampt to determine the object type requested.
	if ( $req_uri =~ /^$req_location/ )
	{
		$obj_and_op = $req_uri;

		# remove the script name
		$obj_and_op =~ s/^$req_location//;

		# remove everything that comes after a '?' mark
		$obj_and_op =~ s/\?.*//;

		# remove beginning and trailing slashes
		$obj_and_op =~ s/^\///;
		$obj_and_op =~ s/\/$//;
	}

	my $object_name;
	my $operation;

	if ( $obj_and_op =~ /(.*)\/(.*)/ )
	{
		$object_name = $1;
		$operation   = $2;
	}

	my $definition = $DATABASE->get_object( $object_name );

	#print "uri: " . $r->uri . "\n";
	#print "location: " . $r->location . "\n";
	#print "path_info: " . $r->path_info . "\n";
	#print "object_name: " . $object_name . "\n";
	#print "operation: $operation\n";

	# read POST data from the client
	my $buffer = undef;
	if ( $r->method() eq 'POST' )
	{
		# Will this work without 'Content-Length' ?
		$r->read($buffer, $r->header_in('Content-Length'));
	}

	my $cgi = CGI->new();

	if ( $operation eq 'load' )
	{
		# load the object
		my $key = { };
		foreach my $pname ( $cgi->param )
		{
			$key->{$pname} = $cgi->param( $pname );
		}
		my $data = $definition->load( $key );

		# we are sending xml!
		$r->send_http_header('text/xml');

		# write the xml 
		my $xml = XML::Writer->new();
		write_object($xml, $data);
		$xml->end();
	}
	elsif ( $operation eq 'search' )
	{
		my $criteria = Xmldoom::Criteria::XML::parse_string($buffer);
		my $rs = $definition->search_rs( $criteria );

		# write the XML results
		my $xml = XML::Writer->new();
		$xml->startTag('results');
		while ( $rs->next() )
		{
			write_object($xml, $rs->get_row());
		}
		$xml->endTag('results');
		$xml->end();
	}
};

1;

