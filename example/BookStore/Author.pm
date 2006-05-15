
package example::BookStore::Author;
use base qw(example::BookStore::Object);

BEGIN
{
	example::BookStore::Author->BindToObjectName( 'Author' );
}

1;

