
package example::BookStore::Order;
use base qw(example::BookStore::Object);

use example::BookStore::BooksOrdered;
use strict;

BEGIN
{
	example::BookStore::Order->BindToObjectName( 'Order' );
}

1;

