extends RefCounted
const RAW_CAP=262144
const ZIP_CAP=65536
static func encode(report:Dictionary)->Dictionary:
 var copy=report.duplicate(true)
 var raw=JSON.stringify(copy).to_utf8_buffer()
 # Explicitly remove oldest details, never silently cut JSON or lose reference/context.
 var removed:=0
 for _attempt in range(24):
  if raw.size()<=RAW_CAP:break
  var changed:=false
  for side in ["client","worker"]:
   var data:Dictionary=copy.get(side,{})
   if not data.get("incidents",[]).is_empty():data.incidents.pop_front();removed+=1;changed=true;break
   var live:Dictionary=data.get("live",{})
   if not live.get("events",[]).is_empty():
    var count:=maxi(1,live.events.size()/2);live.events=live.events.slice(count);removed+=count;changed=true;break
   if live.get("samples",[]).size()>8:
    var count:=maxi(1,live.samples.size()/2);live.samples=live.samples.slice(count);removed+=count;changed=true;break
  if not changed:return {"ok":false,"error":"diagnostic_size"}
  copy["removed_oldest_details"]=removed;raw=JSON.stringify(copy).to_utf8_buffer()
 if raw.size()>RAW_CAP:return {"ok":false,"error":"diagnostic_size"}
 var zip=raw.compress(FileAccess.COMPRESSION_GZIP)
 if zip.size()>ZIP_CAP:return {"ok":false,"error":"diagnostic_size"}
 var data=Marshalls.raw_to_base64(zip)
 return {"ok":true,"encoding":"gzip-base64","raw_bytes":raw.size(),"data":data,"digest":data.sha256_text()}
static func decode(encoded:Dictionary)->Dictionary:
 var text=str(encoded.get("data",""))
 if encoded.get("encoding")!="gzip-base64" or text.length()>87384 or text.sha256_text()!=encoded.get("digest"):return {}
 var zip=Marshalls.base64_to_raw(text)
 if zip.size()>ZIP_CAP:return {}
 var bytes=zip.decompress_dynamic(RAW_CAP,FileAccess.COMPRESSION_GZIP)
 if bytes.size()!=int(encoded.get("raw_bytes",-1)):return {}
 var result=JSON.parse_string(bytes.get_string_from_utf8())
 return result if result is Dictionary else {}
