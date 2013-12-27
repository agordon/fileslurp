/**
Generic Loader for delimited text files.

Copyright: Copyright 2013 the authors.

License: BSD 3-Clause

Authors: $(WEB https://github.com/agordon/ , A. Gordon), JM
*/
module fileslurp;

import std.typetuple;
import std.traits;
import std.typecons;
import std.functional;
import std.string;
import std.array ;
import std.conv: text;
import std.exception;
import std.stdio;
import std.file;
import std.range;

private {

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

} // private


/**
Parses string $(D input), delimited by character $(D delimiter), into a tuple of variables $(arg).

Returns:
On success, the function returns nothing (void), and all the members of the tuple are populated.

Throws:
$(XREF std.exception.Exception) on failure to correctly parse the string.   

Example:
----
string s = "Hello World 42";
Tuple!(string,string,int) t;
parse_delimited_string(s,' ',t);
assert(t[0]=="Hello");
assert(t[1]=="World");
assert(t[2]==42);
----

Notes:
$(OL
	$(LI Parsing is much stricter (and less tolerant) than $(XREF std.format.formattedRead))
	$(LI White-space is never automatically skipped)
	$(LI A space delimiter consume only space character (ASCII 20), not TAB (ASCII 9))
	$(LI Multiple consecutive delimiters are not consumed as one delimiter (e.g. "1\t\t\t2" is considerd a string with four fields - it has three delimiters. It will throw an exception because empty fields are not allowed).)
	$(LI All fields must exist (i.e. if the tuple $(D arg) has 3 members, the $(D input) string must contain two delimiters and three valid values))
	$(LI For a string field, empty values are not acceptable, will throw an exception)
	$(LI Extra characters at the end of a field or the line will throw an exception)
)

*/
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


/**
Loads a delimited text file, line-by-line, parses the line into fields, and calls a delegate/function for each line.

Returns:
On success, the function returns nothing (void), the call back function have been called for every line.

Throws:
$(XREF std.exception.Exception) on failure to correctly parse a line.
$(XREF std.file.FileException) on I/O failures.

Example:
----
// Load a text file with three numeric columns,
// Store the tuple in an array
// (NOTE: this is a naive, inefficient way to populate an array, see NOTES)
alias Tuple!(int,int,int) T;
T[] t;
slurpy!( T,           // The number and types of the (expected) fields in the file
	 delegate(x) { t ~= x; }, // for each line read, call this function. X will be of type T.
	 '\t'         // The delimiter (default = TAB)
       )("file.txt"); // The file name to read.
----

Example:
----
// Load a text file with three numeric columns,
// Use the second column as a KEY and the third column as the VALUE.
alias Tuple!(int,int,int) T;
int[int] data;
slurpy!( T,              // The number and types of the (expected) fields in the file
	 delegate(x) {   // for each line read, call this function. X will be of type T.
	     data[x[1]] = x[2] ;
	 },	
	 '\t'             // The delimiter (default = TAB)
       )("file.txt");    // The file name to read.
----

Notes:
$(OL
	$(LI See $(LREF parse_delimited_string) for details about parsing the delimited lines of the fiile)
	$(LO
)

*/
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

unittest
{
	import std.file ;
	auto deleteme = testFilename();
	write(deleteme,"1 2 3\n4 5 6\n");
	scope(exit) { assert(exists(deleteme)); remove(deleteme); }

	//Load a text file, with three fields, delimiter with spaces.
	alias Tuple!(int,int,int) T;
	T[] t;
	slurpy!( T,         // The number and types of the (expected) fields in the file
		 delegate(x) { t ~= x; }, // for each line read, call this function. X will be of type T.
		 ' '        // The delimiter (default = TAB)
	       )(deleteme); // The file name to read.
	assert(t.length==2);
	assert(t[0] == tuple(1,2,3));
	assert(t[1] == tuple(4,5,6));

	//Any kind of invalid data should throw an exception
	//NOTE: the delegate function does nothing, because we don't care about the data
	//      in this test.
	//NOTE: see more test cases for failed parsing in the unittest of 'parse_delimited_string'.
	auto deleteme2 = testFilename() ~ ".2";
	write(deleteme2,"1 Foo 3\n4 5 6\n"); // conversion will fail in the first line
	scope(exit) { assert(exists(deleteme2)); remove(deleteme2); }
	assertThrown!Exception( slurpy!( T, (x) => {}, ' ')(deleteme2)) ;
}


/**
Loads a delimited text file, line-by-line, parses the line into fields, returns an array of fields.

Returns:
On success, returns an array of tuples, based on template parameters.

Throws:
$(XREF std.exception.Exception) on failure to correctly parse a line.
$(XREF std.file.FileException) on I/O failures.

Example:
----
// Load a text file, tab-delimited, with three numeric columns.

auto data = slurpy_array!('\t', int,int,int)("file.txt");

// data[0] will be of type Tuple!(int,int,int)
----
*/
Select!(Types.length == 1, Types[0][], Tuple!(Types)[])
slurpy_array(char delimiter, Types...)(string filename)
{
    typeof(return) result;
    auto app = appender!(typeof(return))();
    alias ElementType!(typeof(return)) MEMBERS;

    slurpy! ( MEMBERS, delegate (x) { app.put(x); }, delimiter ) (filename);

    return app.data;
}

unittest
{
	import std.file ;
	auto deleteme = testFilename() ~ ".3";
	write(deleteme,"1 2 3\n4 5 6\n");
	scope(exit) { assert(exists(deleteme)); remove(deleteme); }

	//Load a text file, with three fields, delimiter with spaces.
	auto t = slurpy_array!( ' ', // delimiter
			        int, int, int // expected fields in the text file
			      )(deleteme);
	assert(t.length==2);
	assert(t[0] == tuple(1,2,3));
	assert(t[1] == tuple(4,5,6));
}

