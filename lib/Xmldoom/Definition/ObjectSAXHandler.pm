
package Xmldoom::Definition::ObjectSAXHandler;

use Xmldoom::Definition::Property::Simple;
use Xmldoom::Definition::Property::Object;
use Xmldoom::Definition::Property::PlaceHolder;
use Xmldoom::Criteria::XML;
use Roma::Query::XML::Util qw/parse_boolean/;
use XML::GDOME;
use strict;

use Data::Dumper;

# In the interest of speed and memory and Perl's poor garbage collection, we actually
# run this parser twice over the same file to get all its data.

sub new
{
	my $class = shift;
	my $args = shift;

	my $database;

	if ( ref($args) eq 'HASH' )
	{
		$database = $args->{database};
	}
	else
	{
		$database = $args;
	}

	my $self = {
		database => $database,
		phase    => 1,

		# for phase 2
		cur_obj     => undef,
		prop_name   => undef,
		prop_type   => undef,
		prop_args   => undef,
		dom_doc     => undef,
		dom_stack   => [],
		in_criteria => 0,
	};

	bless  $self, $class;
	return $self;
}

sub start_document 
{
	my ($self, $doc) = @_;

	if ( $self->{phase} > 2 )
	{
		die "Cannot run more than twice on the same input";
	}
}

sub end_document 
{
	my ($self, $doc) = @_;

	# move to next phase
	$self->{phase}++;
}

sub start_element 
{
	my ($self, $el) = @_;

	# simple aliases
	my $name = $el->{'LocalName'};
	my $attrs = $el->{'Attributes'};

	# if we are in criteria, we operate in super quaazy mode
	if ( $self->{in_criteria} )
	{
		if ( $self->{phase} == 2 )
		{
			# create a new element
			my $element = $self->{dom_doc}->createElement($name);
			while ( my ($key, $value) = each %$attrs )
			{
				# remove crazy NS symbols that Perl SAX uses.
				$key =~ s/^\{\}//;

				$element->setAttribute($key, $value->{Value});
			}
			
			# add to parent and push to stack
			$self->{dom_stack}->[-1]->appendChild($element);
			push @{$self->{dom_stack}}, $element;
		}

		# drop the monkey and run!
		return;
	}
	
	if ( $name eq 'objects' )
	{
		# just let pass through
	}
	elsif ( $name eq 'object' and not $self->{prop_name} )
	{
		if ( $self->{phase} == 1 )
		{
			# actually create the object in the definition, and attach
			# it to the appropriate table.
			my $object_name = $attrs->{'{}name'}->{Value};
			my $table_name  = $attrs->{'{}table'}->{Value};

			$self->{database}->create_object( $object_name, $table_name );
		}
		elsif ( $self->{phase} == 2 )
		{
			# retrieve and set as the current object
			my $object_name  = $attrs->{'{}name'}->{Value};
			$self->{cur_obj} = $self->{database}->get_object( $object_name );
		}
	}
	elsif ( $name eq 'property' )
	{
		$self->{prop_name} = $attrs->{'{}name'}->{Value};
		if ( not $self->{prop_name} )
		{
			die "Invalid property name: '$self->{prop_name}'";
		}

		my $args = { 
			parent  => $self->{cur_obj},
			name    => $self->{prop_name},
		};

		if ( defined $attrs->{'{}description'} )
		{
			$args->{description} = $attrs->{'{}description'}->{Value};
		}
		if ( defined $attrs->{'{}searchable'} )
		{
			$args->{searchable} = parse_boolean( $attrs->{'{}searchable'}->{Value} );
		}
		if ( defined $attrs->{'{}reportable'} )
		{
			$args->{reportable} = parse_boolean( $attrs->{'{}reportable'}->{Value} );
		}
		if ( defined $attrs->{'{}get_name'} )
		{
			$args->{get_name} = $attrs->{'{}get_name'}->{Value};
		}
		if ( defined $attrs->{'{}set_name'} )
		{
			$args->{set_name} = $attrs->{'{}set_name'}->{Value};
		}

		$self->{prop_args} = $args;
	}
	elsif ( $name eq 'simple' or $name eq 'custom' or ( $name eq 'object' and $self->{prop_name} ) )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		# convenience
		my $args = $self->{prop_args};

		# do the specifics
		if ( $name eq 'simple' )
		{
			if ( defined $attrs->{'{}attribute'} )
			{
				$args->{attribute} = $attrs->{'{}attribute'}->{Value};
			}
		}
		elsif ( $name eq 'object' )
		{
			$args->{object_name} = $attrs->{'{}name'}->{Value};

			if ( defined $attrs->{'{}inter_table'} )
			{
				$args->{inter_table} = $attrs->{'{}inter_table'}->{Value};
			}
		}

		# set our property name
		$self->{prop_type} = $name;
	}
	elsif ( $name eq 'trans' )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( $self->{prop_type} ne 'simple' )
		{
			die "<trans/> tag must be inside of <simple> property";
		}

		my $dir  = $attrs->{'{}dir'}->{Value} || 'both';
		my $from = $attrs->{'{}from'}->{Value};
		my $to   = $attrs->{'{}to'}->{Value};

		if ( $dir eq 'out' or $dir eq 'both' )
		{
			if ( not defined $self->{prop_args}->{trans_from} )
			{
				$self->{prop_args}->{trans_from} = { };
			}
			$self->{prop_args}->{trans_from}->{$from} = $to;
		}

		if ( $dir eq 'both' )
		{
			# reverse these to fill in the next section
			my $temp = $from;
			$from = $to;
			$to = $temp;
		}

		if ( $dir eq 'in' or $dir eq 'both' )
		{
			if ( not defined $self->{prop_args}->{trans_to} )
			{
				$self->{prop_args}->{trans_to} = { };
			}
			$self->{prop_args}->{trans_to}->{$from} = $to;
		}
	}
	elsif ( $name eq 'options' )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( exists $self->{prop_args}->{options} )
		{
			die "<options> tag cannot be defined twice";
		}

		# set us up
		$self->{prop_args}->{options} = [ ];
		if ( defined $attrs->{'{}inclusive'} )
		{
			$self->{prop_args}->{inclusive} = parse_boolean( $attrs->{'{}inclusive'}->{Value} );
		}

		# split for the two property types
		if ( $self->{prop_type} eq 'simple' )
		{
			if ( defined $attrs->{'{}table'} )
			{
				$self->{prop_args}->{options_table} = $attrs->{'{}table'}->{Value};
			}
			if ( defined $attrs->{'{}column'} )
			{
				$self->{prop_args}->{options_column} = $attrs->{'{}column'}->{Value};
			}
		}
		elsif ( $self->{prop_type} eq 'object' )
		{
			if ( defined $attrs->{'{}property'} )
			{
				$self->{prop_args}->{options_property} = $attrs->{'{}property'}->{Value};
			}
		}
	}
	elsif ( $name eq 'criteria' )
	{
		# mark our special mode
		$self->{in_criteria} = 1;
		
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( not exists $self->{prop_args}->{options} )
		{
			die "<criteria/> tag must be inside of <options> section";
		}

		# here we create our initial DOM document
		$self->{dom_doc} = XML::GDOME->createDocument( undef, 'criteria', undef );
		push @{$self->{dom_stack}}, $self->{dom_doc}->documentElement;
	}
	elsif ( $name eq 'option' )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( $self->{prop_type} ne 'simple' or not exists $self->{prop_args}->{options} )
		{
			die "<option/> tag must be inside of <options> section";
		}

		my $opt   = {
			value       => $attrs->{'{}value'}->{Value},
			description => $attrs->{'{}description'}->{Value}
		};

		push @{$self->{prop_args}->{options}}, $opt;
	}
	elsif ( $name eq 'hints' )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( exists $self->{prop_args}->{hints} )
		{
			die "Cannot nest <hints> tags";
		}

		# set us up
		$self->{prop_args}->{hints} = { };
	}
	elsif ( $name eq 'hint' )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		if ( not exists $self->{prop_args}->{hints} )
		{
			die "<hint/> tag must be inside of <hints> section";
		}

		my $name  = $attrs->{'{}name'}->{Value};
		my $value = $attrs->{'{}value'}->{Value};

		if ( not defined $value )
		{
			$value = 1;
		}

		if ( defined $self->{prop_args}->{$name} )
		{
			die "Cannot defined multiple property hint's named '$name'";
		}

		$self->{prop_args}->{hints}->{$name} = $value;
	}
	else
	{
		die "Unknown tag: $name";
	}
}

