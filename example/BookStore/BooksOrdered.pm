
package example::BookStore::BooksOrdered;
use base qw(example::BookStore::Object);

use example::BookStore::Book;
use strict;

BEGIN
{
	example::BookStore::BooksOrdered->BindToObjectName( 'BooksOrdered' );
}

1;

