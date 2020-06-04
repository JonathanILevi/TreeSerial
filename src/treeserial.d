module treeserial;

import std.traits;
import std.meta;
import std.bitmanip;

import std.algorithm;
import std.range;

struct NoLength {
	bool value = true;
}
struct LengthType(T) {
	alias Type = T;
}

struct CastType(T) {
	alias Type = T;
}

struct ElementAttributes(Attribs...) {
	alias Attributes = Attribs;
}

alias DefaultAttributes = AliasSeq!(NoLength(false), LengthType!ushort);


template Serializer(Attributes_...) {
	alias Attributes = AliasSeq!(DefaultAttributes, Attributes_);
	
	template Subserializer(MoreAttributes_...) {
		alias Subserializer = Serializer!(Attributes_, MoreAttributes_);
	}
	alias Subdeserializer = Subserializer;
	
	template isAttribute(alias T) {
		enum isAttribute = Filter!(isDesiredUDA!T, Attributes).length > 0;
	}
	template GetAttributeType(alias T) {
		alias GetAttributeType = Filter!(isDesiredUDA!T, Attributes)[$-1].Type;
	}
	template getAttributeValue(alias T) {
		static if (is(Filter!(isDesiredUDA!T, Attributes)[$-1]))// For if the struct is not created but referencing the type: instantiate it, and use the default.
			enum getAttributeValue = Filter!(isDesiredUDA!T, Attributes)[$-1]().value;
		else
			enum getAttributeValue = Filter!(isDesiredUDA!T, Attributes)[$-1].value;
	}
	template GetAttributes(alias T) {
		template Get(alias EA) {
			alias Get = EA.Attributes;
		}
		alias GetAttributes = staticMap!(Get, Filter!(isDesiredUDA!T, Attributes));
	}
	template FilterOut_(alias T) {
		alias FilterOut_ = Filter!(templateNot!(isDesiredUDA!T), Attributes_);
	}
	
	static if (isAttribute!CastType) {
		ubyte[] serialize(T)(T data) if (__traits(compiles, cast(GetAttributeType!CastType) rvalueOf!T) && serializable!(GetAttributeType!CastType)) {
			return Serializer!(FilterOut_!CastType).serialize(cast(GetAttributeType!CastType) data);
		}
		T deserialize(T)(ref const(ubyte)[] data) if (__traits(compiles, cast(T) rvalueOf!(GetAttributeType!CastType)) && deserializable!(GetAttributeType!CastType)) {
			return cast(T) Serializer!(FilterOut_!CastType).deserialize!(GetAttributeType!CastType)(data);
		}
	}
	else {
		ubyte[] serialize(T)(T data) if(isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
			return nativeToLittleEndian(data).dup;
		}
		ubyte[] serialize(T)(T data) if(isDynamicArray!T) {
			alias Serializer_ = Serializer!(FilterOut_!ElementAttributes, GetAttributes!ElementAttributes);
			static if (getAttributeValue!NoLength)
				return data.map!(Serializer_.serialize).joiner.array;
			else
				return serialize(cast(GetAttributeType!LengthType) data.length) ~ data.map!(Serializer_.serialize).joiner.array;
		}
		
		T deserialize(T)(ref const(ubyte)[] data) if (isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
			scope (success)
				data = data[T.sizeof..$];
			return littleEndianToNative!T(data[0..T.sizeof]);
		}
		T deserialize(T)(ref const(ubyte)[] data) if (isDynamicArray!T) {
			alias Serializer_ = Serializer!(FilterOut_!ElementAttributes, GetAttributes!ElementAttributes);
			static if (getAttributeValue!NoLength)
				return repeat(null).map!(_=>Serializer_.deserialize!(ForeachType!T)(data)).until!((lazy _)=>data.length==0).array;
			else
				return repeat(null, deserialize!(GetAttributeType!LengthType)(data)).map!(_=>Serializer_.deserialize!(ForeachType!T)(data)).array;
		}
	}
}
alias Deserializer = Serializer;
template serialize(Attributes...) {
	alias serialize = Serializer!Attributes.serialize;
}
template deserialize(T, Attributes...) {
	alias deserialize = Deserializer!Attributes.deserialize!T;
}

