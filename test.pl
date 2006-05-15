#/usr/bin/perl -w

use test::Xmldoom::Definition;
use test::Xmldoom::Criteria;
use test::Xmldoom::Object;

use Carp;

$SIG{__DIE__} = sub {
	Carp::confess(@_);
	#Carp::confess;
};

if ( @ARGV > 0 )
{
	my @spec;

	foreach my $s ( @ARGV )
	{
		my @t = split('::', $s);
		unshift @t, "Local";
		push @spec, join('::', @t);
	}

	Test::Class->runtests( @spec );
}
else
{
	# run 'em all!
	Test::Class->runtests;
}

