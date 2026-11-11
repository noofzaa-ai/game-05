# วิเคราะห์รายงานแลค 2026-11-01

ต่อจาก `build/claude-handoff-lag-20261101.md` และ `docs/tech/online_lag_netfox_summary_20261028_TH.md`
ข้อมูลทั้งหมดอ่านอย่างเดียว (`BEGIN READ ONLY ... ROLLBACK`) ไม่มีการแก้ข้อมูลหรือ deploy

## 0. เครื่องมือดึงรายงานกรองผิด (แก้แล้ว)

`tools/backend/fetch_reports.sh` กรอง `message LIKE '[LAG REPORT%'` แต่ client ปัจจุบัน
(`client/lag_report.gd:47`) ส่งหัวข้อ `[NETFOX ROOM REPORT v1]` ตั้งแต่ย้ายมา Netfox
(commit `70eac6f`) จึงได้ 0 แถวทุกวันทั้งที่มีรายงานเข้ามาจริง

สำรวจ `zorx_feedback_v1` ทั้ง collection:

| หัวข้อ | จำนวน | ช่วงเวลา |
|---|---|---|
| `[NETFOX ROOM REPORT v1]` | 22 | 10-28 15:24 → **11-01 19:23** |
| `[LAG REPORT v2]` (เต็ม) | 27 | 10-24 23:11 → 10-27 16:11 |
| `[LAG REPORT v1]` | 11 | 10-18 23:56 → 10-24 22:43 |
| `[LAG REPORT v2]` (compacted) | 2 | 10-31 00:23 → 10-31 00:24 |

แก้สคริปต์ให้กรองทั้ง `[LAG REPORT%` และ `[NETFOX ROOM REPORT%` แล้ว ตอนนี้ได้ 4 รายงาน
ของวันที่ 11-01 และ 10 รายงานของ 10-31

หมายเหตุ: `zorx_diagnostics_v1` **ว่างทั้ง collection (0 แถว)** flight recorder ไม่เคยอัปโหลดสำเร็จ
(ตรงกับที่ handoff ระบุว่า Web `4513` ถูก rollback) จึงไม่มีข้อมูล `first_field` ของ correction

## 1. ข้อมูลที่ใช้ได้จริง

`seconds_oldest_first` คือ 3 บักเก็ตวินาทีสุดท้าย 13 ช่อง:
`frames, total_frame_ms, max_frame_ms, over50, poll_ms, step_ms, states, reconciles, corrections, decode_ms, reconcile_ms, packets, replay_ticks`

ในเส้น Netfox (`netfox_session.gd:163-164`) `step_ms` = `own_actor.prediction_us`
(= ต้นทุน rollback/prediction) และ `reconcile_ms` = `own_actor.restore_us`
ส่วน `poll_ms`, `reconciles`, `corrections`, `replay_ticks` ยังไม่ต่อสายในเส้นนี้ จึงเป็น 0 เสมอ

**รายงานก่อน 11-01 มี `step_ms`/`reconcile_ms` = 0 ทั้งหมด** (ยังไม่ได้ต่อตัวนับ) ใช้ได้แค่ FPS
รายงาน 4 ฉบับของ **11-01** เป็นชุดแรกที่มีต้นทุน netcode ติดมา — ใช้ชุดนี้สรุป

## 2. ผลวัดวันที่ 11-01 (ผู้เล่น ff, web, build `a0b71e0a73c5`)

| เวลา | แมพ | epoch | ping | FPS (3 วินาที) | step_ms/s | reconcile_ms/s | netcode % ของเวลาจริง |
|---|---|---|---|---|---|---|---|
| 15:45 | courtyard | 1 | 41 | **46 → 48** | 88 → 75 | 32 → 33 | 13% → 11% |
| 16:09 | quarry | 8 | 52 | **14 → 12 → 8** | 258 → 346 → 387 | 41 → 49 → 42 | 32% → 42% → **51%** |
| 19:03 | courtyard | 3 | 175 | **30 → 17 → 6** | 8 → 129 → 70 | 92 → 118 → 46 | 11% → 25% → 31% |
| 19:23 | gate | 1 | 304 | **24 → 15 → 6** | 267 → 428 → 340 | 56 → 71 → 44 | 34% → **50%** → 55% |

อ่านได้ว่า:

