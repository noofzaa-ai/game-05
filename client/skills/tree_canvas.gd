extends Control
## Presentation of the authoritative Lab tree; node positions/links remain source data.
signal selected(id: String)
const Ink := preload("res://client/ink_ui.gd")
var tree: ZorxPassiveTreeData
var allocated: Array = []
var focused := ""
var zoom := 2.0
var pan := Vector2.ZERO
var _dragging := false
var _touch := -1
var _last := Vector2.ZERO
var _moved := false
var _min := Vector2.ZERO
var _extent := Vector2.ONE
var _weapon_icons := {}

func setup(value: ZorxPassiveTreeData, owned: Array) -> void:
 tree=value;allocated=owned
 var rules=preload("res://logic/item_rules_loader.gd").load_default()
 for id in rules.catalog.items:
  var entry: Dictionary=rules.catalog.items[id]
  if entry.get("slot","")!="weapon":continue
  var family: String=entry.get("weapon_type","")
  var start:=preload("res://logic/skill_build.gd").start_for(family)
  if not _weapon_icons.has("start_"+start):
   var icon=preload("res://client/item_assets.gd").icon_for_id(id,rules.catalog)
   if icon!=null:_weapon_icons["start_"+start]=icon
 _min=Vector2(INF,INF)
 var upper:=Vector2(-INF,-INF)
 for node in tree.nodes:
  _min=_min.min(node.position);upper=upper.max(node.position)
 _extent=(upper-_min).max(Vector2.ONE)
 mouse_filter=Control.MOUSE_FILTER_STOP
 resized.connect(queue_redraw)
 queue_redraw()

func _scale() -> float:
 # Keep nodes readable on phones; pan across the tree rather than shrinking into a dot.
 return maxf(0.65,minf(maxf(1,size.x-70)/_extent.x,maxf(1,size.y-70)/_extent.y))*zoom

func _point(node: ZorxTreeNodeData) -> Vector2:
 return size*.5+(node.position-_min-_extent*.5)*_scale()+pan

func _color(node: ZorxTreeNodeData) -> Color:
 return {"f":Color("ee7756"),"i":Color("7bc9ef"),"s":Color("efd071"),"b":Color("b586d3")}.get(node.arm,Ink.GOLD)

func magnify(amount: float) -> void:
 zoom=clampf(zoom*amount,0.05,4);queue_redraw()

func reset_view() -> void:
 var fit:=minf(maxf(1,size.x-70)/_extent.x,maxf(1,size.y-70)/_extent.y)
 zoom=clampf(fit/maxf(0.65,fit),0.05,1);pan=Vector2.ZERO;queue_redraw()

func _draw() -> void:
 if tree==null:return
 draw_style_box(Ink.flat(Ink.INK,Ink.GOLD,1,8,0),Rect2(Vector2.ZERO,size))
 for node in tree.nodes:
  for link in node.links:
   var other: ZorxTreeNodeData=tree.by_id[link]
   draw_line(_point(node),_point(other),Color(Ink.GOLD,.75 if node.id in allocated and link in allocated else .18),2,true)
 for node in tree.nodes:
  var point:=_point(node)
  var radius:=_radius(node)
  var owned:=node.id in allocated
  draw_circle(point,radius+2,Ink.GOLD if owned or focused==node.id else Color("35474e"))
  draw_circle(point,radius, _color(node).darkened(.35) if owned else Ink.INK)
  if node.is_start:
   draw_arc(point,radius+5,0,TAU,48,Color(Ink.GOLD,.85),2,true)
   var side:=radius*1.8
   var rect:=Rect2(point-Vector2.ONE*side*.5,Vector2.ONE*side)
   if _weapon_icons.has(node.id):draw_texture_rect(_weapon_icons[node.id],rect,false)
   else:
    # Staff has no production catalog item yet: use a clear staff silhouette.
    draw_line(point+Vector2(-side*.25,side*.35),point+Vector2(side*.2,-side*.25),Ink.GOLD,3,true)
    draw_circle(point+Vector2(side*.23,-side*.3),side*.16,Color("ab91e6"))
   continue
  var glyph: String="★" if node.is_start else ("◆" if node.tier!="minor" else "+")
  var font:=ThemeDB.fallback_font
  draw_string(font,point+Vector2(-font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x*.5,5),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,14,_color(node))

func _pick(at: Vector2) -> void:
 var nearest: ZorxTreeNodeData
 var distance:=INF
 for node in tree.nodes:
  var d:=at.distance_to(_point(node))
  if d<=maxf(26.0,_radius(node)+7.0) and d<distance:nearest=node;distance=d
 if nearest!=null:
  focused=nearest.id;selected.emit(nearest.id);queue_redraw()

func _radius(node: ZorxTreeNodeData) -> float:
 return clampf(58*_scale(),30,46) if node.is_start else clampf(29*_scale(),4,20)

func _gui_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:magnify(1.2)
  elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:magnify(1/1.2)
  elif event.button_index==MOUSE_BUTTON_LEFT:
   _dragging=event.pressed
   if event.pressed:_last=event.position;_moved=false
   elif not _moved:_pick(event.position)
  accept_event()
 elif event is InputEventMouseMotion and _dragging:
  if event.position.distance_to(_last)>8:_moved=true
  pan+=event.relative;queue_redraw();accept_event()
 elif event is InputEventScreenTouch:
  if event.pressed and _touch<0:_touch=event.index;_last=event.position;_moved=false
  elif not event.pressed and event.index==_touch:
   if not _moved:_pick(event.position)
   _touch=-1
  accept_event()
 elif event is InputEventScreenDrag and event.index==_touch:
  if event.position.distance_to(_last)>8:_moved=true
  pan+=event.relative;queue_redraw();accept_event()
