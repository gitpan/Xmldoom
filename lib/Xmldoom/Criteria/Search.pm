
package Xmldoom::Criteria::Search;

use Xmldoom::Criteria;
use Xmldoom::Criteria::Comparison;
use Xmldoom::Criteria::Attribute;
use Xmldoom::Criteria::Property;
use Xmldoom::Criteria::Literal;
use DBIx::Romani::Query::Select;
use DBIx::Romani::Query::Where;
use DBIx::Romani::Query::Comparison;
use DBIx::Romani::Query::SQL::Column;
use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $type;

	if ( ref($args) eq 'HASH' )
	{
		$type = $args->{type};
	}
	else
	{
		$type = $args;
	}
	
	my $self = {
		type        => $type || $Xmldoom::Criteria::AND,
		comparisons => [ ]
	};

	bless  $self, $class;
	return $self;
}

sub get_type        { return shift->{type}; }
sub get_comparisons { return shift->{comparisons}; }

sub set_type
{
	my ($self, $type) = @_;
	$self->{type} = $type;
}

sub _add
{
	my $self = shift;

	my $comp;

	if ( $_[0]->isa( 'Xmldoom::Criteria::Search' ) )
	{
		$comp = shift;
	}
	else
	{
		$comp = Xmldoom::Criteria::Comparison->new( @_ );
	}

	push @{$self->{comparisons}}, $comp;
}

sub add
{
	my ($self, $lval, $rval, $type) = @_;

	if ( $lval->isa( 'Xmldoom::Criteria::Search' ) )
	{
		$self->_add( $lval );
	}
	else
	{
		$self->add_prop( $lval, $rval, $type );
	}
}

sub add_attr
{
	my ($self, $attr, $value, $type) = @_;

	my $rval;

	if ( ref($value) eq 'ARRAY' )
	{
		$rval = [ ];
		foreach my $i ( @$value )
		{
			push @$rval, Xmldoom::Criteria::Literal->new( $i );
		}
	}
	elsif ( defined $value )
	{
		$rval = Xmldoom::Criteria::Literal->new( $value );
	}

	$self->_add(
		Xmldoom::Criteria::Attribute->new( $attr ),
		$rval,
		$type
	);
}

sub add_prop
{
	my ($self, $prop, $value, $type) = @_;

	my $rval;

	if ( ref($value) eq 'ARRAY' )
	{
		$rval = [ ];
		foreach my $i ( @$value )
		{
			push @$rval, Xmldoom::Criteria::Literal->new( $i );
		}
	}
	elsif ( defined $value )
	{
		$rval = Xmldoom::Criteria::Literal->new( $value );
	}

	$self->_add(
		Xmldoom::Criteria::Property->new( $prop ),
		$rval,
		$type
	);
}

sub join_attr
{
	my ($self, $attr1, $attr2, $type) = @_;

	$self->_add(
		Xmldoom::Criteria::Attribute->new( $attr1 ),
		Xmldoom::Criteria::Attribute->new( $attr2 ),
		$type
	);
}

sub join_prop
{
	my ($self, $prop1, $prop2, $type) = @_;

	$self->_add(
		Xmldoom::Criteria::Property->new( $prop1 ),
		Xmldoom::Criteria::Property->new( $prop2 ),
		$type
	);
}

sub get_search_query
{
	my ($self, $database) = @_;

	my $where = DBIx::Romani::Query::Where->new( $self->get_type() );

	foreach my $comp ( @{$self->get_comparisons()} )
	{
		$where->add( $comp->get_search_query($database) );
	}

	if ( scalar @{$where->get_values()} == 1 )
	{
		# if there is only one, then return only that
		return $where->get_values()->[0];
	}
	elsif ( scalar @{$where->get_values()} == 0 )
	{
		# no search. we're grabbing everything?
		return undef;
	}

	return $where;
}

sub get_conn_query
{
	my ($self, $database, $tables) = @_;

	my $where = DBIx::Romani::Query::Where->new();

	#print STDERR Dumper $tables;

	# connect to the connect tables
	foreach my $table_name ( @$tables )
	{
		# skip attempting to join the first table
		if ( $table_name eq $tables->[0] )
		{
			next;
		}

		# find a connection to one of the other tables
		my $conns;
		foreach my $foreign_table_name ( @$tables )
		{
			$conns = $database->find_connections( $table_name, $foreign_table_name );

			# break if found
			if ( $conns )
			{
				last;
			}
		}

		if ( scalar @$conns == 0 )
		{
			print STDERR "** Unable to automatically join '$table_name' to any other tables in our search!\n";
			print STDERR "** 99\% of the time, this is an ERROR!  However, that 1\% must still work!\n";
			print STDERR "** FIX ME! FIX ME! FIX ME!  Xmldoom::Criteria::Search needs some love!\n";

			#die "Unable to join $table_name to any other tables in our search";
		}

		# join the two tables
		foreach my $conn ( @$conns )
		{
			my $join = DBIx::Romani::Query::Comparison->new();

			# NOTE: We do this in reverse than expected order because we looping
			# essentially backwards.  The first item on the list of foriegn tables
			# is thought to be our master table...

			$join->add( DBIx::Romani::Query::SQL::Column->new( $conn->{foreign_table}, $conn->{foreign_column} ) );
			$join->add( DBIx::Romani::Query::SQL::Column->new( $conn->{local_table}, $conn->{local_column} ) );
			$where->add( $join );
		}
	}

	if ( scalar @{$where->get_values()} == 0 )
	{
		# no connections required
		return undef;
	}

	return $where;
}

