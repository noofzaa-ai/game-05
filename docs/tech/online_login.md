# M3-2 — บัญชีเครื่องและสถานะเชื่อมต่อ

## ขอบเขต

เชื่อมบัญชี Nakama ด้วย SDK ทางการ **v3.4.0** (archive SHA256 ใน `addons/com.heroiclabs.nakama/VENDOR.json`) เก็บ device ID แบบสุ่ม, access token และ refresh token ใน `user://online_account_v1.json` SDK ต้นฉบับไม่แก้; transport ของเกมอยู่ `client/online/http_adapter.gd` เพื่อจำกัด timeout10วินาที/คำขอ, ไม่ตาม redirect, ไม่ retry อัตโนมัติ และไม่ log credentials

บัญชีเชื่อมต่อแล้ว **ยังไม่ใช่การบันทึกเกมบนเซิร์ฟเวอร์**: LocalSession และตัวละคร/ไอเทมยังเหมือนก่อน M3-3/M3-4 จะเพิ่มชื่อและ server commands/storage ข้อความออนไลน์จึงแจ้งว่าไอเทมยังไม่บันทึกออนไลน์ และทุกโหมดออฟไลน์มีป้ายไม่บันทึกออนไลน์

## ตั้งค่าเครื่อง dev / ก่อน build Web

ค่าใน Git `data/online.json` ปิดการเชื่อมต่อไว้เมื่อยังไม่ได้กำหนด application key ของ deployment ไม่ใช้ defaultkey และไม่ส่งบัญชีไปเซิร์ฟเวอร์โดยไม่ได้ตั้งค่า

```sh
# ใช้ Python environment ที่ติดตั้ง PyYAML แล้ว (เช่น venv ของ backend smoke)
python3 pipeline/online_client_config.py \
  --secrets build/k3s-remote/deployment.yaml
./pipeline/build_web.sh --max-file-mb 0
```

ตัวสร้างคัดออกมาเฉพาะ public host/port/scheme และ **socket.server_key** ไป `data/online.local.json` ซึ่งอยู่ใน gitignore แต่รวมใน Web pack ได้ ต้องสร้างไฟล์นี้ในแต่ละเครื่อง build ก่อน export หากไม่มี private bundle บนเครื่อง build ให้ส่งเฉพาะ public config ที่สร้างแล้วมาไว้ path เดียวกัน

**ชื่อ key ของ Nakama:** `socket.server_key` คือ application/client key ที่ SDK ต้องส่งเพื่อเริ่ม authenticate จึงมองเห็นได้ใน client bundle ไม่ใช่ขอบเขตความเชื่อถือหรือสิทธิ์ admin ส่วน session/refresh encryption keys, runtime HTTP key, database password และ console credentials ต้องอยู่ฝั่งเซิร์ฟเวอร์เท่านั้น ตัวสร้างไม่คัดค่าเหล่านั้นออกมา

ค่าเริ่มต้นใช้ `https://zorxapi.daiyooo.com:443` ทั้ง PC และ Web ไม่มีการเดาหรือ fallback จาก public ไป internal อัตโนมัติ ตัวเลือก `--host`, `--port`, `--scheme` สำหรับ internal diagnostic ต้องใช้ cache คนละไฟล์เพราะ identity ผูก scope ของ endpoint

## พฤติกรรม

