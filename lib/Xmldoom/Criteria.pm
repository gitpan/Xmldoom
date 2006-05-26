
package Xmldoom::Criteria;

use Xmldoom::Criteria::Search;
use DBIx::Romani::Query::SQL::Column;
use strict;

use Data::Dumper;

# Search types
our $AND = 'AND';
our $OR  = 'OR';

# comparison types
our $EQUAL         = '=';
our $NOT_EQUAL     = '<>';
our $GREATER_THAN  = '>';
our $GREATER_EQUAL = '>=';
our $LESS_THAN     = '<';
our $LESS_EQUAL    = '<=';
our $LIKE          = 'LIKE';
our $NOT_LIKE      = 'NOT LIKE';
our $ILIKE         = 'ILIKE';
our $NOT_ILIKE     = 'NOT ILIKE';
our $BETWEEN       = 'BETWEEN';
our $IN            = 'IN';
our $NOT_IN        = 'NOT IN';
our $IS_NULL       = 'IS NULL';
our $IS_NOT_NULL   = 'IS NOT NULL';

sub new
{
	my $class = shift;
	my $args  = shift;

	my $parent;

	if ( ref($args) eq 'HASH' )
	{
		$parent = $args->{parent};
	}
	else
	{
		$parent = $args;
	}
	
	my $self = {
		parent   => $parent,
		search   => Xmldoom::Criteria::Search->new({ type => 'AND' }),
		order_by => [ ],
		group_by => [ ],
		limit    => undef,
		offset   => undef,
	};

	bless $self, $class;

	# TODO: Shouldn't this really happen just before we create the query?!?
	# automatically add the params from the parent
	if ( $parent )
	{
		# add the values of its primary keys to the criteria
		foreach my $col ( @{$parent->{DEFINITION}->get_table()->get_columns()} )
		{
			if ( $col->{primary_key} )
			{
				my $attr_name = join '/', $parent->{DEFINITION}->get_table_name(), $col->{name};
				# we use key instead of the attr values, in case they were changed, we
				# should still query against the current database value.
				$self->add_attr( $attr_name, $parent->{key}->{$col->{name}} );
			}
		}
	}
	
	return $self;
}

sub get_parent   { return shift->{parent}; }
sub get_type     { return "AND"; }
sub get_order_by { return shift->{order_by}; }
sub get_group_by { return shift->{order_by}; }
sub get_limit    { return shift->{limit}; }
sub get_offset   { return shift->{offset}; }

sub set_limit
{
	my ($self, $limit, $offset) = @_;
	$self->{limit}  = $limit;
	$self->{offset} = $offset;
}

sub add
{
	my $self = shift;
	$self->{search}->add( @_ );
}

sub add_attr
{
	my $self = shift;
	$self->{search}->add_attr( @_ );
}

sub add_prop
{
	my $self = shift;
	$self->{search}->add_prop( @_ );
}

sub join_attr
{
	my $self = shift;
	$self->{search}->join_attr( @_ );
}

sub join_prop
{
	my $self = shift;
	$self->{search}->join_prop( @_ );
}

sub add_order_by_attr
{
	my ($self, $attr, $dir) = @_;
	my ($table_name, $column) = split '/', $attr;

	my %order_by = (
		attr  => {
			table_name => $table_name,
			column     => $column,
		},
		value => {
			dir => $dir,
		}
	);

	push @{$self->{order_by}}, \%order_by;
}

sub add_order_by_prop
{
	my ($self, $prop, $dir) = @_;
	my ($object_name, $prop_name) = split '/', $prop;

	my %order_by = (
		prop  => {
			object_name => $object_name,
			prop_name   => $prop_name,
		},
		value => {
			dir => $dir,
		}
	);

	push @{$self->{order_by}}, \%order_by;
}

# A convenience alias.
sub add_order_by
{
	my $self = shift;
	$self->add_order_by_prop(@_);
}

