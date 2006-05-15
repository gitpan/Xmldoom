
package example::BookStore::Book;
use base qw(example::BookStore::Object);

use example::BookStore::BookAgeProperty;
use strict;

BEGIN
{
	my $obj = example::BookStore::Book->BindToObjectName( 'Book' );

	# add our custom property
	$obj->set_custom_property( 'age', 'example::BookStore::BookAgeProperty' );
}

1;

