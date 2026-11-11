extends RefCounted
const SimInput := preload("res://logic/sim_input.gd")
func run(ctx) -> void:
	var complete := true
	for bits in 256:
		var input := SimInput.new()
		for i in SimInput.BUTTONS.size():
			input.set(SimInput.BUTTONS[i], bool(bits & (1 << i)))
		input.move = Vector2(-1, 1)
		input.aim = Vector2(.375, -.625)
		var encoded := input.encode()
		var decoded = SimInput.decode(encoded)
		complete = complete and encoded.size() == 5 and decoded.encode() == encoded
		complete = complete and decoded.move == input.move and decoded.aim.distance_to(input.aim) < .006
	ctx.check("M1-5 all 256 button combinations and axis signs round-trip in five bytes", complete)
	var axes := true
	for n in range(-127, 128):
		var input := SimInput.new()
		input.move = Vector2(float(n) / 127.0, -float(n) / 127.0)
		axes = axes and SimInput.decode(input.encode()).move == input.move
	ctx.check("M1-5 every signed axis boundary survives", axes)
	ctx.check("M1-5 malformed length and reserved -128 rejected", SimInput.decode(PackedByteArray()) == null and SimInput.decode(PackedByteArray([0, 128, 0, 0, 0])) == null)
	var bad := SimInput.new()
	bad.move = Vector2(INF, NAN)
	bad.aim = Vector2(4, -4)
	var safe = SimInput.decode(bad.encode())
	ctx.check("M1-5 nonfinite input neutralized and oversized axes clamped", safe.move == Vector2.ZERO and safe.aim == Vector2(1, -1))

	var toward := SimInput.new()
	toward.aim = Vector2(10, 1)
	var direction = SimInput.decode(toward.encode()).aim
	ctx.check("M1-5 long world-space aim preserves heading instead of clamping diagonally", absf(direction.angle_to(toward.aim)) < .005)