sub add_group_by_attr
{
	my ($self, $attr) = @_;
	my ($table_name, $column) = split '/', $attr;

	my %group_by = (
		attr  => {
			table_name => $table_name,
			column     => $column,
		}
	);

	push @{$self->{group_by}}, \%group_by;
}

sub add_group_by_prop
{
	my ($self, $prop) = @_;
	my ($object_name, $prop_name) = split '/', $prop;

	my %group_by = (
		prop  => {
			object_name => $object_name,
			prop_name   => $prop_name,
		}
	);

	push @{$self->{group_by}}, \%group_by;
}

# A convenience alias.
sub add_group_by
{
	my $self = shift;
	$self->add_group_by_prop(@_);
}

# NOTE: Modifies the tables list to include the order by columns!!
sub _apply_order_by_to_query
{
	my ($self, $database, $tables, $query) = @_;

	foreach my $order_by ( @{$self->{order_by}} )
	{
		if ( defined $order_by->{attr} )
		{
			# TODO: look out for duplicates
			if ( $order_by->{attr}->{table_name} ne $tables->[0] )
			{
				push @$tables, $order_by->{attr}->{table_name};
			}
			
			my $value = DBIx::Romani::Query::SQL::Column->new({
				table => $order_by->{attr}->{table_name},
				name  => $order_by->{attr}->{column}
			});

			$query->add_order_by({ value => $value, dir => $order_by->{value}->{dir} });
		}
		elsif ( defined $order_by->{prop} )
		{
			my $object = $database->get_object( $order_by->{prop}->{object_name} );
			if ( not defined $object )
			{
				die "Unable to find object '$order_by->{prop}->{object_name}' in order_by";
			}

			my $prop   = $object->get_property( $order_by->{prop}->{prop_name} );
			if ( not defined $prop )
			{
				die "Unable to find property '$order_by->{prop}->{prop_name}' in object '$order_by->{prop}->{prop_name}' in order_by";
			}

			# TODO: this should really "visit" the returned lval to determine what
			# tables this includes ...
			# TODO: look out for duplicates
			if ( $object->get_table_name() ne $tables->[0] )
			{
				push @$tables, $object->get_table_name();
			}

			foreach my $lval ( @{$prop->get_query_lval()} )
			{
				$query->add_order_by({ value => $lval, dir => $order_by->{value}->{dir} });
			}
		}
	}
}

# TODO: This was just copied from _apply_order_by_to_query.  These two should be 
# merged if possible somehow.
# NOTE: Modifies the tables list to include the order by columns!!
sub _apply_group_by_to_query
{
	my ($self, $database, $tables, $query) = @_;

	foreach my $group_by ( @{$self->{group_by}} )
	{
		if ( defined $group_by->{attr} )
		{
			# TODO: look out for duplicates
			if ( $group_by->{attr}->{table_name} ne $tables->[0] )
			{
				push @$tables, $group_by->{attr}->{table_name};
			}
			
			my $value = DBIx::Romani::Query::SQL::Column->new({
				table => $group_by->{attr}->{table_name},
				name  => $group_by->{attr}->{column}
			});

			$query->add_group_by( $value );
		}
		elsif ( defined $group_by->{prop} )
		{
			my $object = $database->get_object( $group_by->{prop}->{object_name} );
			if ( not defined $object )
			{
				die "Unable to find object '$group_by->{prop}->{object_name}' in group_by";
			}

			my $prop   = $object->get_property( $group_by->{prop}->{prop_name} );
			if ( not defined $prop )
			{
				die "Unable to find property '$group_by->{prop}->{prop_name}' in object '$group_by->{prop}->{prop_name}' in group_by";
			}

			# TODO: this should really "visit" the returned lval to determine what
			# tables this includes ...
			# TODO: look out for duplicates
			if ( $object->get_table_name() ne $tables->[0] )
			{
				push @$tables, $object->get_table_name();
			}

			foreach my $lval ( @{$prop->get_query_lval()} )
			{
				$query->add_group_by( $lval );
			}
		}
	}
}