sub characters 
{
	my ($self, $h) = @_;

	# simple alias
	my $text = $h->{'Data'};

	if ( $self->{in_criteria} and $self->{phase} == 2 )
	{
		# add text nodes to the object on the top of the stack
		my $node = $self->{dom_doc}->createTextNode($text);
		$self->{dom_stack}->[-1]->appendChild($node);
	}
}

sub end_element 
{
	my ($self, $el) = @_;

	# simple alias
	my $name = $el->{'LocalName'};

	if ( $self->{in_criteria} )
	{
		if ( $name eq 'criteria' )
		{
			# exist freaky-deeky mode
			$self->{in_criteria} = 0;
		}

		if ( $self->{phase} == 2 )
		{
			# pop tag off the stack.
			pop @{$self->{dom_stack}};

			# now, take care of business
			if ( $name eq 'criteria' )
			{
				# parse the criteria DOM and add it to the property options.
				my $criteria = Xmldoom::Criteria::XML::parse_dom( $self->{dom_doc} );
				$self->{prop_args}->{options_criteria} = $criteria;

				# release the dom from memory
				$self->{dom_doc} = undef;
			}
		}

		return;
	}

	# clear state vars...
	if ( $name eq 'object' and not $self->{prop_name} )
	{
		$self->{cur_obj} = undef;
	}
	elsif ( $name eq 'property' )
	{
		$self->{prop_name} = undef;
	}
	elsif ( $name eq 'simple' or $name eq 'custom' or ( $name eq 'object' and $self->{prop_name} ) )
	{
		if ( $self->{phase} == 1 )
		{
			# we skip over these in phase 1 !!
			return;
		}

		my $prop;
		
		# do the specifics
		if ( $name eq 'simple' )
		{
			# create simple!
			$prop = Xmldoom::Definition::Property::Simple->new($self->{prop_args});
		}
		elsif ( $name eq 'object' )
		{
			# create object!
			$prop = Xmldoom::Definition::Property::Object->new($self->{prop_args});
		}
		elsif ( $name eq 'custom' )
		{
			# create a place holder property
			$prop = Xmldoom::Definition::Property::PlaceHolder->new($self->{prop_args});
		}

		# add 'er!
		$self->{cur_obj}->add_property( $prop );

		# clear state
		$self->{prop_type} = undef;
	}
}

1;

