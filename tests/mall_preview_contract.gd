extends SceneTree
class Authority:
 extends RefCounted
 signal command_completed(id:int,result:Dictionary)
 signal ownership_changed
 var profile
 var state:Dictionary
 var calls:Array=[]
 var rng=RandomNumberGenerator.new()
 func command(value:Dictionary)->Dictionary:
  calls.append(value.duplicate(true))
  return preload("res://logic/commands.gd").apply(state,value,rng)
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 var authority=Authority.new();authority.profile=source.profile
 authority.state={"profile":source.profile,"rules":source.rules,"camp":source.camp,"location":"camp","cosmetics":preload("res://logic/cosmetic_options.gd").load_default()}
 var panel=preload("res://client/look_panel.gd").new();root.add_child(panel)
 panel.setup(source.profile,source.rules,source.sim.combat,authority);panel.show_tab("fashion")
 var appearance:Dictionary=source.profile.appearance.duplicate(true)
 panel._mall_pick("fashion","purple")
 assert(authority.calls.is_empty() and source.profile.diamonds==9999 and source.profile.appearance==appearance)
 assert(panel._preview_appearance().fashion=="purple")
 panel._buy_pressed()
 assert(is_instance_valid(panel._confirm) and authority.calls.is_empty())
 var overlay=panel._confirm.get_child(0)
 assert(overlay.theme!=null)
 var thai_font=overlay.theme.default_font
 for letter in "ยืนยันการซื้อยกเลิก":assert(thai_font.has_char(letter.unicode_at(0)))
 panel._cancel_purchase()
 assert(authority.calls.is_empty() and source.profile.diamonds==9999)
 panel._buy_pressed();panel._confirm_purchase()
 assert(authority.calls.size()==1 and source.profile.diamonds==9849)
 assert(source.profile.appearance==appearance)
 panel._mall_pick("fashion_hat","cat")
 assert(authority.calls.size()==1)
 panel._buy_pressed();panel._cancel_purchase()
 assert(source.profile.diamonds==9849)
 panel.queue_free();await process_frame
 assert(source.profile.appearance==appearance)
 print("MALL PREVIEW PASS: try-on/cancel/close never write; only confirm purchases once; original appearance preserved")
 quit()
