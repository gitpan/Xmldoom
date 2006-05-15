
package Xmldoom::Object::Property;

use Scalar::Util qw(weaken);
use strict;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $definition;
	my $object;

	if ( ref($args) eq 'HASH' )
	{
		$definition = $args->{definition};
		$object     = $args->{object};
	}
	else
	{
		$definition = $args;
		$object     = shift;
	}

	my $self = {
		definition => $definition,
		object    => $object,
		autoload  => undef,
	};

	if ( defined $self->{object} )
	{
		weaken( $self->{object} );
	}

	bless  $self, $class;
	return $self;
}

sub get_name      { return shift->{definition}->get_name(); }
sub get_type      { return shift->{definition}->get_type(); }
sub get_data_type { return shift->{definition}->get_data_type(@_); }

sub set
{
	my $self = shift;
	$self->{definition}->set( $self->{object}, @_ );
}

sub get
{
	my $self = shift;
	return $self->{definition}->get( $self->{object} );
}

sub get_hint
{
	my ($self, $name) = @_;
	return $self->{definition}->get_hint( $name );
}

sub get_pretty
{
	my $self = shift;

	my $value = $self->{definition}->get( $self->{object} );
	my $desc  = $self->{definition}->get_value_description( $value );

	if ( defined $desc )
	{
		$value = $desc;
	}

	return $value;
}

sub get_autoload_list
{
	my $self = shift;

	return [
		@{$self->{definition}->get_autoload_get_list()},
		@{$self->{definition}->get_autoload_set_list()}
	];
}

sub autoload
{
	my ($self, $func_name) = (shift, shift);
	return $self->{definition}->autoload( $self->{object}, $func_name, @_ );
}

1;