template serializable(T) {
	enum serializable = __traits(compiles, rvalueOf!T.serialize);
}
template serializable(alias v) {
	enum serializable = __traits(compiles, v.serialize);
}
template deserializable(T) {
	enum deserializable = __traits(compiles, deserialize!T(lvalueOf!(const(ubyte)[])));
}

/// Copied from phobas/std/bitmanip
private template isFloatOrDouble(T)
{
    enum isFloatOrDouble = isFloatingPoint!T &&
                           !is(Unqual!(FloatingPointTypeOf!T) == real);
}


@("number")
unittest {
	{
		int data = 5;
		const(ubyte)[] bytes = serialize(data);
		assert(bytes == [5,0,0,0] || bytes == [0,0,0,5]);
		assert(bytes.deserialize!(typeof(data)) == data);
	}
	{
		ushort data = 5;
		const(ubyte)[] bytes = serialize(data);
		assert(bytes == [5,0] || bytes == [0,5]);
		assert(bytes.deserialize!(typeof(data)) == data);
	}
}
@("cast type")
unittest {
	{
		int data = 5;
		alias Serializer_ = Serializer!(CastType!byte);
		const(ubyte)[] bytes = Serializer_.serialize(data);
		assert(bytes == [5]);
		assert(Serializer_.deserialize!(typeof(data))(bytes) == data);
	}
}
@("array")
unittest {
	{
		int[] data = [1,2];
		const(ubyte)[] bytes = serialize(data);
		assert(bytes == [2,0, 1,0,0,0, 2,0,0,0] || bytes == [0,2, 0,0,0,1, 0,0,0,2]);
		assert(bytes.deserialize!(typeof(data)) == data);
	}
	// LengthType
	{
		int[] data = [1,2];
		alias Serializer_ = Serializer!(LengthType!uint);
		const(ubyte)[] bytes = Serializer_.serialize(data);
		assert(bytes == [2,0,0,0, 1,0,0,0, 2,0,0,0] || bytes == [0,0,0,2, 0,0,0,1, 0,0,0,2]);
		assert(Serializer_.deserialize!(typeof(data))(bytes) == data);
	}
	// NoLength
	{
		int[] data = [1,2];
		alias Serializer_ = Serializer!(NoLength);
		const(ubyte)[] bytes = Serializer_.serialize(data);
		assert(bytes == [1,0,0,0, 2,0,0,0] || bytes == [0,0,0,1, 0,0,0,2]);
		assert(Serializer_.deserialize!(typeof(data))(bytes) == data);
	}
	// ElementAttributes
	{
		int[] data = [1,2];
		alias Serializer_ = Serializer!(ElementAttributes!(CastType!ubyte));
		const(ubyte)[] bytes = Serializer_.serialize(data);
		assert(bytes == [2,0, 1,2] || bytes == [0,2, 1,2]);
		assert(Serializer_.deserialize!(typeof(data))(bytes) == data);
	}
	// Nested & ElementAttributes
	{
		int[][] data = [[1,2],[3,4]];
		alias Serializer_ = Serializer!(LengthType!ubyte, ElementAttributes!(ElementAttributes!(CastType!ubyte)));
		const(ubyte)[] bytes = Serializer_.serialize(data);
		assert(bytes == [2, 2,1,2, 2,3,4]);
		assert(Serializer_.deserialize!(typeof(data))(bytes) == data);
	}
}

/// Copied from std.traits
private template isDesiredUDA(alias attribute)
{
    template isDesiredUDA(alias toCheck)
    {
        static if (is(typeof(attribute)) && !__traits(isTemplate, attribute))
        {
            static if (__traits(compiles, toCheck == attribute))
                enum isDesiredUDA = toCheck == attribute;
            else
                enum isDesiredUDA = false;
        }
        else static if (is(typeof(toCheck)))
        {
            static if (__traits(isTemplate, attribute))
                enum isDesiredUDA =  isInstanceOf!(attribute, typeof(toCheck));
            else
                enum isDesiredUDA = is(typeof(toCheck) == attribute);
        }
        else static if (__traits(isTemplate, attribute))
            enum isDesiredUDA = isInstanceOf!(attribute, toCheck);
        else
            enum isDesiredUDA = is(toCheck == attribute);
    }
}
 
