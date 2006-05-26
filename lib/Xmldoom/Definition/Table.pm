
package Xmldoom::Definition::Table;

use strict;

sub _bool
{
	my $text = shift;
	if ( $text eq '1' or $text eq 'true' )
	{
		return 1;
	}
	elsif ( $text eq '0' or $text eq 'false' )
	{
		return 0;
	}

	return undef;
}

sub COLUMN_STRUCT
{
	my $args = shift;

	my $name;
	my $required;
	my $primary_key;
	my $id_generator;
	my $type;
	my $description;
	my $size;
	my $auto_increment;
	my $default;
	my $timestamp;

	if ( ref($args) eq 'HASH' )
	{
		$name           = $args->{name};
		$type           = $args->{type};
		$size           = $args->{size};
		$required       = $args->{required};
		$primary_key    = $args->{primary_key};
		$id_generator   = $args->{id_generator};
		$description    = $args->{description};
		$auto_increment = $args->{auto_increment};
		$default        = $args->{default};
		$timestamp      = $args->{timestamp};
	}
	else
	{
		$name        = $args;
		$type        = shift;
		$size        = shift;
		$required    = shift;
		$primary_key = shift;
		$description = shift;
	}

	if ( not defined $name or not defined $type )
	{
		die "Cannot create a column without setting both name and type";
	}

	my %COLUMN_STRUCT = (
		name           => $name,
		type           => uc($type),
		size           => $size,
		required       => _bool($required)       || 0,
		primary_key    => _bool($primary_key)    || 0,
		auto_increment => _bool($auto_increment) || 0,
		id_generator   => $id_generator,
		description    => $description,
		default        => $default,
		timestamp      => $timestamp || 0,
	);

	return \%COLUMN_STRUCT;
}

sub FOREIGN_KEY_STRUCT
{
	my $args = shift;

	my $local_column;
	my $foreign_table;
	my $foreign_column;

	if ( ref($args) eq 'HASH' )
	{
		$local_column   = $args->{local_column};
		$foreign_table  = $args->{foreign_table};
		$foreign_column = $args->{foreign_column};
	}
	else
	{
		$local_column   = $args;
		$foreign_table  = shift;
		$foreign_column = shift;
	}

	my %FOREIGN_KEY_STRUCT = (
		local_column   => $local_column,
		foreign_table  => $foreign_table,
		foreign_column => $foreign_column
	);

	return \%FOREIGN_KEY_STRUCT;
}

sub new
{
	my $class = shift;
	my $args  = shift;

	my $self = {
		columns      => [ ],
		foreign_keys => [ ]
	};

	bless  $self, $class;
	return $self;
}

sub get_columns { return shift->{columns}; }

sub get_column
{
	my ($self, $name) = @_;

	my @cols = grep { $_->{name} eq $name } @{$self->{columns}};
	if ( scalar @cols != 1 )
	{
		return undef;
	}

	return $cols[0];
}

sub get_column_type 
{
	my ($self, $name) = @_;

	my $column  = $self->get_column($name);
	my $value = { };

	if ( defined $column )
	{
		if ( $column->{type} =~ /char|text/i )
		{
			$value->{type} = "string";
			$value->{size} = $column->{size};
		}
		elsif ( $column->{type} =~ /enum/i )
		{
			# TODO: We should list the possible values!
			$value->{type} = "string";
		}
		elsif ( $column->{type} =~ /int/i )
		{
			$value->{type} = "integer";
		}
		elsif ( $column->{type} =~ /float/i )
		{
			$value->{type} = "float";
		}
		elsif ( $column->{type} =~ /date|time/i )
		{
			$value->{type} = "date";
		}
	}

	if ( not defined $value->{type} )
	{
		return undef;
	}
	
	return $value;
}

sub get_foreign_keys { return shift->{foreign_keys}; }

sub get_foreign_key
{
	my ($self, $name) = @_;
	
	my @keys = grep { $_->{local_column} eq $name } @{$self->{foreign_keys}};
	if ( scalar @keys != 1 )
	{
		return undef;
	}

	return $keys[0];
}

sub add_column
{
	my $self = shift;

	my $col = COLUMN_STRUCT(@_);
	if ( $self->get_column( $col->{name} ) )
	{
		die "Table already has a column named \"$col->{name}\"";
	}

	push @{$self->{columns}}, $col;
}

sub add_foreign_key
{
	my $self = shift;

	my $foreign_key = FOREIGN_KEY_STRUCT(@_);
	if ( not $self->get_column( $foreign_key->{local_column} ) )
	{
		die "Table doesn't have local column named \"$foreign_key->{local_column}\"";
	}

	push @{$self->{foreign_keys}}, $foreign_key;
}

sub find_connections
{
	my ($self, $table_name) = @_;

	my @conns;

	foreach my $key ( @{$self->get_foreign_keys()} )
	{
		if ( $key->{foreign_table} eq $table_name )
		{
			push @conns, $key;
		}
	}

	return \@conns;
}

1;

