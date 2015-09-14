module sicas.png;

import std.traits : isNumeric;
import std.bitmanip : nativeToBigEndian;
import std.zlib : adler32, crc32, compress;
import std.file : write;

struct PNG
{
public:
	const(ubyte)[] SIGNATURE = [ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A ];
	
	struct Chunk
	{
		uint	size;	// Not exceeding (2^31)-1 bytes
		char[4]	type;	// a-z, A-Z (65-90, 97-122)
		char[]	data;	// Data of length defined in 'length'	
		uint	crc;	// Cyclic Redundancy Code
		
		this(char[4] type)
		{
			this.type = type;
			this.crc = crc32(0, type);
		}
		
		ref Chunk opBinary(string op, T)(const auto ref T rhs)
		if((isNumeric!T || is(T == char[])) && (op == "<<"))
		{
			static if(isNumeric!T)
			{
				assert(this.size + rhs.sizeof <= 0x7FFFFFFF);
				this.data ~= nativeToBigEndian(rhs);
				this.size += rhs.sizeof;
			}
			else
			{
				assert(this.size + rhs.length <= 0x7FFFFFFF);
				this.data ~= rhs;
				this.size += rhs.length;
			}
			
			this.crc = crc32(0, this.type ~ this.data);
			return this;
		}
		
		char[] arrayof() const pure nothrow @safe @property
		{
			return (cast(char[]) nativeToBigEndian(this.size) ~ this.type ~ this.data ~ cast(char[]) nativeToBigEndian(this.crc));
		}
		
		alias arrayof this;
	}
	
	this(in uint width, in uint height) nothrow @nogc @safe
	in { assert(width <= 0x80000000 && height <= 0x80000000); }
	body { width_ = width; height_ = height; }
	
	char[] filter(in char[] data) const @safe
	{
		char[] filtered;
		uint index;
		
		foreach(y; 0 .. height_)
		{
			filtered ~= char(0);	// No filtering
			
			foreach(x; 0 .. width_)
			{
				index = ((y * width_) + x) * 4;
				filtered ~= data[index .. (index + 4)];
			}
		}
		
		return filtered;
	}
	
	char[] data() const @property
	{
		return this.compressedData();
	}
	
	char[] compressedData(in int compression = 6) const
	in { assert(compression >= 0 && compression <= 9); }
	body
	{
		char[] data = cast(char[])(SIGNATURE);											// Add PNG signature
		data ~= Chunk("IHDR") << width_ << height_ << cast(char[]) [ 8, 6, 0, 0, 0 ];	// Add header chunk (width, height, depth, type, compression, filter, interlace)
		data ~= Chunk("IDAT") << cast(char[]) compress(filter(image), compression);		// Add data chunk (filtered and compressed image)
		data ~= Chunk("IEND");
		return data;
	}
	
	bool write(in string filename, in int compression = 6) const
	in { assert(compression >= 0 && compression <= 9); }
	body
	{
		// Write to filename
		try .write(filename, this.compressedData(compression));
		catch return false;
		return true;
	}
	
	char[]	image;
	
private:
	uint	width_;
	uint	height_;
}
