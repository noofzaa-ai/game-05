# Equipment Upgrade — initial tuning

วันที่: 2026-10-19 · ค่าตุ๊กตาที่ Boss อนุมัติให้ใช้เริ่มต้น

## กติกา

- แยกจาก Refine: Upgrade ไม่เพิ่มออฟหลักหรือเปลี่ยน Tier
- อุปกรณ์หนึ่งชิ้นใช้ได้รวม 5 ครั้ง ครั้งละ 100 Gold สำเร็จแน่นอน
- มีออฟรองไม่ครบ 4 แถว: สุ่มออฟใหม่ 1 แถวตามช่วงของ Tier เดิม ไม่ซ้ำออฟหลัก/ออฟรองที่มี และใช้โควตา 1 ครั้ง
- มีครบ 4 แถว: สุ่มแต่ละแถวโอกาสเท่ากัน แล้วเพิ่มค่าคงที่ตามตาราง; สุ่มโดนแถวเดิมซ้ำได้
- ทุก Upgrade เพิ่มตัวนับ 1 เท่านั้น ไม่มี reset/re-roll/เสียของ
- โบนัสบวกสะสม เก็บจำนวนจริงบนไอเทม; เปลี่ยน config ไม่แก้โบนัสที่ได้รับไปแล้ว
- ออฟใหม่ไม่มีโบนัส Upgrade เพิ่มในครั้งเดียวกัน
- แสดง `STA REGEN +3.2 (+0.1)`; ค่าหลังวงเล็บคือโบนัส Upgrade สะสม
- ค่า % ในตารางคือจุดเปอร์เซ็นต์ที่บวกเพิ่ม ไม่ใช่คูณค่าปัจจุบัน

## เพิ่มต่อครั้งที่สุ่มโดนแถว

| Stat | Normal | Rare | Epic | Legendary |
|---|---:|---:|---:|---:|
| HP | 10 | 15 | 20 | 25 |
| ATK | 1 | 1.5 | 2 | 2.5 |
| DEF | 0.8 | 1.2 | 1.6 | 2 |
| ATKSPD | 0.2 | 0.3 | 0.4 | 0.5 |
| MOVESPD | 0.1 | 0.15 | 0.2 | 0.25 |
| CRIRATE | 0.2 | 0.3 | 0.4 | 0.5 |
| CRIDMG | 0.5 | 0.75 | 1 | 1.25 |
| EFFECT_ACC | 0.3 | 0.45 | 0.6 | 0.75 |
| EFFECT_RES | 0.3 | 0.45 | 0.6 | 0.75 |
| HPREGEN | 0.05 | 0.075 | 0.1 | 0.125 |
| STAREGEN | 0.025 | 0.05 | 0.075 | 0.1 |
| ULTREGEN | 0.005 | 0.01 | 0.015 | 0.02 |
| STAMINA | 0.5 | 0.75 | 1 | 1.25 |

## Config และข้อจำกัด

- ค่าเริ่มต้น: `data/items/equipment_tuning.json` (Refine + Upgrade)
- Server override: environment `ZORX_EQUIPMENT_CONFIG` ชี้ไฟล์ที่ mount จาก ConfigMap
- Staging: ConfigMap `zorx-equipment-tuning` ใน namespace `zorx-staging`, key `equipment_tuning.json`
- แก้ ConfigMap แล้ว restart Deployment `headless` เพื่อให้ทั้ง profiles/rooms โหลดตรงกัน ไม่ต้อง build/push image
- Client โหลด config จาก profile RPC ของ server เมื่อเข้าแคมป์/refresh profile ไม่เชื่อค่าราคา/ผลสุ่มจาก client
- restart headless กระทบห้องที่กำลังเล่น ควรทำช่วงไม่มีผู้เล่นในห้อง
- Refine ยังคง 1.3% ต่อขั้น สูงสุด +12 ราคา 100 Gold
- ราคา Merchant ยังอยู่ใน `data/items/shop.json` ไม่ได้ย้ายมา ConfigMap ชุดนี้
- ตารางเป็นค่าตั้งต้น ยังไม่ได้ยืนยันบาลานซ์หลังเล่นจริง

## วิธีแก้ค่าบนเครื่อง k3s

ไฟล์ถาวร: `/home/wiyazard/deployment/game-test/zorx-staging/equipment-tuning.yaml`
แก้ `data.equipment_tuning.json` แล้วรันจาก directory นั้น:

```sh
kubectl apply -n zorx-staging -f equipment-tuning.yaml
kubectl rollout restart deployment/headless -n zorx-staging
kubectl rollout status deployment/headless -n zorx-staging
kubectl logs deployment/headless -c profiles -n zorx-staging --tail=20
kubectl logs deployment/headless -c rooms -n zorx-staging --tail=20
```

ตรวจว่าไม่มี `invalid game configuration` และมี `name validator: ready` ทั้งสอง container.
Config ผิดรูปแบบจะไม่เปิดรับคำสั่ง และไม่ fallback เงียบไปใช้ราคาเก่า.

หากแก้ค่าตั้งต้นใน repo ให้สร้าง ConfigMap ใหม่ด้วย:

```sh
python3 server/k3s/equipment_tuning.py --output server/k3s/equipment-tuning.yaml
```

การแก้ราคา/อัตรา Refine มีผลกับสูตรออฟหลักของของเดิมด้วย ส่วนตารางโบนัส Upgrade มีผลกับการกดครั้งถัดไปเท่านั้น.
หลัง restart ให้ refresh เกม/โหลดบัญชีใหม่เพื่อรับ config ล่าสุด; อย่าใช้หน้าเมนูที่เปิดค้างก่อนเปลี่ยนราคาเป็นราคายืนยัน.