1. **ตอนเริ่มเข้าด่านเล่นได้ดีจริง** (15:45: 46-48 FPS, เฟรมสูงสุด 25-30ms, ไม่มีเฟรมเกิน 50ms, correction 1 ครั้ง 0.05m)
2. **แล้วทรุดลงเรื่อยๆ ภายในไม่กี่วินาที** FPS 24→15→6 และ 14→12→8 โดย `step_ms` **เพิ่มขึ้นพร้อมกัน** (267→428, 258→387) นี่คือวงจรป้อนกลับ: FPS ต่ำ → ต้องเดิน tick ต่อเฟรมมากขึ้น + หน้าต่าง replay กว้างขึ้น → CPU มากขึ้น → FPS ต่ำลงอีก (`netfox/time/max_ticks_per_frame=8` ที่ 8 FPS ต้องเดิน 7.5 tick/เฟรม = เต็มเพดานพอดี)
3. **ต้นทุน netcode ไปถึง 50-55% ของเวลาจริง** — ไม่ใช่ 11% แบบที่รายงาน compacted ของ 10-31 บอก (สองฉบับนั้นมาจาก client build เก่าคนละเส้นโค้ด ใช้สรุปเส้น Netfox ไม่ได้)
4. **correction ใหญ่จริง:** 16:09 `correction_max_m` = **6.004m**, 19:23 = 1.301m 49 ครั้ง — ตรงกับอาการ "ดึงขา"
5. ส่วนที่เหลืออีกราวครึ่งเฟรมเป็น render/เกม (สมมติฐาน 2 ยังจริงอยู่แต่ไม่ใช่ตัวเดียว)

→ **สมมติฐานที่ 1 ของ handoff (CPU ตอน rollback replay) ยืนยันแล้วด้วยตัวเลขจริง** ประมาณการเดิม
~300ms CPU/วินาที ใกล้ของจริง (267-428ms/วินาที) แต่ **สาเหตุไม่ใช่จำนวน replay tick ตาม RTT อย่างเดียว —
ต้นทุนต่อ tick แพงเกินเหตุ**

## 3. สาเหตุที่วัดแยกได้: `State.capture()` แพงกว่าการจำลองเอง ~9-15 เท่า

`runtime/netfox/actor.gd:97` เรียก `State.capture(simulation,actor_id)` **ทุก rollback tick** รวมทุก tick ที่ replay
และ `logic/net/actor_continuation.gd:8-22` ไม่ได้เก็บแค่ตัวเรา: บรรทัด 11-12 วนทุกตัวใน `sim.bodies`
ทำ `Codec.fields()` ทั้ง body+fighter ของทุกตัว แล้วบรรทัด 18 เรียก `_value_safe()`
เดินซ้ำทั้งโครงสร้างอีกรอบ ก่อน `var_to_bytes()` บรรทัด 21 → ต้นทุนโตตามจำนวนตัวในฉาก

วัดบนเครื่อง Mac native (สคริปต์ `build/bench_capture.gd`, `build/bench_capture2.gd`, ห้อง goblin wave lab จริง):

| ตัวในฉาก | advance (จำลองจริง) | capture | ในนั้นเป็น `_value_safe` | ขนาด snapshot |
|---|---|---|---|---|
| 5 | 184 µs | **1,686 µs** | 1,020 µs (60%) | 15 KB |
| 10 | 234 µs | **2,761 µs** | 1,780 µs (64%) | 27 KB |
| 15 | 280 µs | **4,312 µs** | 2,594 µs (60%) | 38 KB |
| 20 | 331 µs | **4,972 µs** | 3,360 µs (68%) | 50 KB |

- `capture` แพงกว่า `advance` ที่มันไปถ่ายภาพ **9-15 เท่า** และโตเชิงเส้นตามจำนวนตัว
- **60-68% ของ capture คือ `_value_safe()`** ซึ่งเป็นการเดินตรวจข้อมูลที่เราเพิ่งสร้างเองทุก tick
  (ฝั่งรับมี `inspect()` ตรวจให้อยู่แล้วตอน restore)
- ที่เหลือคือ `Codec.fields()` ของตัวอื่นๆ (11-16%) และ `var_to_bytes` (8-10%)
- เว็บ/wasm ช้ากว่า native หลายเท่า ตรงกับที่วัดได้จริงในเกม ~2-3.3 ms ต่อ prediction tick
  (19:23: `prediction_us` 2,805,000 / `prediction_ticks` 966 = 2.9 ms/tick)

