module treeserial;

import std.traits;
import std.meta;
import std.bitmanip;

import std.typecons;

import std.algorithm;
import std.range;
import std.conv;

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

struct Include {
	bool value = true;
}
enum Exclude = Include(false);

alias DefaultAttributes = AliasSeq!(NoLength(false), LengthType!ushort);


template Serializer(Attributes...) {
	
	template Subserializer(MoreAttributes...) {
		alias Subserializer = Serializer!(Attributes, MoreAttributes);
	}
	alias Subdeserializer = Subserializer;
	
	template isAttribute(alias T, AddedDefaults...) {
		enum isAttribute = Filter!(isDesiredUDA!T, AliasSeq!(DefaultAttributes, AddedDefaults, Attributes)).length > 0;
	}
	template GetAttributeType(alias T, AddedDefaults...) {
		alias GetAttributeType = Filter!(isDesiredUDA!T, AliasSeq!(DefaultAttributes, AddedDefaults, Attributes))[$-1].Type;
	}
	template getAttributeValue(alias T, AddedDefaults...) {
		static if (is(Filter!(isDesiredUDA!T, AliasSeq!(DefaultAttributes, AddedDefaults, Attributes))[$-1]))// For if the struct is not created but referencing the type: instantiate it, and use the default.
			enum getAttributeValue = Filter!(isDesiredUDA!T, AliasSeq!(DefaultAttributes, AddedDefaults, Attributes))[$-1]().value;
		else
			enum getAttributeValue = Filter!(isDesiredUDA!T, AliasSeq!(DefaultAttributes, AddedDefaults, Attributes))[$-1].value;
	}
	template GetAttributes(alias T) {
		template Get(alias EA) {
			alias Get = EA.Attributes;
		}
		alias GetAttributes = staticMap!(Get, Filter!(isDesiredUDA!T, Attributes));
	}
	template FilterOut(alias T) {
		alias FilterOut = Filter!(templateNot!(isDesiredUDA!T), Attributes);
	}
	
	static if (isAttribute!CastType) {
		ubyte[] serialize(T)(T value) if (__traits(compiles, cast(GetAttributeType!CastType) rvalueOf!T) && serializable!(GetAttributeType!CastType)) {
			return Serializer!(FilterOut!CastType).serialize(cast(GetAttributeType!CastType) value);
		}
		T deserialize(T)(ref const(ubyte)[] value) if (__traits(compiles, cast(T) rvalueOf!(GetAttributeType!CastType)) && deserializable!(GetAttributeType!CastType)) {
			return cast(T) Serializer!(FilterOut!CastType).deserialize!(GetAttributeType!CastType)(value);
		}
	}
	else {
		ubyte[] serialize(T)(T value) if(isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
			return nativeToLittleEndian(value).dup;
		}
		ubyte[] serialize(T)(T value) if(isDynamicArray!T || isStaticArray!T) {
			alias Serializer_ = Serializer!(FilterOut!ElementAttributes, GetAttributes!ElementAttributes);
			static if (isSomeChar!(ForeachType!T)) {
				import std.utf;
				static if (isStaticArray!T || getAttributeValue!NoLength)
					return value[].byCodeUnit.map!(Serializer!(FilterOut!NoLength).serialize).joiner.array;
				else
					return serialize(cast(GetAttributeType!LengthType) value.length) ~ value.byCodeUnit.map!(Serializer_.serialize).joiner.array;
			}
			else {
				static if (isStaticArray!T || getAttributeValue!NoLength)
					return value[].map!(Serializer!(FilterOut!NoLength).serialize).joiner.array;
				else
					return serialize(cast(GetAttributeType!LengthType) value.length) ~ value.map!(Serializer_.serialize).joiner.array;
			}
		}
		ubyte[] serialize(T)(T value) if(isTuple!T) {
			import std.stdio;
			ubyte[] bytes;
			static foreach (i; 0..value.length)
				bytes ~= serialize(value[i]);
			return bytes;
		}
		ubyte[] serialize(T)(T value) if((is(T == class) || is(T == struct)) && !isTuple!T) {
			static if(__traits(hasMember, T, "serialize")) {
				return value.serialize;
			}
			else {
				ubyte[] bytes;
				foreach (memName; __traits(derivedMembers, T)) {{
					static if (memName != "this") {
						alias mem = __traits(getMember, T, memName);
						alias Mem = typeof(mem);
						static if (Subserializer!(__traits(getAttributes, mem)).getAttributeValue!(Include, Include(
							!isCallable!mem
							&& !__traits(compiles, { mixin("auto test=T." ~ memName ~ ";"); })	// static members
						))) {
							bytes ~= Serializer!(Serializer!(FilterOut!ElementAttributes).FilterOut!Include, GetAttributes!ElementAttributes).serialize(mixin("value."~memName));
						}
					}
				}}
				return bytes;
			}
		}
		
		T deserialize(T)(ref const(ubyte)[] buffer) if (isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
			scope (success)
				buffer = buffer[T.sizeof..$];
			return littleEndianToNative!T(buffer[0..T.sizeof]);
		}
		T deserialize(T)(ref const(ubyte)[] buffer) if (isDynamicArray!T || isStaticArray!T) {
			alias Serializer_ = Serializer!(FilterOut!ElementAttributes, GetAttributes!ElementAttributes);
			static if (isStaticArray!T)
				return repeat(null, T.length).map!(_=>Serializer_.deserialize!(ForeachType!T)(buffer)).array.to!T;
			else static if (getAttributeValue!NoLength)
				return repeat(null).map!(_=>Serializer!(FilterOut!NoLength).deserialize!(ForeachType!T)(buffer)).until!((lazy _)=>buffer.length==0).array;
			else
				return repeat(null, deserialize!(GetAttributeType!LengthType)(buffer)).map!(_=>Serializer_.deserialize!(ForeachType!T)(buffer)).array;
		}
		T deserialize(T)(ref const(ubyte)[] buffer) if(is(T == class) || is(T == struct)) {
			static if(__traits(hasMember, T, "deserialize")) {
				return buffer.serialize;
			}
			else {
				T value;
				static if (is(T == class))
					value = new T();
				foreach (memName; __traits(derivedMembers, T)) {{
					static if (memName != "this") {
						alias mem = __traits(getMember, T, memName);
						alias Mem = typeof(mem);
						static if(isCallable!Mem)
							alias MemT = ReturnType!Mem;
						else
							alias MemT = Mem;
						static if (Subserializer!(__traits(getAttributes, mem)).getAttributeValue!(Include, Include(
							!isCallable!mem
							&& !__traits(compiles, { mixin("auto test=T." ~ memName ~ ";"); })	// static members
						))) {
							mixin(q{value.}~memName) = Serializer!(Serializer!(FilterOut!ElementAttributes).FilterOut!Include, GetAttributes!ElementAttributes).deserialize!MemT(buffer);
						}
					}
				}}
				return value;
			}
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
	// Static
	{
		int[2] data = [1,2];
		const(ubyte)[] bytes = serialize(data);
		assert(bytes == [1,0,0,0, 2,0,0,0] || bytes == [0,0,0,1, 0,0,0,2]);
		assert(bytes.deserialize!(typeof(data)) == data);
	}
}
@("class")
unittest {
	{
		static class C {
			ubyte a = 1;
			ubyte b = 2;
			@Exclude ubyte c = 3;
			@property ubyte d() { return 4; }
			@Include @property ubyte e() { return 5; } @Include @property void e(ubyte) {}
			ubyte f() { return 6; }
			@Include ubyte g() { return 7; } @Include void g(ubyte) {}
			static ubyte h = 8;
			@Include static ubyte i = 9;
			static ubyte j() { return 10; }
			@Include static ubyte k() { return 11; } @Include static void k(ubyte) {}
		}
		C data = new C;
		const(ubyte)[] bytes = serialize(data);
		assert(bytes == [1,2,5,7,9,11]);
		
		const(ubyte)[] nb = [11,22,55,77,99,110];
		C nd = nb.deserialize!(typeof(data));
		assert(nd.a == 11);
		assert(nd.b == 22);
		assert(nd.c == 3);
		assert(nd.d == 4);
		assert(nd.e == 5);
		assert(nd.f == 6);
		assert(nd.g == 7);
		assert(nd.h == 8);
		assert(nd.i == 99);
		assert(nd.j == 10);
		assert(nd.k == 11);
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
 
