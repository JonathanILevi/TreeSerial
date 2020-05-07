module treeserial;

import std.traits;
import std.bitmanip;

enum NoLength;

template serialize(Ts...) {
	ubyte[] serialize(T)(T data) if(isIntegral!T || isSomeChar!T || isBoolean!T) {
		return nativeToLittleEndian(data).dup;
	}
	////ubyte[T.sizeof] serialize(T)(T data) if(isIntegral!T || isSomeChar!T || isBoolean!T) {
	////	return nativeToLittleEndian(data).dup;
	////}
	
	ubyte[] serialize(T)(T data) if(isFloatingPoint!T) {
		return (cast(ubyte*) cast(void*) (&data))[0..T.sizeof].dup;
	}
	////ubyte[T.sizeof] serialize(T)(T data) if(isFloatingPoint!T) {
	////	return (cast(ubyte*) cast(void*) (&data))[0..T.sizeof].dup;
	////}
}
template deserialize(T, Ts...) {
	static if (isIntegral!T || isSomeChar!T || isBoolean!T) {
		////T deserialize(scope ubyte[T.sizeof] data) {
		////	return littleEndianToNative!T(data);
		////}
		T deserialize(ref ubyte[] data) {
			scope (success)
				data = data[T.sizeof..$];
			return littleEndianToNative!T(data[0..T.sizeof]);
		}
	}
	static if (isFloatingPoint!T) {
		////T deserialize(scope ubyte[T.sizeof] data) {
		////	return *(cast(T*) cast(void*) data.ptr);
		////}
		T deserialize(ref ubyte[] data) {
			scope (success)
				data = data[T.sizeof..$];
			return *(cast(T*) cast(void*) data.ptr);
		}
	}
}



 
