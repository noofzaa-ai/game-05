extends RefCounted
const TEXT := {
	"skill_build_required": "จัด Build และใส่อาวุธให้ตรงจุดเริ่มทรีที่แคมป์ก่อนออกเดินทาง",
	"reskill_required": "อาวุธคนละสายกับทรี กรุณารีสกิลที่เมนู Skill ก่อน",
	"weapon_required": "ต้องใส่อาวุธไว้ เปลี่ยนเป็นอาวุธชิ้นอื่นแทนการถอด",
	"not_sellable": "ของชิ้นนี้ยังขายไม่ได้", "price_changed": "ราคาขายเปลี่ยนแล้ว กรุณาเลือกของอีกครั้ง", "gold_limit": "Gold ถึงขีดจำกัดแล้ว",
	"storage_full": "คลังเต็มแล้ว ถอนของออกก่อนฝากเพิ่ม", "backpack_full": "กระเป๋าเต็มแล้ว ฝากของก่อนถอนเพิ่ม",
	"cannot_afford": "Gold หรือวัตถุดิบไม่พอ", "stash_full": "คลังเต็ม กรุณาจัดพื้นที่ก่อน", "invalid_product": "ไม่พบสินค้าในร้าน",
	"revision_conflict": "ข้อมูลไอเทมเปลี่ยนแล้ว โหลดข้อมูลล่าสุดให้แล้ว กรุณาเลือกไอเทมอีกครั้ง",
	"item_not_owned": "ไม่พบไอเทมชิ้นนี้ในคลังบัญชี กรุณาเลือกใหม่", "item_not_in_container": "ไอเทมถูกย้ายแล้ว กรุณาเลือกจากคลังล่าสุด",
	"bag_full": "เป้เต็ม ต้องเคลียร์ช่องก่อนถอดอุปกรณ์", "not_available_here": "เปลี่ยนอุปกรณ์ได้ที่แคมป์หรือจุดพักเท่านั้น",
	"profile_required": "ยังโหลดคลังบัญชีไม่ครบ กรุณากลับเข้าเกมอีกครั้ง", "invalid_command": "ส่งคำสั่งไอเทมไม่สำเร็จ กรุณาโหลดเกมรุ่นล่าสุด",
	"google_login_required": "กรุณาเข้าสู่ระบบ Google ใหม่จากเว็บหลัก",
	"not_online": "กรุณาเชื่อมต่อบัญชีก่อน", "unavailable": "เซิร์ฟเวอร์ไม่พร้อมหรือปิดปรับปรุง กรุณาลองใหม่",
	"maintenance": "เซิร์ฟเวอร์กำลังปิดปรับปรุง กรุณาลองภายหลัง", "not_configured": "เซิร์ฟเวอร์รุ่นนี้ยังไม่เปิดระบบปาร์ตี้",
	"room_full": "ห้องเต็มแล้ว", "room_expired": "ห้องนี้ปิดแล้ว หรือคำเชิญหมดอายุ", "not_invited": "รหัสเชิญไม่ถูกต้อง",
	"in_match": "มีห้องค้างอยู่ กดกลับห้องเดิม หรือรอให้ห้องเดิมปิด", "connection_changed": "การเชื่อมต่อเปลี่ยน กรุณาลองใหม่",
	"name_taken": "ชื่อนี้มีผู้ใช้แล้ว", "too_short": "ชื่อต้องมีอย่างน้อย 2 ตัวอักษร", "too_long": "ชื่อยาวได้ไม่เกิน 16 ตัวอักษร",
	"bad_characters": "ชื่อใช้ตัวอักษร ตัวเลข ช่องว่าง _ และ - ได้", "player_not_found": "ไม่พบชื่อตัวละครนี้",
	"cannot_add_self": "เพิ่มตัวเองเป็นเพื่อนไม่ได้", "request_expired": "คำขอนี้หมดอายุแล้ว", "not_friends": "ต้องรับเป็นเพื่อนกันก่อน",
	"leader_only": "หัวหน้าปาร์ตี้เป็นผู้เลือกเส้นทางและออกเดินทาง", "party_not_ready": "รอทุกคนเชื่อมต่อและกดพร้อมก่อน",
	"room_not_ready": "กำลังรอเพื่อนเข้าห้องให้ครบ กรุณาลองอีกครั้ง", "already_started": "ปาร์ตี้ออกเดินทางแล้ว",
	"rate_limited": "ทำรายการเร็วเกินไป รอสักครู่แล้วลองใหม่", "conflict": "ข้อมูลกำลังเปลี่ยน กรุณาลองใหม่",
	"pending": "กำลังรอเซิร์ฟเวอร์…", "busy": "กำลังทำรายการ กรุณารอสักครู่", "invalid_payload": "ข้อมูลไม่ถูกต้อง กรุณาลองใหม่",
	"character_required": "ตั้งชื่อตัวละครออนไลน์ก่อน", "not_connected": "กำลังเชื่อมต่อห้องอีกครั้ง…", "use_room": "กลับเข้าห้องเดิมเพื่อออกจากปาร์ตี้",
	"friend_left": "%s ออกจากปาร์ตี้", "friend_disconnected": "%s หลุด กำลังรอเชื่อมต่อใหม่", "friend_reconnected": "%s กลับเข้าห้องแล้ว",
	"reconnecting": "กำลังเชื่อมต่อห้องอีกครั้ง…", "reconnect_expired": "เชื่อมต่อกลับไม่สำเร็จ สามารถกลับแคมป์ได้",
}
static func message(code: String) -> String:
	return TEXT.get(code, TEXT.unavailable)

static func command_message(result: Dictionary) -> String:
	if result.get("ok", false): return "สำเร็จ"
	var code := str(result.get("error", "unavailable"))
	if RegEx.create_from_string("^[a-z_]{1,40}$").search(code) == null: code = "unavailable"
	return message(code) + " (" + code + ")"