version(unittest) string testFilename(string file = __FILE__, size_t line = __LINE__)
{
	import std.path;
	import std.process;
	return text("deleteme-.", getpid(), ".", baseName(file), ".", line);
}

/*
On Thursday, 16 May 2013 at 10:35:12 UTC, Dicebot wrote:
> Want to bring into discussion people that are not on Google+.
> Samuel recently has posted there some simple experiments with
> bioinformatics and bad performance of Phobos-based snippet has
> surprised me.
>
> I did explore issue a bit and reported results in a blog post
> (snippets are really small and simple) :
> http://dicebot.blogspot.com/2013/05/short-performance-tuning-story.html
>
> One open question remains though - can D/Phobos do better here?
> Can some changes be done to Phobos functions in question to
> improve performance or creating bioinformatics-specialized
> library is only practical solution?

I bet the problem is in readln. Currently, File.byLine() and
readln() are extremely slow, because they call fgetc() one char
at a time.

I made an "byLineFast" implementation some time ago that is 10x
faster than std.stdio.byLine. It reads lines through rawRead, and
using buffers instead of char by char.

I don't have the time to make it phobos-ready (unicode, etc.).
But I'll paste it here for any one to use (it works perfectly).

--jm
*/


import std.stdio;
import std.string: indexOf;
import core.stdc.string: memmove;

/**
   Reads by line in an efficient way (10 times faster than File.byLine
   from std.stdio).
   This is accomplished by reading entire buffers (fgetc() is not used),
   and allocating as little as possible.

   The char \n is considered as separator, removing the previous \r
   if it exists.

   The \n is never returned. The \r is not returned if it was
   part of a \r\n (but it is returned if it was by itself).

   The returned string is always a substring of a temporary
   buffer, that must not be stored. If necessary, you must
   use str[] or .dup or .idup to copy to another string.

   Example:

         File f = File("file.txt");
         foreach (string line; f.byLineFast) {
             ...process line...
             //Make a copy:
             string copy = line[];
         }

   The file isn't closed when done iterating, unless it was
   the only reference to the file (same as std.stdio.byLine).
   (example: ByLineFast(File("file.txt"))).
*/
struct byLineFast {
     File file;
     char[] line;
     bool first_call = true;
     char[] buffer;
     char[] strBuffer;

     this(File f, int bufferSize=4096) {
         assert(bufferSize > 0);
         file = f;
         buffer.length = bufferSize;
     }

      @property bool empty() const {
         //Its important to check "line !is null" instead of
         //"line.length != 0", otherwise, no empty lines can
         //be returned, the iteration would be closed.
         if (line.ptr !is null) {
             return false;
         }
         if (!file.isOpen) {
             //Clean the buffer to avoid pointer false positives:
            (cast(char[])buffer)[] = 0;
             return true;
         }

         //First read. Determine if it's empty and put the char back.
         auto mutableFP = (cast(File*) &file).getFP();
         auto c = fgetc(mutableFP);
         if (c == -1) {
             //Clean the buffer to avoid pointer false positives:
            (cast(char[])buffer)[] = 0;
             return true;
         }
         if (ungetc(c, mutableFP) != c) {
             assert(false, "Bug in cstdlib implementation");
         }
         return false;
     }

      @property char[] front() {
         if (first_call) {
             popFront();
             first_call = false;
         }
         return line;
     }

     void popFront() {
         if (strBuffer.length == 0) {
             strBuffer = file.rawRead(buffer);
             if (strBuffer.length == 0) {
                 file.detach();
                 line = null;
                 return;
             }
         }

         ulong pos = strBuffer.indexOf('\n');
         if (pos != -1) {
             if (pos != 0 && strBuffer[pos-1] == '\r') {
                 line = strBuffer[0 .. (pos-1)];
             } else {
                 line = strBuffer[0 .. pos];
             }
             //Pop the line, skipping the terminator:
             strBuffer = strBuffer[(pos+1) .. $];
         } else {
             //More needs to be read here. Copy the tail of the buffer
             //to the beginning, and try to read with the empty part of
             //the buffer.
             //If no buffer was left, extend the size of the buffer before
             //reading. If the file has ended, then the line is the entire
             //buffer.

             if (strBuffer.ptr != buffer.ptr) {
                 //Must use memmove because there might be overlap
                 memmove(buffer.ptr, strBuffer.ptr, strBuffer.length * char.sizeof);
             }
             ulong spaceBegin = strBuffer.length;
             if (strBuffer.length == buffer.length) {
                 //Must extend the buffer to keep reading.
                 assumeSafeAppend(buffer);
                 buffer.length = buffer.length * 2;
             }
             char[] readPart = file.rawRead(buffer[spaceBegin .. $]);
             if (readPart.length == 0) {
                 //End of the file. Return whats in the buffer.
                 //The next popFront() will try to read again, and then
                 //mark empty condition.
                 if (spaceBegin != 0 && buffer[spaceBegin-1] == '\r') {
                     line = buffer[0 .. spaceBegin-1];
                 } else {
                     line = buffer[0 .. spaceBegin];
                 }
                 strBuffer = null;
                 return;
             }
             strBuffer = buffer[0 .. spaceBegin + readPart.length];
             //Now that we have new data in strBuffer, we can go on.
             //If a line isn't found, the buffer will be extended again to read more.
             popFront();
         }
     }
}
