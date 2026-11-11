# AGENTS.md — zorx

ไฟล์เริ่มต้นสำหรับ AI ทุกตัว (Codex, Cursor, Kiro, Gemini ฯลฯ) ที่เข้ามาทำงานใน repo นี้
กติกาจริงอยู่ในไฟล์ด้านล่าง ไฟล์นี้เป็นแค่ทางเข้า ห้ามเขียนกติกาซ้ำที่นี่

1. อ่าน `CLAUDE.md` — กฎสถาปัตยกรรม (logic/client/data), วิธีรันเทสต์, การตัดสินใจที่ต้องถาม Boss
2. อ่าน `AI_SYNC.md` — กติกาทำงานร่วมกันหลายฝั่ง, งานที่มีคนจองอยู่, ฟีเจอร์ปัจจุบัน
3. อ่าน `PROGRESS.md` — ทำถึงไหนแล้ว และเรื่องที่รอ Boss ตัดสิน
4. `GDD.md` — แนวคิดเกม (อ่านเมื่อต้องการรายละเอียด)
5. `assets_spec.md` — อ่านก่อนเพิ่ม/แก้ asset 3D: งบ texture, import, geometry และการวัดขนาด web

กฎที่ห้ามลืม:
- ทำงานใน branch ของตัวเอง รวมเข้า `main` ผ่าน Pull Request
- รันเทสต์ให้ผ่านทั้งหมดก่อน push: `godot --headless --path . --script res://tests/run_all.gd`
- **อัปเดต `AI_SYNC.md` ทุกครั้งก่อน push**

- ตัวละครใหม่ต้องตรง Studio ต้นแบบทุก option และพฤติกรรม: อ่านกฎ Character Studio parity ใน CLAUDE.md และ docs/tech/reference_studio_parity.md ก่อนแก้ ห้ามถือว่ามี rig/weights แล้วแปลว่าแสดงผลครบ
