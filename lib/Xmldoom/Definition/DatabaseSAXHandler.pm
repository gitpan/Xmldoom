
package Xmldoom::Definition::DatabaseSAXHandler;

use Xmldoom::Definition::Database;
use strict;

sub new
{
	my $class = shift;
	my $args = shift;

	my $self = {
		database      => undef,
		table         => undef,
		foreign_table => undef,
	};

	bless  $self, $class;
	return $self;
}

sub start_document 
{
	my ($self, $doc) = @_;

	$self->{database} = Xmldoom::Definition::Database->new();
}

sub end_document 
{
	my ($self, $doc) = @_;
}

sub start_element 
{
	my ($self, $el) = @_;

	# simple aliases
	my $name = $el->{'LocalName'};
	my $attrs = $el->{'Attributes'};

	if ( $name eq "database" )
	{
		# TODO: something with this info ...
	}
	elsif ( $name eq "table" )
	{
		if ( defined $self->{table} )
		{
			die "Cannot nest table declarations";
		}

		my $table_name = $attrs->{'{}name'}->{Value};
		my $table = $self->{database}->create_table( $table_name );

		# store for column adding hot action
		$self->{table} = $table;
	}
	elsif ( $name eq "column" )
	{
		if ( not defined $self->{table} )
		{
			die "Column must be defined inside of a <table/> tag.";
		}

		my $args = { };

		if ( defined $attrs->{'{}name'} )
		{
			$args->{name} = $attrs->{'{}name'}->{Value};
		}
		if ( defined $attrs->{'{}required'} )
		{
			$args->{required} = $attrs->{'{}required'}->{Value};
		}
		if ( defined $attrs->{'{}primaryKey'} )
		{
			$args->{primary_key} = $attrs->{'{}primaryKey'}->{Value};
		}
		if ( defined $attrs->{'{}type'} )
		{
			$args->{type} = $attrs->{'{}type'}->{Value};
		}
		if ( defined $attrs->{'{}size'} )
		{
			$args->{size} = $attrs->{'{}size'}->{Value};
		}
		if ( defined $attrs->{'{}description'} )
		{
			$args->{description} = $attrs->{'{}description'}->{Value};
		}
		if ( defined $attrs->{'{}auto_increment'} )
		{
			$args->{auto_increment} = $attrs->{'{}auto_increment'}->{Value};
		}
		if ( defined $attrs->{'{}default'} )
		{
			$args->{default} = $attrs->{'{}default'}->{Value};
		}
		if ( defined $attrs->{'{}timestamp'} )
		{
			$args->{timestamp} = $attrs->{'{}timestamp'}->{Value};
		}

		$self->{table}->add_column( $args );
	}
	elsif ( $name eq 'foreign-key' )
	{
		if ( not defined $self->{table} or defined $self->{foreign_table} )
		{
			die "<foreign-key/> can only be defined inside of <table/>";
		}

		$self->{foreign_table} = $attrs->{'{}foreignTable'}->{Value};
	}
	elsif ( $name eq 'reference' )
	{
		if ( not defined $self->{foreign_table} )
		{
			die "<reference/> tag must be inside of a <foreign-key> tag with a valid foreignTable attribute";
		}

		my $args = {
			local_column => $attrs->{'{}local'}->{Value},
			foreign_table => $self->{foreign_table},
			foreign_column => $attrs->{'{}foreign'}->{Value}
		};
		$self->{table}->add_foreign_key($args);
	}
}

sub characters 
{
	my ($self, $h) = @_;

	# simple alias
	my $text = $h->{'Data'};
}

sub end_element 
{
	my ($self, $el) = @_;

	# simple alias
	my $name = $el->{'LocalName'};

	if ( $name eq "table" )
	{
		# mark that we have left the table
		$self->{table} = undef;
	}
	elsif ( $name eq 'foreign-key' )
	{
		# mark that we have left the foreign key
		$self->{foreign_table} = undef;
	}
}

1;