- เปิดหน้าเริ่มเกมแล้วเชื่อมอัตโนมัติ ไม่บล็อกปุ่ม Start
- ผู้เล่นกดเล่นออฟไลน์ได้ทันทีระหว่างรอ ผลตอบกลับเก่าจะไม่สลับกลับออนไลน์
- กดเชื่อมต่ออีกครั้งได้ถ้าไม่สำเร็จ ไม่มี retry loop เมื่อออฟไลน์
- device ID สุ่มด้วย Crypto แล้วบันทึกก่อนส่ง auth ไม่ใช้ hardware ID
- ครั้งแรกอนุญาต create; ครั้งถัดไปใช้ `create=false` เมื่อเคยลงทะเบียนแล้ว หากบัญชีถูกลบจะไม่สร้างแทนเงียบๆ
- คืน session จาก cache แล้วตรวจ `/v2/account` จริงก่อนแสดงออนไลน์ ไม่เชื่อ JWT ในเครื่องโดยลำพัง
- token ใกล้หมดอายุใช้ refresh; ถ้า401กลับไป login ด้วย device เดิม ส่วน network/5xxแสดงออฟไลน์
- ออนไลน์ตรวจบัญชี/ต่อ session ทุก30วินาที หากเครือข่ายหลุดจะเปลี่ยนสถานะเมื่อคำขอตรวจล้มเหลว เกมออฟไลน์เดินต่อได้
- cache เสียหรือ scope ไม่ตรงจะหยุดเป็นออฟไลน์ ไม่เขียนทับตัวตนเดิมอัตโนมัติ
- ไม่มี gameplay state, inventory หรือคำสั่งเกมถูกส่งขึ้น backend ในขั้นนี้

## ข้อจำกัดบัญชีเครื่อง

- Web เก็บ user:// ผ่าน IndexedDB; Native เก็บในพื้นที่ข้อมูลแอป จำกัดสิทธิ์ไฟล์เป็น0600บน Mac/Linux
- token/device ID เป็น credentials ไม่ใส่ log, screenshot หรือ commit การเก็บใน client ไม่ใช่ secure vault และไม่ป้องกันเจ้าของเครื่องอ่านได้
- อย่าล้าง site data/cache หรือลบไฟล์เพื่อแก้เน็ตโดยไม่เก็บ identity หากลบจะสูญทางเข้าบัญชีเครื่องเดิม
- Safari private mode/โควตา storage อาจไม่เก็บข้อมูลถาวร ต้องทดลองเครื่องจริง
- มือถือกับ PC จะเป็นคนละบัญชีจนเพิ่มการผูกบัญชี/login ข้ามเครื่อง จึงยังไม่ผ่านเกณฑ์ M3 ทั้งหมด

## ทดสอบ

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_all.gd
python3 -m unittest discover -s tests -p 'test_*.py'
```

`tests/test_online_login.gd` ใช้ fake client ไม่ยิง staging ระหว่าง regression tests ครอบคลุม cache, refresh, offline, late response, scope mismatch และ cache เสีย ส่วน live Godot/Web ตรวจ staging แยกจาก unit suite

อ้างอิง: [Godot SDK](https://heroiclabs.com/docs/nakama/client-libraries/godot/), [authentication](https://heroiclabs.com/docs/nakama/concepts/authentication/), [pinned SDK release](https://github.com/heroiclabs/nakama-godot/releases/tag/v3.4.0)

ทดสอบ SDK กับ staging จริง (สร้างบัญชี probe แยกหนึ่งบัญชีเมื่อรันครั้งแรก แล้วใช้ cache เดิมทุกครั้ง):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/online_live_probe.gd
```

ตรวจ HTTPS login/account, cache restore เป็นบัญชีเดิม, refresh token จริง และ WSS ผ่าน SDK ใช้ `-- --cache /PRIVATE/PATH/probe-cache.json` เพื่อเลือก cache แยก ห้ามใช้ไฟล์บัญชีผู้เล่นจริงกับ probe เพราะทดสอบแทน access token เป็น fixture ที่หมดอายุชั่วคราว Cache นี้เป็นข้อมูลลับ ห้าม commit และห้ามลบหากยังต้องการตรวจบัญชีเดิม

## ขอบเขตไฟล์ Web export

`build/`, `server/`, `pipeline/`, `docs/`, `tools/` และ `tests/` ต้องไม่อยู่ในแพ็กเกม แม้ Git จะ ignore แล้ว Godot all_resources ยังสามารถเก็บ JSON จาก build/ ได้ จึงมีทั้ง exclude_filter และตัวตรวจ PCK ในขั้น split ที่ปฏิเสธ path งานพัฒนา/ข้อมูลส่วนตัวก่อน publish build สำเร็จ มี regression test กันแคชทดสอบหลุดซ้ำ
