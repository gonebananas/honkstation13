#include "XML.dm"

XML/Element
	var
		_tag
		XML/Element/_parent
		_attributes_params			// For space/efficiency, store attributes as a params list.
		list/_children

	New(tag, text)
		if (tag) setTag(tag)
		if (text) setXML(text)
		return ..()

	Del()
		_parent = null

		if (_children)
			for (var/child in _children)
				del(child)
			_children = null

		return ..()

	Tag()
		return _tag

	setTag(tag)
		_tag = tag

	Parent(optional_name)
		var/XML/Element/parent = _parent
		if (optional_name)
			while(parent && parent.Tag() != optional_name)
				parent = parent.Parent()
		return parent

	proc/_setParent(XML/Element/parent)
		_parent = parent

	Descendant(optional_name)
		// Equivalent to Twig's next_elt function.
		if (!optional_name)
			return FirstChild()

		for (var/XML/Element/child in Children())
			if (child.Tag() == optional_name) return child

			var/XML/Element/descendant = child.Descendant(optional_name)
			if (descendant) return descendant

	Descendants(optional_name)
		var/list/descendants = new()
		for (var/XML/Element/child in Children())
			descendants += child.DescendantsOrSelf(optional_name)
		return descendants

	DescendantsOrSelf(optional_name)
		var/list/descendants = new()
		if (!optional_name || Tag() == optional_name)
			descendants += src

		descendants += Descendants(optional_name)
		return descendants

	Attributes()
		if (_attributes_params)
			return params2list(_attributes_params)

		// No params, so return an empty list.
		var/list/placeholder = new()
		return placeholder

	setAttributes(list/attributes)
		_attributes_params = list2params(attributes)

	Attribute(name)
		var/list/attributes = Attributes()
		return attributes[name]

	setAttribute(name, value)
		var/list/attributes = Attributes()
		attributes[name] = value
		setAttributes(attributes)

	FirstChild(optional_name, element_only)
		var/list/children
		if (element_only)
			children = ChildElements()
		else
			children = Children()

		if (!children) return

		if (!optional_name) return children[1]

		// Look for the specified name.
		for (var/XML/Element/child in children)
			if (child.Tag() == optional_name)
				return child

	FirstChildElement(optional_name)
		return FirstChild(optional_name, element_only = 1)

	FirstChildText(optional_name)
		var/XML/Element/child = FirstChild(optional_name)
		if (child) return child.Text()

	Children(optional_name, elements_only)
		// If given a name, only return children named that.
		// If elements_only is specified, only return non-text elements.
		if (_children)
			if (optional_name)
				var/list/named = new()
				for (var/XML/Element/child in _children)
					if (child.Tag() == optional_name)
						named += child
				return named
			else if (elements_only)
				var/list/elements = new()
				for (var/XML/Element/child in _children)
					if (!dd_hasprefix_case(child.Tag(), "#"))
						elements += child
				return elements
		else
			// If no children, return an empty list.
			var/list/placeholder = new()
			return placeholder

		// We have children and no modifiers were passed in, so return children.
		return _children

	setChild(XML/Element/child)
		var/list/children = list(child)
		setChildren(children)

	setChildren(list/children)
		RemoveChildren()

		for (var/XML/Element/child in children)
			AddChild(child)

	AddChild(XML/Element/child, position = LAST_CHILD)
		// Remove from any previous parent.
		var/XML/Element/child_parent = child.Parent()
		if (child_parent)
			child_parent.RemoveChild(child)
		child._setParent(src)

		if (!_children) _children = new()

		switch(position)
			if (LAST_CHILD)		_children += child
			if (FIRST_CHILD)	_children.Insert(1, child)
		return

	RemoveChildren()
		if (_children)
			for (var/XML/Element/child in _children)
				RemoveChild(child)

	RemoveChild(XML/Element/child)
		if (_children && _children.Find(child))
			child._setParent(null)
			_children -= child

	ChildElements(optional_name)
		return Children(optional_name, elements_only = 1)

	AddSibling(XML/Element/sibling, position = AFTER)
		var/XML/Element/parent = Parent()
		if (!parent) CRASH("Can't add sibling to [Tag()] because there is no parent.")

		var/list/siblings = parent.Children()
		var/my_position = siblings.Find(src)
		if (!my_position) CRASH("[Tag()] couldn't find itself listed in parent's children.")

		var/XML/Element/sibling_parent = sibling.Parent()
		if (sibling_parent) sibling_parent.RemoveChild(sibling)
		sibling._setParent(parent)

		switch(position)
			if (BEFORE) siblings.Insert(my_position, sibling)
			if (AFTER)	siblings.Insert(my_position + 1, sibling)

	setText(text)
		// Translate <>&"' to their entity equivalents.
		// Must replace & first to keep from messing up entities.
		var/newtext = replacetext(text, "&", "&amp;")
		newtext = replacetext(newtext, "<", "&lt;")
		newtext = replacetext(newtext, ">", "&gt;")
