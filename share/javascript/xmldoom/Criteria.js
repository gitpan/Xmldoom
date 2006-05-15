
dojo.provide('Xmldoom.Criteria');

dojo.require('dojo.lang');

/*
Used to produce the XML for doing an Xmldoom::Criteria search.
*/

Xmldoom.Criteria = function ( xml ) {

	this.order_by_node = null;

	var cons_node;

	if ( typeof(xml) != 'undefined' )
	{
		// read from an XML string
		this.doc = dojo.dom.createDocumentFromText(xml);
		this.order_by_node = this.doc.getElementsByTagName('order-by').item(0);
		cons_node = this.doc.getElementsByTagName('constraints').item(0);
	}
	else
	{
		// create a new document
		this.doc = dojo.dom.createDocument();
		this.doc.appendChild(this.doc.createElement("search"));
	}
	if ( cons_node == null || typeof(cons_node) == 'undefined' )
	{
		cons_node = this.doc.createElement("constraints"); 
		this.doc.firstChild.appendChild(cons_node);
	}

	// create the search object
	this.search = new Xmldoom.Criteria.Search( this.doc, cons_node );

	this.getDoc = function() { return this.doc; };
	this.getNode = function() {
			return this.getDoc().firstChild; };

	this.setType = function(type) { 
		if (!type || type == '')
			this.getNode().removeAttribute('type');
		else
			this.getNode().setAttribute('type',type);
		return this; 
	};

	this.getType = function() { return this.getNode().getAttribute('type'); }

	this.xml = function() { 
		return dojo.dom.innerXML(this.getNode());
	};

	// member functions
	this.get_constraints = function ()         { return this.search.get(); };
	this.add_prop        = function (a1,a2,a3) { this.search.add_prop(a1,a2,a3); };
	this.add             = function (a1,a2,a3) { this.add_prop(a1,a2,a3); };

	this.add_order_by = function (name, dir)
	{
		if ( this.order_by_node == null )
		{
			this.order_by_node = this.doc.createElement("order-by");
			this.getNode().appendChild(this.order_by_node);
		}

		var prop_node = this.doc.createElement('property');
		prop_node.setAttribute('name', name);
		if ( dir )
		{
			prop_node.setAttribute('dir', dir);
		}

		this.order_by_node.appendChild(prop_node);
	}

	this.get_order_by = function ()
	{
		var ret = Array();
		var node, i, name, dir;

		if ( !this.order_by_node )
		{
			// toss back an empty list
			return ret;
		}

		node = this.order_by_node.firstChild;

		while ( node )
		{
			if ( node.tagName == 'property' )
			{
				ret[ret.length] = {
					'prop':  node.getAttribute('name'),
					'dir' :  node.getAttribute('dir')
				};
			}

			node = node.nextSibling;
		}

		return ret;
	}
} 

Xmldoom.Criteria.ComparisonTypes = {
	AND:           'and',
	OR:            'or',
	EQUAL:         'equal',
	NOT_EQUAL:     'not-equal',
	GREATER_THAN:  'greater-than',
	GREATER_EQUAL: 'greater-equal',
	LESS_THAN:     'less-than',
	LESS_EQUAL:    'less-equal',
	LIKE:          'like',
	NOT_LIKE:      'not-like',
	BETWEEN:       'between',
	IN:            'in',
	NOT_IN:        'not-in',
	IS_NULL:       'is-null',
	IS_NOT_NULL:   'is-not-null'
};

Xmldoom.Criteria.Search = function(doc, node)
{
	this.doc  = doc;
	this.node = node;

	// Two synonymous functions
	this.getNode = function() { return this.node; };

	// constraint manipulating functions

	this.add_prop = function (name, value, type)
	{
		if ( typeof(type) == 'undefined' )
		{
			type = Xmldoom.Criteria.ComparisonTypes.EQUAL;
		}

		// create the property node
		var property_node;
		property_node = this.doc.createElement('property');
		property_node.setAttribute('name', name);
		this.getNode().appendChild(property_node);

		// create the comparison node
		var comparison_node = this.doc.createElement( type );
		if ( type == Xmldoom.Criteria.ComparisonTypes.IN || 
		     type == Xmldoom.Criteria.ComparisonTypes.NOT_IN )
		{
			alert('Criteria type "'+type+'" not implemented.');
		}
		else if ( type == Xmldoom.Criteria.ComparisonTypes.BETWEEN )
		{
			comparison_node.setAttribute('min', value[0]);
			comparison_node.setAttribute('max', value[1]);
		}
		else
		{
			if ( dojo.lang.isObject(value) )
			{
				var object_node = this.doc.createElement('object');
				for( var attr in value )
				{
					object_node.setAttribute(attr, value[attr]);
				}
				comparison_node.appendChild( object_node );
			}
			else
			{
				// add the text to the comparison.
				comparison_node.appendChild( this.doc.createTextNode(value) );
			}
		}
		property_node.appendChild( comparison_node );
	}

	this.get = function ()
	{
		var ret = Array();
		var node, i, name, type, value;

		for(i = 0; i < this.getNode().childNodes.length; i++ )
		{
			node = this.getNode().childNodes.item(i);
			
			if ( node.tagName == 'property' )
			{
				type = node.firstChild.tagName;
				if ( type == Xmldoom.Criteria.ComparisonTypes.BETWEEN )
				{
					value = [
						node.firstChild.getAttribute('min'),
						node.firstChild.getAttribute('max')
					];
				}
				else
				{
					if ( (type == Xmldoom.Criteria.ComparisonTypes.EQUAL || 
					      type == Xmldoom.Criteria.ComparisonTypes.NOT_EQUAL) &&
						 node.firstChild.firstChild.nodeType == dojo.dom.ELEMENT_NODE )
					{
						var obj_node  = node.firstChild.firstChild;

						value = { };
						
						for( var e = 0; e < obj_node.attributes.length; e++ )
						{
							var attr = obj_node.attributes.item(e);
							value[attr.name] = attr.value;
						}
					}
					else
					{
						value = node.firstChild.firstChild.text;
					}
				}

				ret[ret.length] = {
					'prop':  node.getAttribute('name'),
					'comp':  type,
					'value': value
				};
			}
		}

		return ret;
	}
} 

/* 
Removes all of the current constraints.
*/

/*
function SearchObject_clearConstraints()
{
	var children = this.getNode().childNodes;
	for(i = 0; i < children.length; i++)
	{
		this.getNode().removeChild(children.item(i));
	}
}
*/


