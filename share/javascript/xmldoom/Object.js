
dojo.provide('Xmldoom.Object');

dojo.require('dojo.dom');
dojo.require('dojo.lang');

Xmldoom.Object = function (name, args, database)
{
	// use a private variable, public function closure thing to 
	// store this value, so that the actual object is pure.
	this._get_name     = function () { return name; };
	this._get_database = function () { return database; };
	this._get_conn     = function () { return database._connection; };

	if ( args.length == 1 && dojo.lang.isObject(args[0]) )
	{
		// keyword arguments!
		args = args[0];
	
		// copy from a data hash
		if ( args.data )
		{
			// first the info
			for ( var key in args.data )
			{
				this._info[key] = args.data[key];
			}

			// then the keys
			for ( var key in this._key )
			{
				this._key[key] = args.data[key];
			}
		}

	}
}

Xmldoom.Object.make_objects = function (cons, data)
{
	for( var i = 0; i < data.length; i++ )
	{
		data[i] = new cons({ 'data': data[i] });
	}

	return data;
}

Xmldoom.Object.Search = function (conn, name, cons, criteria, callback)
{
	if ( callback )
	{
		var onload = function (result)
		{
			callback(Xmldoom.Object.make_objects(cons, result));
		};

		conn.search(name, criteria, onload);
	}
	else
	{
		return Xmldoom.Object.make_objects(cons, conn.search(name, criteria));
	}
}

