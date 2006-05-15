
dojo.provide('Xmldoom.Connection');

dojo.require('dojo.io.*');

//
// TODO: Add support for JSON as the transport.
//

Xmldoom.Connection = function (base_url)
{
	this.baseUrl = base_url;

	this._findAttrs = function (parent)
	{
		var node = parent.firstChild;

		while ( node )
		{
			if ( node.nodeType == dojo.dom.ELEMENT_NODE &&
				 node.tagName == 'attributes' )
			{
				break;
			}

			node = node.nextSibling;
		}

		return node;
	}

	this._parseObject = function (parent)
	{
		// jump down to the attributes section
		parent = this._findAttrs(parent);
		if ( !parent )
			return null;

		var node = parent.firstChild;
		var data = { };

		// go through the values and add them to data
		while ( node )
		{
			if ( node.nodeType == dojo.dom.ELEMENT_NODE &&
			     node.tagName == 'value' )
			{
				// Get the text value of the node, if it has a value, otherwise
				// we leave it at its default (by not setting it).
				if ( node.firstChild )
				{
					var key   = node.getAttribute('name');
					var value = node.firstChild.nodeValue;

					data[key] = value;
				}
			}

			node = node.nextSibling;
		}

		return data;
	}

	this._parseObjectList = function (parent)
	{
		var node = parent.firstChild;
		var list = [ ];

		while ( node )
		{
			if ( node.nodeType == dojo.dom.ELEMENT_NODE &&
			     node.tagName == 'object' )
			{
				var obj = this._parseObject(node);
				if ( obj )
				{
					list[list.length] = obj;
				}
			}

			node = node.nextSibling;
		}

		return list;
	}

	this.load = function (xmldoomType, key)
	{
		var result = null;

		dojo.io.bind({
			url:         this.baseUrl + xmldoomType + "/load",
			method:      'get',
			content:     key,
			load:        function (type, data, evt) { result = data; },
			mimetype:    "text/xml",
			sync:        true
		});

		if ( !result )
			return null;

		return this._parseObject(result.firstChild);
	}

	this.search = function (xmldoomType, criteria, callback)
	{
		var self   = this;
		var result = null;

		var sync;
		var onload;

		if ( callback )
		{
			onload = function (type, data, evt) 
			{
				callback(self._parseObjectList(data.firstChild));
			}
			sync = false;
		}
		else
		{
			onload = function (type, data, evt)
			{
				result = data;
			}
			sync = true;
		}

		dojo.io.bind({
			url:         this.baseUrl + xmldoomType + "/search",
			method:      'post',
			postContent: criteria.xml(),
			load:        onload,
			mimetype:    "text/plain",
			sync:        sync
		});

		// this will catch both errors, and when we are in async mode.
		if ( !result )
			return null;

		result = dojo.dom.createDocumentFromText(result);

		return this._parseObjectList(result.firstChild);
	}
}