sub get_tables
{
	my ($self, $database, $conn_tables, $from_tables) = @_;

	foreach my $comp ( @{$self->get_comparisons()} )
	{
		$comp->get_tables( $database, $conn_tables, $from_tables );
	}
}

# NOTE: this should never be called without a 'tables' argument!  The first
# table passed to it should be the 'main table'.  If just grabbing attributes
# then pass all the tables that data is being grabbed from.
sub generate
{
	my $self = shift;
	my $args = shift;

	my $database;
	my $tables;

	if ( ref($args) eq 'HASH' )
	{
		$database = $args->{database};
		$tables   = $args->{tables};
	}
	else
	{
		$database = $args;
		$tables   = shift;
	}

	if ( ref($tables) ne 'ARRAY' )
	{
		$tables = [ $tables ];
	}

	my %conn_hash;
	my %from_hash;

	# put all the "extra" tables onto the from list, as they will be
	# manually connected.
	for ( my $i = 1; $i < scalar @$tables; $i++ )
	{
		$from_hash{$tables->[$i]} = 1;
	}

	# discover and append the other tables on the query onto our list
	$self->get_tables( $database, \%conn_hash, \%from_hash );

	# make sure that all the main tables are not included in the connection list, because
	# we are going to re-add them at the front of the array.
	foreach my $table_name ( @$tables )
	{
		delete $conn_hash{$table_name};
	}

	# tie it all together in one nifty little package
	my $result = {
		from_tables  => [ keys %from_hash ],
		search_where => $self->get_search_query( $database ),
		conn_where   => $self->get_conn_query( $database, [ @$tables, keys %conn_hash ] )
	};

	return $result;
}

sub generate_description
{
	my $self = shift;
	my $args = shift;

	my $database;
	my $object_name;

	if ( ref($args) eq 'HASH' )
	{
		$database    = $args->{database};
		$object_name = $args->{object_name};
	}
	else
	{
		$database    = $args;
		$object_name = shift;
	}

	my $object = $database->get_object( $object_name );
	my %comps;

	# group by the lvalues
	foreach my $comp ( @{$self->get_comparisons()} )
	{
		my $lval = $comp->get_lval();
		my $name;

		my %res = (
			type => $comp->get_type(),
			rval => $comp->get_rval(),
			lval => $lval,
		);

		# name
		if ( $lval->isa('Xmldoom::Criteria::Property') )
		{
			if ( $lval->get_object_name() eq $object_name )
			{
				$name = $object->get_property( $lval->get_property_name() )->get_description();
			}
			else
			{
				die "Unimplemented.";
			}

			$res{prop} = $database->get_object( $lval->get_object_name() )->get_property( $lval->get_property_name() );
		}
		elsif ( $lval->isa('Xmldoom::Criteria::Attribute') )
		{
			$name = sprintf "%s.%s", $lval->get_table_name(), $lval->get_column_name();
		}

		if ( not defined $comps{$name} )
		{
			$comps{$name} = [ ];
		}

		push @{$comps{$name}}, \%res;
	}

	my $text;

	if ( $self->get_type() eq 'AND' )
	{
		my @texts;
		while( my ($name, $value) = each %comps )
		{
			my @chunks;

			foreach my $comp ( @$value )
			{
				my $value = $comp->{rval}->[0]->get_value( $database, $comp->{lval} );
				my $op;

				my $desc = $comp->{prop}->get_value_description( $value );
				if ( $desc )
				{
					$value = $desc;
				}
				
				if ( $comp->{type} eq $Xmldoom::Criteria::EQUAL )
				{
					$op = "is $value";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::NOT_EQUAL )
				{
					$op = "isn't $value";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::GREATER_THAN )
				{
					$op = "is greater than $value";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::GREATER_EQUAL )
				{
					$op = "is $value or greater";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::LESS_THAN )
				{
					$op = "is less than $value";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::LESS_EQUAL )
				{
					$op = "is $value or less";
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::LIKE )
				{
					my $pure = $value;
					$pure =~ s/\%//g;

					if ( $value =~ /^\%.*\%$/ )
					{
						$op = "contains $pure";
					}
					elsif ( $value =~ /^\%.*/ )
					{
						$op = "ends with $pure";
					}
					elsif ( $value =~ /^.*\%/ )
					{
						$op = "begins with $pure";
					}
					else
					{
						$op = "is similar to $pure";
					}
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::NOT_LIKE )
				{
					my $pure = $value;
					$pure =~ s/\%//g;

					if ( $value =~ /^\%.*\%$/ )
					{
						$op = "doesn't contain $pure";
					}
					elsif ( $value =~ /^\%.*/ )
					{
						$op = "doesn't end with $pure";
					}
					elsif ( $value =~ /^.*\%/ )
					{
						$op = "doesn't begin with $pure";
					}
					else
					{
						$op = "isn't similar to $pure";
					}
				}
				elsif ( $comp->{type} eq $Xmldoom::Criteria::BETWEEN )
				{
					my $value2 = $comp->{rval}->[1]->get_value( $database, $comp->{lval} );
					$op = "is between $value and $value2";
				}
				else
				{
					die "Unimplemented.";
				}

				push @chunks, $op;
			}

			push @texts, sprintf( "%s %s", $name, join(' but ', @chunks ) );
		}

		$text = join ', and ', @texts;
	}
	else
	{
		# TODO: we should group these as 'comp1 (or comp2 or comp3)' in the text.
		die "Unimplemented.";
	}

	return $text;
}

sub clone
{
	my $self = shift;

	my $search = Xmldoom::Criteria::Search->new( $self->get_type() );

	foreach my $comp ( @{$self->get_comparisons()} )
	{
		push @{$search->{comparisons}}, $comp->clone();
	}

	return $search;
}

1;

