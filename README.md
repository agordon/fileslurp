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

    slurpy!( FIELDS, store_data, '\t' )("file.txt");
}

// Or shorter syntax:
slurpy! ( Tuple!(int,int,int), (x) => { writeln(x); }, '\t' )("file.txt");
```

## License
BSD 3-Clause

## Contact
A. Gordon

