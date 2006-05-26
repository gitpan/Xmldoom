
package example::BookStore::Publisher;
use base qw(example::BookStore::Object);

use example::BookStore::PublisherIdGenerator;
use strict;

BEGIN
{
	my $definition = example::BookStore::Publisher->BindToObjectName( 'Publisher' );
}

1;

