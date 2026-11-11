from pathlib import Path
import tempfile,subprocess,shutil
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='zorx-perf-images-') as tmp:
 ctx=Path(tmp)
 server=ctx/'server';server.mkdir();shutil.copytree(root/'server/perf',server/'perf');data=ctx/'data';data.mkdir();shutil.copytree(root/'data/perf',data/'perf')
 (ctx/'Dockerfile').write_text('FROM wiyazard:30500/zorx-room-worker:bow-20261026-1\nCOPY server/perf /project/server/perf\nCOPY data/perf /project/data/perf\nENTRYPOINT ["/usr/local/bin/godot","--headless","--path","/project","--script","res://server/perf/worker.gd"]\n')
 subprocess.run(['docker','build','--platform','linux/amd64','-t','wiyazard:30500/zorx-perf-worker:20261027-3',str(ctx)],check=True)
with tempfile.TemporaryDirectory(prefix='zorx-perf-web-') as tmp:
 ctx=Path(tmp);shutil.copytree(root/'build/web',ctx/'html')
 page=ctx/'html/play.html';page.write_text(page.read_text().replace('async function authenticate() {','async function authenticate() { authenticated=true; return true; /* isolated synthetic lab: no account */',1))
 shutil.copy2(root/'pipeline/Dockerfile.web',ctx/'Dockerfile')
 conf=(root/'pipeline/nginx-web.conf').read_text().replace('    location = /healthz {','    location ^~ /perf-lab/ {\n        alias /usr/share/nginx/html/;\n        index play.html;\n        add_header Cache-Control "no-cache";\n    }\n\n    location = /healthz {')
 (ctx/'nginx-web.conf').write_text(conf)
 subprocess.run(['docker','build','--platform','linux/amd64','-t','wiyazard:30500/zorx-perf-web:20261027-3',str(ctx)],check=True)