# Finishes up the query with all the search and connection stuff on the WHERE
# clause.  Should be called last after all the _apply functions or anything else
# that needs to be done to get the complete list of tables.
sub _setup_query
{
	my ($self, $database, $tables, $query) = @_;

	# get our search info
	my $search = $self->{search}->generate( $database, $tables );
	
	# add the from stuff
	foreach my $table_name ( @{$search->{from_tables}} )
	{
		$query->add_from( $table_name );
	}

	# build the where clause
	my $where;
	if ( defined $search->{conn_where} )
	{
		$where = $search->{conn_where};
	}
	if ( defined $search->{search_where} )
	{
		if ( $where )
		{
			$where->add( $search->{search_where} );
		}
		else
		{
			$where = $search->{search_where};
		}
	}
	$query->set_where( $where );

	# set the limit and offset
	$query->set_limit( $self->{limit}, $self->{offset} );
}

sub generate_query_for_object
{
	my ($self, $database, $object_name) = @_;

	my $definition = $database->get_object( $object_name );

	my $query      = $definition->get_select_query()->clone();
	my $table_name = $definition->get_table_name();
	my $table      = $definition->get_table();

	my @tables = ( $table_name );

	# add the order by
	$self->_apply_order_by_to_query( $database, \@tables, $query );
	
	# add the group by
	$self->_apply_group_by_to_query( $database, \@tables, $query );

	# setup the query
	$self->_setup_query( $database, \@tables, $query );

	return $query;
}

sub generate_query_for_object_count
{
	my ($self, $database, $object_name) = @_;

	my $definition = $database->get_object( $object_name );

	my $query      = $definition->get_select_query()->clone();
	my $table_name = $definition->get_table_name();
	my $table      = $definition->get_table();

	# make a query for COUNT() of the objects first primary key
	$query->clear_result();
	foreach my $column ( @{$table->get_columns()} )
	{
		if ( $column->{primary_key} )
		{
			my $count = DBIx::Romani::Query::Function::Count->new();
			$count->add( DBIx::Romani::Query::SQL::Column->new( $table_name, $column->{name} ) );
			$query->add_result( $count, 'count' );

			# we're cool
			last;
		}
	}
	
	# setup the query
	$self->_setup_query( $database, $table_name, $query );

	# we don't want to limit or offset on a count query
	$query->clear_limit();

	return $query;
}

sub generate_query_for_attrs
{
	my ($self, $database, $attrs) = (shift, shift, shift);

	# we can put on the list, or use an array hash
	if ( ref($attrs) ne 'ARRAY' )
	{
		$attrs = [ $attrs, @_ ];
	}

	my $query = DBIx::Romani::Query::Select->new();

	my @tables;
	foreach my $attr ( @$attrs )
	{
		my ($table_name, $column) = split '/', $attr;

		# add the column to the result list
		$query->add_result( DBIx::Romani::Query::SQL::Column->new( $table_name, $column ) );

		# add to the table list
		push @tables, $table_name;
	}

	# we have to manually add the first table as the "main" table, even though this
	# type of query doesn't really have a main table.
	$query->add_from( $tables[0] );

	# add the order by stuff
	$self->_apply_order_by_to_query( $database, \@tables, $query );

	# add the group by
	$self->_apply_group_by_to_query( $database, \@tables, $query );

	# setup the query
	$self->_setup_query( $database, \@tables, $query );

	return $query;
}

sub generate_description
{
	my $self = shift;

	return $self->{search}->generate_description( @_ );
}

sub clone
{
	my $self = shift;
	
	my $criteria = Xmldoom::Criteria->new( $self->get_parent() );

	# copy all the deep information
	$criteria->{search} = $self->{search}->clone();
	foreach my $order_by ( @{$self->get_order_by()} )
	{
		push @{$criteria->{order_by}}, $order_by;
	}
	foreach my $group_by ( @{$self->get_group_by()} )
	{
		push @{$criteria->{group_by}}, $group_by;
	}

	# shallow mallow
	$criteria->set_limit( $self->get_limit(), $self->get_offset() );

	return $criteria;
}

1;