`State.restore()` ก็แพง: 19:23 `restore_us` 587,000 / `restore_count` 180 = **3.26 ms ต่อครั้ง**
(benchmark native ให้เลขสูงผิดปกติ 27 ms — ยังไม่สรุป ต้องแยกวัดส่วน `skill_system.restore` ต่อ)

## 4. ที่ยังเป็นข้อสงสัย (ยังไม่พิสูจน์)

- `logic/net/actor_continuation.gd:41` ตรวจ `_same_shape` ของ context target ทุกตัวเทียบกับ
  field ของ **ตัวเราเอง** (`sim.bodies[id]`/`sim.fighters[id]`) ไม่ใช่ของ target นั้น ตอนนี้ไม่พังเพราะ
  fighter เป็นคลาสเดียวกัน แต่เป็นบั๊กซ่อนอยู่
- ส่วน render ครึ่งที่เหลือยังวัดไม่ได้ เพราะ `client/lag_report.gd:59` ลบ `graphics` และ `runtime`
  (render_scale, draw_calls, primitives, process_ms, physics_ms, vsync) ทิ้งก่อนเป็นอย่างแรกเวลาย่อรายงาน
  — ซึ่งเป็นฟิลด์ที่ต้องใช้ตรวจสมมติฐาน render พอดี
- `ping_ms` เชื่อไม่ได้เต็มที่: `ping_age_ms` 381-771 ms ในทุกรายงาน (ค่าเก่ากว่าครึ่งวินาที)

## 5. ที่มาของ build เชื่อไม่ได้ (เรื่องสำคัญแยก)

`packs.json` ของเว็บจริง: build `9b77e80430dc`, core **สร้าง 2026-10-29 11:21 UTC**,
`baseline_build` `659a8eeb9299`, patch 2026-11-01 16:06 แตะแค่ 5 ไฟล์ตัวละคร, `dirty: true`,
`commit a0b71e0a73c5`

เพราะ build เว็บเป็น **patch ทับ PCK baseline เก่า** ฟิลด์ `version` ในรายงานจึงเป็น git HEAD
*ตอนทำ patch* ไม่ใช่โค้ดที่รันอยู่จริง หลักฐาน: รายงาน `[LAG REPORT v2]` compacted ของ 10-31
มีตัวนับ `movement_sync` (`hard_corrections`, `prediction_rebases`, `lead_trim_ticks`,
`filled_input_ticks`) ซึ่ง**ไม่มีอยู่ใน commit หรือ branch ใดของ repo นี้เลย** ทั้งที่ติดป้าย
version เดียวกับรายงาน Netfox — เทียบ string ใน `core.18141a57b548.pck.wasm` ที่โหลดจากเว็บจริง
พบ `NETFOX ROOM REPORT`/`netfox_authoritative_room` แต่ไม่พบ `hard_corrections`/`LAG REPORT v2`
ยืนยันว่าสองรายงานนั้นมาจาก client build เก่าคนละตัว

→ **อย่าสรุปตัวเลขแลคโดยเชื่อฟิลด์ `version`** ต้องผูกรายงานกับ `core` digest + `worker_release`
(`worker_release` มีในรายงาน Netfox อยู่แล้ว: `flight-20261031-1`, `goblin-waves-20261101-1`)

## 6. ข้อเสนอลำดับถัดไป (รอ Boss สั่ง)

1. **ตัด `_value_safe()` ออกจากทาง capture ฝั่ง client** (คงไว้ฝั่ง authority และคง `inspect()` ตอน restore)
   — คาดลดต้นทุน capture 60-68% โดยพฤติกรรมเกมไม่เปลี่ยน
2. **ไม่ต้อง `var_to_bytes` ทุก tick ที่ replay** เก็บเป็น value snapshot แล้ว serialize เฉพาะ tick ล่าสุด
3. ทบทวนว่า snapshot ของตัวเราต้องอุ้ม body+fighter ของ **ทุกตัวในฉาก** จริงหรือไม่ (ข้อนี้กระทบ
   ระบบ logic/client → **ต้องให้ Boss ตัดสินก่อน**)
4. เลิกลบ `graphics`/`runtime` เป็นอย่างแรกตอนย่อรายงาน (ลบ `seconds_oldest_first` บักเก็ตเก่าก่อน)
   เพื่อให้วัดฝั่ง render ได้
5. ซ่อม `enable_goblin_wave_lab` default = `true` (`server/rooms/room.gd:147`) ก่อน deploy ครั้งถัดไป
   ตามที่ handoff ระบุ
