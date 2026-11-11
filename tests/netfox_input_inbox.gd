extends SceneTree
func _initialize()->void:
 var inbox=preload("res://logic/net/input_inbox.gd").new();inbox.clear(2)
 var frame=preload("res://logic/sim_input.gd").new();frame.move=Vector2.RIGHT;frame.light=true
 assert(inbox.receive(10,frame,2,100,5))
 assert(not inbox.receive(10,frame,2,101,5))
 var first:Dictionary=inbox.consume(110);assert(first.frame.light and first.frame.move==Vector2.RIGHT)
 assert(not inbox.consume(120).frame.light)
 # A late missing action older than the newest held control remains a one-shot action.
 var late=frame.duplicate_input();late.light=false;late.dodge=true
 assert(inbox.receive(9,late,2,130,4));assert(inbox.consume(140).frame.dodge)
 assert(not inbox.consume(150).frame.dodge)
 assert(inbox.consume(600).frame.move==Vector2.ZERO)
 assert(not inbox.receive(11,frame,1,610,5))
 var blob=preload("res://logic/net/compressed_blob.gd")
 var raw=var_to_bytes({"input":frame.encode(),"text":"x".repeat(2000)})
 assert(blob.unpack(blob.pack(raw))==raw)
 var bomb=PackedByteArray();bomb.resize(5);bomb.encode_u32(0,99999999)
 assert(blob.unpack(bomb).is_empty())
 print("NETFOX INBOX PASS: late actions once, held expiry, scene fence, dedupe, bounded compressed values")
 quit()
