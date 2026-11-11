ตรวจเร็ว ไม่ต้องใช้ key
./tools/backend/test_backend.sh both --health-only
ตรวจครบ: login, บัญชีเดิม, WS/WSS, CORS
./tools/backend/test_backend.sh both \
  --secrets build/k3s-remote/deployment.yaml
เปลี่ยน both เป็น internal หรือ external เพื่อแยกตรวจได้ หลัง restart pod รันคำสั่งเดิมเพื่อเช็ก persistence
- [คู่มือและวิธีติดตั้ง dependencies](/Users/user/godot-project/test01/zorx/docs/tech/backend_checks.md)
- รายงาน: build/backend-smoke/report.json