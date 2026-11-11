extends RefCounted
const FeedbackPanel :=  preload("res://client/feedback_panel.gd")
func run(ctx) -> void:
	for viewport in [Vector2(854, 393), Vector2(360, 780), Vector2(854, 220)]:
		var host := Control.new()
		host.size = viewport
		host.theme = preload("res://client/ink_ui.gd").make_theme(preload("res://client/ink_ui.gd").FONT_SECTION)
		ctx.root.add_child(host)
		var panel := FeedbackPanel.new()
		host.add_child(panel)
		await ctx.process_frame
		await ctx.process_frame
		await ctx.process_frame
		ctx.check("feedback composer fits camp UI %s" % viewport, panel._box.size.x <= viewport.x and panel._box.size.y <= viewport.y and panel._box.position.x >= 0 and panel._box.position.y >= 0)
		ctx.check("feedback empty message disabled", panel._send.disabled)
		panel._text.text = "แจ้งปัญหาการทดสอบ"
		panel._changed()
		ctx.check("feedback valid message enables submit", not panel._send.disabled)
		panel._text.text = "x".repeat(2001)
		panel._changed()
		ctx.check("feedback overlong message disabled", panel._send.disabled)
		panel.queue_free(); host.queue_free()
		await ctx.process_frame
