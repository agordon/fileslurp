# FileSlurp
**A *D* library to load a delimited text file into memory.**

## Usage

```D
import fileslurp;

void main()
{
    // Our file has three columns: int, string, int
    alias Tuple!(int, string, int) FIELDS;

    // Store the data in a hash:
    //   The string (2nd column) will be the key,
    //   The third field will be the value.
    string[int] data;

    // This delegate function will be called for every loaded line.
    void store_data(FIELDS x)
    {
        data[ x[1] ] = x[2];
    }

    // The three template parameters are:
    //  1. The Tuple structure, representing the expected fields in the file
    //  2. The delegate function, called for each parsed line
    //  3. The delimiter character
    // The one runtime parameter:
    //  1. The file name to load.
    slurpy!( FIELDS, store_data, '\t' )("file.txt");
}

// Or shorter syntax, load entire file into an array.
// NOTE: this is a naive,inefficient version, see below.
alias Tuple!(int,int,int) FIELDS;
FIELDS[] data;
slurpy! ( Tuple!(int,int,int), (x) => { data ~= x }, '\t' )("file.txt");

// slurpy_array does the same as above, in a slightly faster manner.
auto data = slurpy_array!('\t', int,int,int)("file.txt");
```

## License
BSD 3-Clause

## Contact
A. Gordon

