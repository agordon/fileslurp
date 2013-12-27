module fileslurp;

import std.typetuple;
import std.traits;
import std.typecons;
import std.string;
import std.array : empty;
import std.conv: text;
import std.exception : Exception, assertThrown;
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

	// No delimiter in string - treat it as a valid single field
	s = "hello world";
	t = consume_string_field(s,'\t');
	assert(s=="");
	assert(t=="hello world");
}

@safe pure S quotemeta(S)(const S s)
{
	string[dchar] meta = [ '\n' : "<LF>",
		'\t' : "<TAB>",
		'\r' : "<CR>",
		'\0' : "<NULL>" ];

	return translate(s,meta);
}

unittest
{
	string s="1\t2\t3\n";
	auto t = quotemeta(s);
	assert(t=="1<TAB>2<TAB>3<LF>");

	//String with null
	s="1\0002";
	t = quotemeta(s);
	assert(t=="1<NULL>2");

	//Empty string
	s="";
	t = quotemeta(s);
	assert(t=="");

	// Normal string
	s="1\\t2";
	t = quotemeta(s);
	assert(t=="1\\t2");
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

unittest
{
	assert(quotemeta('\t')=="<TAB>");
	assert(quotemeta('\r')=="<CR>");
	assert(quotemeta('\n')=="<LF>");
	assert(quotemeta('\00')=="<NULL>");
	assert(quotemeta('t')=="t");
}

@safe void parse_delimited_string(DATA)(const string input, const char delimiter, ref DATA arg)
{
	string remaining_input = input;

	foreach (i, T; DATA.Types)
	{
		//TODO: Handle other types (for now, only numeric or strings)
		static if (isNumeric!T) {
			try {
				// consume a numeric field
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
}

unittest
{
	Tuple!(int,string,int) a;
	parse_delimited_string("1 2 3",' ',a);
	assert(a[0]==1 && a[1]=="2" && a[2]==3);

	parse_delimited_string("1\t2\t3",'\t',a);
	assert(a[0]==1 && a[1]=="2" && a[2]==3);

	//Extra delimiter at the end of the line is not OK
	assertThrown!Exception(parse_delimited_string("1 2 3 ",' ',a));

	//Invalid number on first field (parse!int should fail)
	assertThrown!Exception(parse_delimited_string(".1 2 3",' ',a));

	//Extra characters in field 1 (After successfull parse!int)
	assertThrown!Exception(parse_delimited_string("1. 2 3",' ',a));

	//Line contains too many fields
	assertThrown!Exception(parse_delimited_string("1 2 3 4",' ',a));

	//Line is too short
	assertThrown!Exception(parse_delimited_string("1 2",' ',a));

	//non-space/tab delimiter is fine
	parse_delimited_string("1|2|3",'|',a);
	assert(a[0]==1 && a[1]=="2" && a[2]==3);
	parse_delimited_string("1|  2  |3",'|',a);
	assert(a[0]==1 && a[1]=="  2  " && a[2]==3);

	//Spaces are bad (and not ignored) if delimiter is not space (for numeric fields)
	assertThrown!Exception(parse_delimited_string("1 |2|3",'|',a));
	assertThrown!Exception(parse_delimited_string(" 1|2|3",'|',a));
	assertThrown!Exception(parse_delimited_string(" 1|2| 3",'|',a));
	assertThrown!Exception(parse_delimited_string("1|2|3 ",'|',a));

	//For string fields, empty values are not OK (different from formattedRead())
	assertThrown!Exception(parse_delimited_string("1||3",'|',a));

	//For string fields, last value can't be empty (different from formattedRead())
	Tuple!(int,string,string) b;
	assertThrown!Exception(parse_delimited_string("1|2|",'|',b));

	//One field is OK
	Tuple!(string) c;
	parse_delimited_string("foo",' ',c);
	assert(c[0]=="foo");

	//Fields that are OK for floating-point types should not work for integers (extra characters)
	Tuple!(real,int) d;
	parse_delimited_string("4.5 9",' ',d);
	assert(d[0]==4.5 && d[1]==9);
	Tuple!(int,real) e;
	assertThrown!Exception(parse_delimited_string("4.5 9",' ',e));

	//scientific notation - OK for floating-point types
	Tuple!(double,double) f;
	parse_delimited_string("-0.004e3 +4.3e10",' ',f);
	assert(f[0]==-0.004e3 && f[1]==43e9);

	//Scientific notation - fails for integars
	Tuple!(int,int) g;
	assertThrown!Exception(parse_delimited_string("-0.004e3 +4.3e10",' ',g));
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
