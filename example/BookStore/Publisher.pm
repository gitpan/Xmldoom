
package example::BookStore::Publisher;
use base qw(example::BookStore::Object);

BEGIN
{
	example::BookStore::Publisher->BindToObjectName( 'Publisher' );
}

1;

