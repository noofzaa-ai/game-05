extends RefCounted
## Bounded native compression; header is uncompressed byte length, never an executable Object.
const MAX_RAW=524288
static func pack(raw:PackedByteArray)->PackedByteArray:
 if raw.is_empty() or raw.size()>MAX_RAW:return PackedByteArray()
 var result=PackedByteArray();result.resize(4);result.encode_u32(0,raw.size())
 result.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD));return result
static func unpack(bytes:PackedByteArray)->PackedByteArray:
 if bytes.size()<5 or bytes.size()>MAX_RAW:return PackedByteArray()
 var size:=bytes.decode_u32(0)
 if size<1 or size>MAX_RAW:return PackedByteArray()
 var raw:=bytes.slice(4).decompress(size,FileAccess.COMPRESSION_ZSTD)
 return raw if raw.size()==size else PackedByteArray()
