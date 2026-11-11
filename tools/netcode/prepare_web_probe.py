#!/usr/bin/env python3
"""Create an isolated Web probe project under ignored build/. Does not edit the game project."""
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[2]


def main():
    destination=ROOT/'build/netcode-web-project'
    marker=destination/'.netcode-probe-owned'
    if destination.exists() and not marker.exists(): raise ValueError('Refusing to overwrite an unrelated project directory')
    destination.mkdir(parents=True,exist_ok=True)
    marker.touch()
    for folder in ('logic','data','art'):
        shutil.copytree(ROOT/folder,destination/folder,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','_archive'))
    tests=destination/'tests'
    tests.mkdir(exist_ok=True)
    for name in ('test_determinism.gd','online_fixture.gd','journey_bot.gd','web_determinism_probe.gd'):
        shutil.copy2(ROOT/'tests'/name,tests/name)
    imported=ROOT/'.godot/imported'
    if imported.exists(): shutil.copytree(imported,destination/'.godot/imported',dirs_exist_ok=True)
    (destination/'project.godot').write_text('''config_version=5
[application]
config/name="zorx determinism probe"
run/main_scene="res://probe.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
''')
    (destination/'probe.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/web_determinism_probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
''')
    (destination/'export_presets.cfg').write_text('''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="data/*.json, art/animations/*.json, art/items/item_manifest.json, art/skills/*.json"
exclude_filter="art/items/_archive/*, */preview/*"
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=false
html/canvas_resize_policy=2
progressive_web_app/enabled=false
''')
    (ROOT/'build/netcode-web').mkdir(exist_ok=True)
    print('Prepared isolated project:',destination)


if __name__=='__main__':main()