//		newtext = replacetext(newtext, "\"", "&quot;")
//		newtext = replacetext(newtext, "\'", "&apos;")

		var/XML/Element/Special/PCDATA/pc = new(newtext)
		setChild(pc)

	Text(escaped)
		var/content = ""
		for (var/XML/Element/child in Children())
			content += child.Text()

		if (!escaped)
			content = replacetext(content, "&lt;", "<")
			content = replacetext(content, "&gt;", ">")
//			content = replacetext(content, "&quot;", "\"")
//			content = replacetext(content, "&apos;", "\'")
			content = replacetext(content, "&amp;", "&")
		return content

	setXML(text)
		var/XML/Parser/parse = new(text)
		var/list/children = parse.Parse_content()
		if (parse.Error()) CRASH(parse.Error())
		setChildren(children)

	XML(pretty_print = 0, indent_level = 0, enclosing_tags = 1)
		var/content = ""
		var/child_pretty_print = pretty_print
		var/child_indent = indent_level + 1

		if (pretty_print)
			// If any of my children are text nodes, don't use indentation for my children.
			for (var/XML/Element/child in Children())
				if (child.Tag() == "#PCDATA")
					child_pretty_print = 0

		for (var/XML/Element/child in Children())
			content += child.XML(pretty_print = child_pretty_print, indent_level = child_indent)

		if (!enclosing_tags)
			return content

		// Opening tag.
		var/newline = ""
		var/indent = ""
		if (pretty_print && indent_level)
			newline = "\n"
			for (var/count = 0, count < indent_level, count++)
				indent += "    "

		var/string = "[newline][indent]<[Tag()]"
		var/list/attributes = Attributes()
		for (var/attribute in attributes)
			var/value = attributes[attribute]

			// Delimeter can be " or ' depending on whether the value uses one of those characters.
			var/delimiter = "\""
			if (findtextEx(value, "\"")) delimiter = "'"

			string += " [attribute]=[delimiter][value][delimiter]"

		// Is this an empty element?
		if (!content)
			string += "/>"
			return string

		string += ">"

		// Content
		string += content

		// Closing tag
		if (pretty_print)
			if (indent_level == 0)
				// Handle the root level closing tag.
				newline = "\n"
			else if (!child_pretty_print)
				// If children not being indented, then don't newline/indent.
				newline = ""
				indent = ""
		string += "[newline][indent]</[Tag()]>"
		return string

	String(pretty_print)
		return XML(pretty_print = pretty_print, enclosing_tags = 0)

XML/Element/Special
	var
		_text

	Text()
		return _text

	setXML(text)
		_text = text

	XML(enclosing_tags, pretty_print, indent_level)
		return Text()

XML/Element/Special/PCDATA
	New(text)
		return ..("#PCDATA", text)

XML/Element/Special/CDATA
	New(text)
		return ..("#CDATA", text)

	XML(enclosing_tags, pretty_print, indent_level)
		return "<!\[CDATA\[[Text()]]]>"

XML/Element/Special/Comment
	New(text)
		return ..("#COMMENT", text)

	XML(enclosing_tags, pretty_print, indent_level)
		return "<!--[Text()]-->"

XML/Element/Special/P_I