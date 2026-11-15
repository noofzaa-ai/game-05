extends RefCounted
## Reliable room event stream (server/rooms/netfox/event_delivery.gd): one event too big for a frame must not stall
## every event after it. Staging 2026-11-16: a won fight's end events and all pongs stopped, the room closed 60 s
## later and the player saw "connection lost" instead of the victory summary.
const Delivery := preload("res://server/rooms/netfox/event_delivery.gd")
const Wire := preload("res://logic/net_wire.gd")


func run(ctx) -> void:
	var huge := {}
	for i in 9000:  # more nodes than one frame's encode budget
		huge["k%d" % i] = i
	var events := [
		{"sequence": 1, "tick": 1, "event": {"type": "hit", "player": 1}},
		{"sequence": 2, "tick": 2, "event": {"type": "card_xp", "player": 1, "detail": huge}},
		{"sequence": 3, "tick": 3, "event": {"type": "journey_complete", "player": 1}},
	]
	ctx.check("arrange: the big event alone cannot be packed", Wire.packet(Wire.EVENTS, 1, {"events": [events[1]]}).is_empty())
	var row := {"event_ack": 0}
	var seen: Array = []
	var send := func(p: PackedByteArray) -> bool:
		for e in Wire.decode(Wire.parse(p).body).value.events:
			seen.append(int(e.sequence))
		return true
	Delivery.flush(row, events, 1, send, func() -> bool: return true)
	ctx.check("events after an oversized one still arrive %s" % [seen], seen.has(3) and seen.has(1))
	ctx.check("the stream moves past the oversized event", int(row.get("sent_event_sequence", 0)) == 3)
