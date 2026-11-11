"""Remove retired player wardrobe from the runtime register; keep authored sources and all weapons."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'art/items/item_manifest.json'
data=json.loads(p.read_text())
data['items']=[row for row in data['items'] if row.get('category') not in {'clothing','hair','faces'}]
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print('Runtime registry:',len(data['items']),'entries; legacy wearables removed')
