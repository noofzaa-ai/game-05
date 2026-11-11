extends Node
## Dedicated probe project only. Results appear in the page DOM for browser inspection.
func emit_line(line: String) -> void:
	print(line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.getElementById('probe-output').textContent += " + JSON.stringify(line + "\n") + ";", true)

func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var p=document.createElement('pre');p.id='probe-output';p.style='position:fixed;inset:0;overflow:auto;color:#ddd;background:#111;z-index:99999;padding:12px;margin:0;font:12px monospace';document.body.appendChild(p);",true)
	emit_line("GODOT_VERSION " + Engine.get_version_info()["string"])
	await get_tree().process_frame
	var suite = load("res://tests/test_determinism.gd")
	for boss in [false,true]:
		emit_line("RUNNING " + ("boss" if boss else "normal"))
		await get_tree().process_frame
		var hashes: Array = suite.trace(boss)
		for i in hashes.size(): emit_line("NETCODE_HASH %s %d %s" % ["boss" if boss else "normal",(i+1)*60,hashes[i]])
	for count in [2,4]:
		emit_line("RUNNING party%d" % count)
		await get_tree().process_frame
		var hashes: Array = suite.trace_party(count)
		for i in hashes.size(): emit_line("NETCODE_HASH party%d %d %s" % [count,(i+1)*60,hashes[i]])
	emit_line("PROBE_COMPLETE 80")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
var output=document.getElementById('probe-output');
fetch('native-reference.txt').then(function(response){if(!response.ok)throw new Error('No native reference');return response.text();}).then(function(text){
 function hashes(value){return value.split('\\n').filter(function(line){return line.startsWith('NETCODE_HASH ');});}
 var reference=hashes(text),actual=hashes(output.textContent);
 var matched=actual.filter(function(line,index){return reference[index]===line;}).length;
 output.textContent+='WEB_REFERENCE_MATCHES '+matched+'/'+actual.length+' (reference '+reference.length+')\\n';
}).catch(function(){output.textContent+='Native reference not provided; save this output for compare_native.py\\n';});
var button=document.createElement('button');button.textContent='Download probe results';
button.style='position:fixed;top:8px;right:12px;z-index:100000;padding:12px';
button.onclick=function(){var link=document.createElement('a');link.href=URL.createObjectURL(new Blob([output.textContent],{type:'text/plain'}));link.download='web-determinism.txt';link.click();setTimeout(function(){URL.revokeObjectURL(link.href);},1000);};
document.body.appendChild(button);
""",true)
