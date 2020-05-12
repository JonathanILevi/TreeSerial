module treeserial;

import std.traits;
import std.bitmanip;

enum NoLength;

template serialize(Ts...) {
	ubyte[] serialize(T)(T data) if(isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
		return nativeToLittleEndian(data).dup;
	}
	////ubyte[T.sizeof] serialize(T)(T data) if(isIntegral!T || isSomeChar!T || isBoolean!T) {
	////	return nativeToLittleEndian(data).dup;
	////}
}
template deserialize(T, Ts...) {
	static if (isIntegral!T || isSomeChar!T || isBoolean!T || isFloatOrDouble!T) {
		////T deserialize(scope ubyte[T.sizeof] data) {
		////	return littleEndianToNative!T(data);
		////}
		T deserialize(ref ubyte[] data) {
			scope (success)
				data = data[T.sizeof..$];
			return littleEndianToNative!T(data[0..T.sizeof]);
		}
	}
}

/// Copied from phobas/std/bitmanip
private template isFloatOrDouble(T)
{
    enum isFloatOrDouble = isFloatingPoint!T &&
                           !is(Unqual!(FloatingPointTypeOf!T) == real);
}

 
