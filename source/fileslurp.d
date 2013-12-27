module fileslurp;

import std.string;
import std.array;
import std.exception;
import std.stdio;

@safe pure void consume_delimiter(S, D)(ref S input_str, const D delimiter)
{
    if (input_str.empty || input_str[0] != delimiter)
	    throw new Exception("missing delimiter");

    input_str = input_str[1..$];
}

unittest
{
	string s = "\t2\t3";
	consume_delimiter(s,'\t');
	assert(s=="2\t3");
	//Trying to remove a delimiter when non is available is a throwable offense
	assertThrown!Exception(consume_delimiter(s,'\t'));
	//Trying to remove a delimiter from an empty string is a throwable offense
	s = "";
	assertThrown!Exception(consume_delimiter(s,' '));
}

@safe S consume_string_field(S,D)(ref S input_str, const D delimiter)
{
	size_t j = input_str.length;
	foreach (i, dchar c; input_str)
	{
		if ( c == delimiter ) {
			j = i;
			break;
		}
	}
	scope(exit) input_str = input_str[j .. $];
	return input_str[0 .. j];
}

unittest
{
	// Consume the first field
	string s = "hello\tworld";
	string t = consume_string_field(s,'\t');
	assert(s=="\tworld");
	assert(t=="hello");

	// Consume the next (and last) field
	consume_delimiter(s,'\t');
	t = consume_string_field(s,'\t');
	assert(s=="");
	assert(t=="world");

	// No string before delimiter - return an empty string
	s = "\tfoo\tbar";
	t = consume_string_field(s,'\t');
	assert(s=="\tfoo\tbar");
	assert(t=="");

	// Empty string - is a valid single (empty) field
	s = "";
	t = consume_string_field(s,'\t');
	assert(s=="");
	assert(t=="");
}

@safe pure S quotemeta(S)(const S s)
{
	string[dchar] meta = [ '\n' : "<LF>",
		'\t' : "<TAB>",
		'\r' : "<CR>",
		'\0' : "<NULL>" ];

	return translate(s,meta);
}

@safe pure string quotemeta(const char c)
{
	string[dchar] meta = [ '\n' : "<LF>",
		'\t' : "<TAB>",
		'\r' : "<CR>",
		'\0' : "<NULL>" ];
	if (c in meta)
		return meta[c];

	//ridiculous - there's got to be a better way
	char[] tmp;
	tmp = tmp ~ c;
	return tmp;
}

@safe size_t parse_delimited_string(DATA)(const string input, const char delimiter, ref DATA arg)
{
	//const char delimiter = '\t';
	string remaining_input = input;

	foreach (i, T; DATA.Types)
	{
		static if (isNumeric!T) {
			try {
				// consume a numeric/boolean field
				arg[i] = std.conv.parse!T(remaining_input);
			} catch ( std.conv.ConvException e ) {
				throw new Exception(text("failed to parse numeric value in field ", i+1,
							" (text is '",quotemeta(remaining_input),"')"));
			}
		} else 	{
			// consume a string field
			arg[i] = consume_string_field(remaining_input,delimiter);
			if (arg[i].empty)
				throw new Exception(text("empty text at field ", i+1,
							" (remaining text is '",quotemeta(remaining_input),"')"));
		}

		static if (i<DATA.length-1) {
			//Not the last field - require more input
			if (remaining_input.empty)
				throw new Exception(text("input terminated too soon (expecting ",
							DATA.length," fields, got ", i+1, ")"));

			//Following the converted value of this field,
			//require a delimiter (to prevent extra characters, even whitespace)
			if (remaining_input[0] != delimiter)
				throw new Exception(text("extra characters in field ",i+1,
							" (starting at '",quotemeta(remaining_input),"')"));
			consume_delimiter(remaining_input,delimiter);
		} else {
			// Last field: check for extra input
			if (!remaining_input.empty)
				throw new Exception(text("extra characters in last field ",i+1,
							" (starting at '",quotemeta(remaining_input),"')"));
		}
		
	}
	return 0;
}


template slurpy(MEMBERS, alias STORE_FUNCTION, char delimiter='\t')
{
	static assert (isTuple!MEMBERS,"slurpy: 1st template parameter must be a Tuple with the expected columns in the file"); 

	void slurpy(const string filename)
	{
		auto f = File(filename);
		scope(exit) f.close();
		auto lines=0;

		alias unaryFun!STORE_FUNCTION _Fun;
		MEMBERS data;

		foreach (origline; f.byLineFast())
		{
			++lines;
			string line = origline.idup;
			try {
				parse_delimited_string(line, delimiter, data);
				_Fun(data);
			} catch ( Exception e ) {
				throw new FileException(filename,text("invalid input at line ", lines,
							": expected ", data.tupleof.length,
							" fields ",typeof(data.tupleof).stringof,
							" delimiter by '",quotemeta(delimiter),
							"' got '", origline,
							"' error details: ", e.msg ));
			}
		}
	}
}

Select!(Types.length == 1, Types[0][], Tuple!(Types)[])
slurpy_array(Types...)(string filename)
{
    typeof(return) result;
    auto app = appender!(typeof(return))();
    alias ElementType!(typeof(return)) MEMBERS;

    slurpy! ( MEMBERS, delegate (x) { app.put(x); } ) (filename);

    return app.data;
}
