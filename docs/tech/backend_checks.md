# ตรวจ backend ทั้ง internal / external

รันจากราก repo บน Mac/Linux ที่เข้าถึงปลายทางได้ ไม่ต้องมี kubectl และไม่ต้อง SSH เข้า k3s

## เตรียมครั้งแรก

```sh
python3 -m venv build/backend-smoke/venv
build/backend-smoke/venv/bin/pip install -r tools/backend/requirements.txt
export PYTHON_BIN="$PWD/build/backend-smoke/venv/bin/python"
```

## ตรวจเส้นทางเร็ว ไม่ต้องใช้ key

```sh
./tools/backend/test_backend.sh both --health-only
./tools/backend/test_backend.sh internal --health-only
./tools/backend/test_backend.sh external --health-only
```

Internal ต้องต่อ Tailscale: `http://100.78.133.27:30350` → Nakama

External: `https://zorxapi.daiyooo.com` → Cloudflare Tunnel443 → Traefik80 → Nakama7350

ตรวจ health JSON, TLS certificate/hostname และ CORS จาก Origin `https://zorxplay.daiyooo.com`

## ตรวจครบ: login, account, WebSocket, CORS

เครื่อง dev ปัจจุบันมี private YAML และ smoke identity เดิมแล้ว ใช้คำสั่งนี้ได้เลย:

```sh
./tools/backend/test_backend.sh both --secrets build/k3s-remote/deployment.yaml
```

แยกขาได้โดยเปลี่ยน `both` เป็น `internal` หรือ `external` โปรแกรมตรวจ:

- health และ CORS preflight
- login ด้วย identity เดิม (`create=false`) และ account ID ต้องตรงที่บันทึกไว้
- login ซ้ำโดยไม่สร้าง account ใหม่
- token และ application key ผิดต้องถูกปฏิเสธ
- authenticated WS/WSS upgrade และ ping/pong
- WS token ผิดต้องถูกปฏิเสธ
- CORS บนผลตอบกลับ login/account จริง

เครื่องอื่นให้เก็บ **socket.server_key** ในไฟล์ส่วนตัว (ไม่ใช่ session encryption key หรือ database password):

```sh
chmod 600 /path/to/server-key.txt
./tools/backend/test_backend.sh both --key-file /path/to/server-key.txt --init
```

`--init` สร้าง smoke account หนึ่งบัญชีเมื่อยังไม่มี state เท่านั้น ครั้งถัดไปเอา `--init` ออก เก็บ `build/k3s-remote/smoke-state.json` ไว้และห้าม commit เพราะ device ID ใช้ login ได้ โปรแกรมไม่พิมพ์ key/token/device/account ID ลง log ส่วน YAML ที่ส่งให้ `--secrets` ต้องเป็นชุดส่วนตัวที่มี Secret จริง ไม่ใช่ resources-only YAML ใน Git

## ตรวจ persistence หลัง restart

1. รันครบให้ผ่านก่อน restart
2. ให้ผู้ดูแล restart Nakama และ Postgres บน k3s แล้วรอ Ready
3. รันคำสั่งเดิม **ไม่ใส่ `--init` และไม่ลบ state**
4. `same persisted account` ผ่าน แปลว่าบัญชีเดิมยังอยู่ ไม่ได้สร้างทดแทน

สคริปต์ไม่ restart pod หรือแก้ deployment เอง และการผ่านนี้ยังไม่ใช่การทดสอบ backup/restore หรือเล่น co-op/iPhone จริง

## รายงาน / วินิจฉัย

```sh
./tools/backend/test_backend.sh both --secrets build/k3s-remote/deployment.yaml --timeout 15 --report build/backend-smoke/investigation.json
./tools/backend/test_backend.sh external --health-only --external-url https://zorxapi.daiyooo.com
```

Exit `0` = ผ่าน, `1` = FAIL/SKIP, `2` = input/dependency ผิด รายงาน JSON ไม่มี response body หรือ credentials

- internal ล้ม แต่ external ผ่าน: ตรวจ Tailscale, NodePort30350 และ NetworkPolicy
- internal ผ่าน แต่ external ล้ม: ตรวจ DNS, Tunnel hostname/Host header, Traefik Ingress
- HTTP403: ตรวจ Cloudflare policy; tester ใช้ User-Agent `zorx-backend-smoke/1.0`
- HTTP404: ตรวจ Host header และ Ingress routing
- HTTP502/503: ตรวจ Service endpoints/pod readiness และ Tunnel origin
- TLS error: ตรวจ hostname/certificate/trust store ไม่ปิด certificate verification
- login ล้ม: ตรวจ server_key ตรงกับ Secret ที่ deploy และ DB พร้อม
- WS ล้มแต่ REST ผ่าน: ตรวจ `/ws` routing และ WebSocket upgrade ตลอดเส้นทาง
- CORS ล้ม: ตรวจ Allow-Origin และ Allow-Headers ต้องระบุ Authorization ชัดเจน (`*` อย่างเดียวไม่พอ)

ไม่มี Allow-Methods บน preflight ของ POST อย่างเดียวไม่ถือว่าผิด เพราะ POST เป็น safelisted method

## M3-3 name RPC checks (after names overlay deployment)

```sh
./tools/backend/test_backend.sh both --names --secrets build/k3s-remote/deployment.yaml
```

Uses the existing dedicated smoke identity. Claims one QA name only if that account has none; otherwise reuses its current name. Checks read/claim, invalid-name and forged-ID rejection. The base server must first receive the additional names runtime/validator overlay; see `server/names/README.md`. Race, API bypass and restart coverage runs separately with `python3 server/names/smoke_stack.py` against disposable local containers. This does not prove gameplay cloud save.

## M3-4 profile RPC checks (after updated backend deployment)

```sh
./tools/backend/test_backend.sh both --names --profiles --secrets build/k3s-remote/deployment.yaml
```

`--profiles` loads/creates the dedicated smoke account's server starter profile, then verifies snapshot injection/reward requests fail without changing its saved state. It does not import local items or perform a valid equipment/economy mutation. Run only after deploying both updated images; local integration/race/restart tests are in `server/names/smoke_stack.py`.
