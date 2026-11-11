# บันทึกปัญหาออนไลน์ การดึงขา และตีมอนไม่ตรงภาพ — 27 ตุลาคม 2026

เอกสารนี้รวมหลักฐานจากรายงานผู้เล่นจริง โค้ด และการทดสอบเฉพาะจุด แยกสิ่งที่ยืนยันแล้วออกจากข้อสันนิษฐาน ไม่ถือว่า native test, rollout สำเร็จ หรือ manifest ตรง เป็นหลักฐานว่าเล่น Web แล้วหายหน่วง

## 1. เป้าหมายที่ผู้เล่นต้องการ

- กดเดิน แดช และโจมตีแล้วตอบสนองทันที ไม่ถูกดึงขาหรือวาร์ปกลับบ่อย
- เห็นมอนตรงไหน ต้องสามารถเล็งและตีได้สัมพันธ์กับภาพนั้น
- มอนและผู้เล่นอื่นเคลื่อนต่อเนื่อง ไม่หยุดกึกทุก snapshot
- เซิร์ฟเวอร์ยังตรวจ input, ดาเมจ, HP, ของ เงิน และรางวัล ไม่ยกข้อมูลบัญชีจริงให้ client ตัดสิน
- FPS เป็นข้อมูลประกอบ ไม่ใช่ตัวแทนความรู้สึกหน่วงทางเครือข่าย เกม 30 FPS ที่ตอบสนองดีต่างจากเกมที่ถูก reconciliation ดึงกลับ

## 2. สถาปัตยกรรมที่เกี่ยวข้อง

```text
Browser / Godot Web
  ├─ รับปุ่มและจำลองผู้เล่นตัวเองล่วงหน้า (prediction)
  ├─ WSS ผ่าน Cloudflare / Tunnel
  │    └─ Godot Room Worker แบบ headless บน k3s
  │         ├─ จำลองโลก 60 tick/s และ AI / การต่อสู้
  │         ├─ ตรวจ input และส่ง snapshot / event / ACK
  │         └─ ส่งผลที่ตรวจแล้วไปบริการบัญชี
  └─ Login / คำสั่งจัดการข้อมูล → Nakama
                                      └─ Godot Profile Worker → PostgreSQL
```

Room Worker ใช้ logic คณิตศาสตร์ร่วมกับ client; prediction จำลองเฉพาะเจ้าของ ไม่ใช่ AI ทั้งห้อง และไม่ตัดสินรางวัล ข้อมูลจริงของคนอื่น/มอนมาจาก Worker ส่วนภาพ remote actor มี clock interpolation แยกจากตำแหน่ง canonical

### Clock ที่ต้องแยก

| ค่า | ความหมาย | ใช้ทำอะไร |
|---|---|---|
| `server_tick` | world tick ที่ snapshot เป็นตัวแทน | จับคู่ history, ลำดับ snapshot |
| `input_ack` | input จริงล่าสุดที่ Worker ใช้ | ยืนยัน input ไม่ใช่ดัชนี state เสมอ |
| prediction target | tick ที่ client จำลองไปถึง | ตารางส่ง input และ replay |
| snapshot lead | target − tick ของ snapshot ล่าสุด | ระยะ replay โดยประมาณ รวมความเก่าขากลับ |
| estimated live lead | ประมาณ server ปัจจุบันจาก snapshot age และ RTT | diagnostic ไม่ใช่เวลาที่วัดตรง |
| input arrival margin | newest input tick − Worker tick ตอนรับแพ็กเก็ต | feedback คุม send-ahead ปัจจุบัน |
| remote render tick | world tick ที่กำลังแสดงมอน | ภาพ interpolation และ view-time melee |

`ping_ms` เป็น application RTT รวม browser scheduling, main-thread/poll ของ client และ Worker ไม่ใช่ pure network RTT ค่า ping 100+ ไม่ได้แปลว่าปุ่มต้องรอ server ก่อนขยับ และไม่มี disconnect ก็ไม่ได้พิสูจน์ว่าเส้นทางไม่มี delay/jitter

## 3. การทดลองและข้อจำกัด

### Synthetic perf-lab รุ่นแรก

ใช้ fixture สังเคราะห์ ไม่ได้ mirror คนเล่นและ AI/เหตุการณ์ห้องจริงครบ การเปิด receive/decode/apply ทีละชั้นช่วยวัดต้นทุนโค้ดใน workload นั้น แต่ใช้สรุปสาเหตุอาการห้องจริงโดยตรงไม่ได้ การบอกว่าแต่ละชั้นเพิ่มเล็กน้อยจึงไม่หักล้างรายงานผู้เล่น

### Actual Room A/B/C ที่ใช้ภายหลัง

- A: Worker ห้องจริง ส่ง input และ apply snapshot พร้อม prediction/reconciliation
- B: WSS และ Worker จริงยังอยู่ แต่ client ทิ้ง state/event หลัง bootstrap และใช้ local AI/sim; ไม่มีบันทึกรางวัล
- C: ใช้ local sim ชุดเดียวกับ B แล้วปิด socket ชั่วคราว; ไม่มี traffic และกลับ B ด้วย handshake

ผู้เล่นยืนยัน A ดึงขาหนักกว่า B/C หลักฐานนี้ชี้ว่าการใช้ authoritative state/reconcile เป็นส่วนสำคัญ แต่ B เปลี่ยนทั้ง sim และการ apply จึงไม่ใช่การพิสูจน์ว่า Cloudflare ผิดหรือบริสุทธิ์ และ C ที่ดีไม่ทำให้เราสรุปว่า WSS protocol เป็นสาเหตุเดียวได้

## 4. ปัญหาที่พบและแก้ไป

### 4.1 Disconnect 1009 จาก diagnostic instrumentation

เคยเกิด `encode k=6 key_type_21` / frame limit ต่อเนื่อง, input ACK ค้าง 0 และเข้า reconnect loop ต้นเหตุที่พิสูจน์ในเส้นทางนี้คือ diagnostic echo ใช้ StringName key (`echo.echo_stage`) ไม่ตรงชนิดที่ Wire codec รองรับ แก้ใช้ string key (`echo["echo_stage"]`) และทดสอบ PING ผ่าน transport 120 ครั้ง ไม่ใช่หลักฐานว่าทุก 1009 ในอนาคตมีต้นเหตุเดียวกัน

### 4.2 ขยับ tick และ apply state ผิดจังหวะ

- snapshot-relative ceiling เคยหยุด input/prediction เมื่อ snapshot เก่า ทั้งที่โลก Worker เดินต่อ
- เป้าหมาย tick ต้อง monotonic; ไม่ถอยกลับตาม snapshot
- หลัง bootstrap ย้ายการ apply authoritative state ไปต้น physics tick และ coalesce snapshot ที่ใหม่ที่สุดในเฟรมนั้น
- เก็บ prediction history จำกัด 128 tick เทียบกับ `server_tick` ไม่ใช่ ACK อย่างเดียว
- เติม future slots ที่จำเป็นด้วย held move/aim/run/guard เท่านั้น ไม่ทำซ้ำ attack/jump/dodge/skill edges
- เวลาต้อง reanchor เก็บเหตุผล `first_rtt` หรือ `world_overtook`; rebase ปกติไม่เติม lead กลับทุก packet

### 4.3 Replay ทั้งที่ทายตรง

เพิ่มการตรวจ continuation state (body/fighter ที่จำเป็นต่อการเดิน sim ต่อ) ก่อน reuse ถ้าตรง ใช้ carrier เดิมและอัปเดต remote actors / authoritative HP โดยไม่ replay history ทั้งหมด หากไม่ตรงหรือเปลี่ยน ownership/epoch ให้ rebuild ตาม authority ตามเดิม พบค่าของ gauge เก่าที่ทำให้ reuse ไม่ทำงานและแก้ให้ตรงกับ server ที่เลิกใช้ gauge แล้ว

### 4.4 Incoming hit ทำให้วาร์ป 1–2.4 เมตร

ก่อนหน้า ณ tick ที่เทียบตำแหน่งอาจตรง แต่ client เดินล่วงหน้าไปแล้ว พอใส่ hitstop/hitstun แล้วย้อนจำลอง ระยะปัจจุบันต่างมาก จึงเกิด snap

แก้เฉพาะภาพ: เมื่อมี incoming hit event ยืนยัน อนุญาต visual correction <3m, exponential decay40ms (ประมาณ95%ภายใน120ms) ตำแหน่ง/state จริงรับ authority ทันที ผู้ตาย/downed/eliminated ยัง snap และกรณีใหญ่เกินขอบเขตยัง snap ไม่ได้เปลี่ยนความแรงหรือ hitstun ของเกมเพื่อซ่อนปัญหา

รายงาน b51 และ caf ใน window ล่าสุด hard correction เป็น0 แต่ยังมี smooth corrections จึงห้ามสรุปว่าอาการดึงขาหายทั้งหมด

### 4.5 `move_frame` และ outgoing hitstop

พบ `move_frame` ไม่ใช่แค่เฟรมภาพ แต่มีผลต่อ active/startup ของการโจมตี จึงเอาออกจาก sync ไม่ได้

ทดสอบ static enemy: authority hit tick3 ตั้ง attacker hitstop3 แต่ prediction เดิม0; tickถัดไป client move_frame4.0879858 vs server3.06598935 ที่ ATKSPD2.199645 ความต่าง3.07/5.11ในรายงานสอดคล้องกับ3/5 simulation steps

เพิ่ม prediction ของ contact pause ฝั่งผู้โจมตีด้วย geometry เดียวกับ melee โดยไม่แก้ target HP/status, ไม่สุ่ม damage, ไม่ spawn side effects อย่างไรก็ตามมอนเคลื่อนที่/hidden skill filter ยังทำให้การทาย contact ต่างได้ รายงาน caf ยังพบ `move_frame`/`hitstop` unexpected จึงยังไม่ถือว่าปัญหานี้ปิดทั้งหมด

### 4.6 การจัดหมวด correction และข้อมูลที่หายจาก log

- HP ต่าง0.02จาก regen ต้องไม่ซ่อน movement desync เป็น health change
- ใช้ tolerance0.5สำหรับ standalone HP และพิจารณา field ที่ต่างก่อน
- incoming event, input gap, unexplained forced state, unexpected แยกกัน
- เก็บ last4 unexpected แยกจาก recent8 เพื่อไม่ให้ถูก input_gap ถัดมาทับทั้งหมด
- ยังต้องแยก outgoing authority hit evidence ให้ละเอียดขึ้น; `unexpected` ที่ไม่มี incoming event ไม่ได้แปลว่าไม่มีเหตุการณ์โจมตีใดเกิดขึ้น

### 4.7 Input ขาดระหว่างเล่นและ fallback

Worker ใช้ held input จริงล่าสุดได้สูงสุด24tick400ms โดยไม่ทำซ้ำ one-shot actions แล้ว neutral; ACKเดินเฉพาะ input จริง Late input ไม่ย้อนเวลา server และถูกทิ้งพร้อม audit

มี input มาถึงเป็นก้อนและ late_unapplied ทั้งระหว่างเล่นและต้น epoch การมาถึงเป็นก้อนอาจเกิด browser stall, Worker poll/catch-up, TCP/route buffering หรือหลายอย่างร่วมกัน ต้องใช้เวลาเป็นคู่และเทียบเส้นทาง ไม่สรุปว่าเป็น Tunnel หรือ browser จาก pattern อย่างเดียว

### 4.8 ตัวคุม lead รุ่น b51 ผิด

b51 ใช้ target − latest snapshot tick คุม ±5% rate แต่ค่านี้รวม snapshot age กรณีจริง snapshot age249ms, snapshot lead24, estimated live lead4 ตัวคุมกลับชะลอ95% ทำให้ input ตาม Workerไม่ทัน

นี่เป็นข้อผิดพลาดของแพตช์เราเอง ผล native fixture ที่ผ่านก่อนหน้าไม่ครอบคลุมความผิดปกติของ snapshot age ในการเล่นจริง ไม่ควรยืนยันว่า lead controller ถูกจาก fixture เดียว

### 4.9 ตัวคุม input margin รุ่น caf

Worker วัด newest input ของแต่ละแพ็กเก็ตครั้งเดียว ไม่เอา redundancy4frameมานับซ้ำ เก็บ p10marginใน1วินาที/ไม่เกิน128sample, late_total, sequence, measurement age และ packet gap p50/p95/max ณ Worker polling

Client เป้า margin2tick; late ใหม่เร่ง1.05, margin2กลับ1.0, marginเหลือมากชะลอไม่ต่ำ.95 Feedbackเก่าหรือไม่มีข้อมูลกลับneutral1.0; fixed simulation DT ยัง1/60, เปลี่ยนจำนวนtickไม่ใช่DT ตัวเลข desired_lead เก่าเหลือเป็น bootstrap heuristic

ลด verbose audit ใน wire32→8 (Workerยังเก็บ32) ขนาดรับ windowจริงจากประมาณ603–622KB เหลือ333–335KB ไม่มีการเพิ่มข้อมูล geometry เพื่อ interpolation

## 5. ผลล่าสุดจากผู้เล่น build caf6484fe127

| ตัววัดใน window ราว10วินาที | รายงาน1 | รายงาน2 |
|---|---:|---:|
| hard correction | 0 | 0 |
| smooth correction | 11 | 8 |
| input gap corrections | 5 | 6 |
| missing input ticks | 69 | 25 |
| late newest packets | 62 | 20 |
| replay ticks | 154 | 183 |
| server ticks advance | 596 | 606 |
| replay/server | 0.258 | 0.302 |
| received bytes | 333,417 | 334,787 |
| reconcile total | 402.9ms | 501.8ms |
| margin p10 ขณะ copy | +6 | −8 |
| packet gap max ใน feedback ล่าสุด | 49ms | 267ms |

ตัวเลข missing/late ดีขึ้นบางช่วงแต่ยังไม่หมด ไม่สามารถใช้ feedback จุดเดียวอธิบายทั้งwindow และไม่มีข้อมูลพิสูจน์ว่า gap267msเกิดจากrouteหรือWorker

ผู้เล่นแจ้งปัญหาใหม่ที่สำคัญกว่า: **เห็นมอนแต่ตีวืด ไม่รู้ตำแหน่งจริง**

## 6. สาเหตุตำแหน่งมอนกับการตีไม่ตรงภาพ

รุ่นเดิมเพิ่ม remote interpolation buffer12–24tick200–400ms เพื่อให้มอนต่อเนื่อง แต่ server ตรวจ melee กับ enemy box ปัจจุบัน ขณะที่ตัวผู้เล่นเองอยู่ใน predicted future และภาพมอนอยู่ในอดีต

รายงานล่าสุด:
- ชุด1 latest tick911, render898.7488 → ย้อนจาก snapshot12.25tick≈204ms
- ชุด2 latest2994, render2971.7636 → ย้อน22.24tick≈371ms

ตัวเลขนี้ยังไม่รวมเวลาที่ snapshot เดินทางกลับหรือ inputไปข้างหน้า มอนที่เห็นจึงไม่ตรงกับ target collider ตอน Workerตัดสิน โดยเฉพาะมอนที่เดิน/วิ่งผ่านผู้เล่น การทำให้ภาพดูต่อเนื่องอย่างเดียวทำให้ปัญหา hit registration เด่นขึ้น นี่เป็นข้อบกพร่องของการเชื่อม presentation กับ combat validation ที่เราต้องแก้

## 7. แพตช์ล่าสุด: bounded view-time melee compensation

ไฟล์อธิบายเฉพาะ: `docs/tech/melee_view_rewind_20261027.md`

1. ลด interpolation delayเป็น3–6tick50–100ms เพื่อไม่เพิ่มความเก่าภาพ200–400msเอง
2. Clientแนบ viewed worldtick ต่อinput เป็นส่วนท้ายoptionalของ INPUT packet; packetเก่ายังอ่านได้ และ retransmitใช้viewtickเดิม
3. Workerใช้เฉพาะ AABBมอนจากประวัติ simulationตัวเอง; ไม่รับclientposition,damage,hitIDหรือcollider
4. ตรวจviewไม่เกินsnapshotที่ACK,ไม่ใช่อนาคต,ไม่เก่าเกิน36tick600ms และไม่ข้ามepoch
5. ใช้ attacker/hitboxจริงปัจจุบัน ตรวจ target enemy AABBในอดีตที่ตรงview; current life/team/invulnerability/per-attack hitIDsยังใช้ตามauthority
6. ไม่ย้ายมอนกลับ ไม่เพิ่มระยะอาวุธ ไม่ให้hitซ้ำ ไม่ทำPvPrewind
7. Melee aim assistใช้targetเวลาเดียวกัน; local contact pauseใช้visualboxที่จับไว้ต่อinput
8. ประวัติจำกัด38tickฝั่งWorker/128inputฝั่งclient และไม่มีการส่งประวัติมอนทั้งชุดกลับclient
9. fallbackที่ไม่มีviewหรือเก่าเกินใช้currenttarget; ข้อมูลlegacyทำงานได้

### ขอบเขตและความเสี่ยงที่ต้องติดตาม

- 600msเป็นเพดานย้อนหลังของแพตช์ ไม่ใช่การรับรองว่าเหมาะสมที่สุดทุกmap/อาวุธ; ผู้เล่นอาจเลือกviewในหน้าต่างนี้ได้ ต้องติดตามfairness/ลดเพดานหากจำเป็น
- กฎcurrentinvulnerabilityอาจปฏิเสธhitบนอดีตที่ดูเหมือนโดน เป็นtradeoffที่ยังไม่อนุญาตให้clientตัดสิน
- ไม่มีlag compensationของprojectileหรือarea skillในแพตช์นี้ ต้องทดสอบแยก ไม่อ้างว่าทุกskillหายวืด
- ภาพdelayสั้นลงอาจเห็นการhold/stepช่วงnetworkgapมากขึ้น ไม่ใช้bufferใหญ่ซ่อนจนcombatใช้ไม่ได้
- ยังไม่ใช่full rollbackของโลก ไม่ย้อนAI/RNG/lootหรือสถานะผู้เล่นอื่น
- Historyกำหนดตามtickเต็ม; fractional interpolation/targetเปลี่ยนทิศเร็วอาจยังมีerror ต้องประเมินจากWebจริง

## 8. การทดสอบและสิ่งที่ห้ามสรุปเกินหลักฐาน

ผ่านเฉพาะ correctness contracts ที่เกี่ยวข้อง:
- real Room input queue300msRTT+jitter:0reverse/0missing/0tickIDregressionในworkloadนั้น
- fixedDT control clock/queuedone-shot once; marginfeedback/dedup/stale/epoch
- incoming2.4mhit visualblend/authoritystateทันที/deathsnap
- static melee contacthitstop parity และ5weapon×240inputparity
- historicalvisibleenemyอยู่ในswordbox/currentenemyไกล5m:currentquerymiss,historyqueryhit,enemyไม่teleport
- optional/legacyINPUTroundtrip,old/futureviewrejection,boundedhistory
- exactcandidateWorkerimage network-disabledผ่านmeleecontract
- Wire20skills×90tick ผ่านก่อนboundedviewhistoryfinalization max15,640bytes;ไม่ได้พิสูจน์Webperformance
- interpolationclockmonotonic,canonicalbodiesไม่ถูกเขียนทับ; delayลดลงทำให้underrunในfixtureเพิ่ม22/351เฟรม ไม่ปิดบังผลนี้

Full test suite **ไม่เขียว**: มีlegacybeta/profilefixtures และuser://writefailureที่บันทึกไว้ `build/clock-run_all.log` จึงไม่อ้างทั้งระบบผ่าน สิ่งที่ผ่านnativeไม่ใช่Webgameplayacceptance

## 9. งานค้างเรียงตามความสำคัญ

1. Deployแพตช์view-time meleeครบWorkerก่อนWeb แล้วตรวจจริงว่ามอนเดินเข้าหา/ผ่านตัวผู้เล่นตีโดนสัมพันธ์ภาพ ไม่ต้องให้ผู้เล่นทำA/B/Cกว้างอีก
2. เก็บreportจุดที่วืด พร้อมrewind/rejectedview/inputmargin/windowmissing/fieldunexpected; แยกbasicmeleeกับskill/projectile
3. ตรวจoutgoingcontacthitstopที่ยังunexpectedโดยใช้movingtargetไม่ใช่staticอย่างเดียว
4. แก้startup/epochinputlateโดยไม่freezeworldtimerหรือให้clientเพิ่มspeedauthority
5. เทียบเส้นทางเดียวกันผ่านTunnelกับLAN/Tailscaleจริง เมื่อมีoriginbrowserreachableและWSS/TLSเหมาะสม; ยังไม่มีผลroutecomparison ไม่เดาว่าเปลี่ยนhttp2หรือVPSแล้วหาย
6. ถ้าพบstall305msให้จับclient-send/Worker-receive/snapshot-arrival timelineคู่กัน; rawpollgapอย่างเดียวไม่ชี้ต้นเหตุ
7. Projectile/areasและskillmotionpredictionที่ยังไม่ครบ ต้องมีcontractและWebevidenceก่อนประกาศครบ

## 10. ประวัติ build / deployment ที่เกี่ยวข้อง

| Build | การเปลี่ยนหลัก | สถานะที่บันทึก |
|---|---|---|
| 48cbbab5c2f2 | prediction patchรุ่นก่อนหน้า | เคยdeployWeb prediction-20261027-1;ข้อความcommitเก่าไม่ใช่contentbuildID |
| 3710a78ee903 | replay diagnostic | ได้validจริงหลังแก้disconnect; replayONงานซ้ำสูง |
| f290f0387304 / ff1e018e6f37 / 4d10c3f4c7f0 | actualRoomstateapplyA/B/C | แยกapply/receive/socketclosed;Cbuttonเคยno-opแล้วแก้ |
| 46b7d7900409 | inputgate/monotonicticks/visualsmooth | deployแล้ว |
| fc20b525cd3f | physicshistory/Blinkmotion/firstdiff | deployWeb+Rooms |
| 841c3ba824e1 | continuationreuse | deployแล้ว |
| 50fe3fc081ea | remoteinterp/heldfallback | deployแล้ว;latermonsterhitmisalignment |
| b51aea6faa98 | timedilation/hitblend/contactpause | deployแล้ว;leadfeedbackพบผิดในWebจริง |
| caf6484fe127 | serverinputmargin/debugpayload | liveก่อนแพตช์melee |
| 68964d164870 | melee candidateแรก | buildเท่านั้นไม่ได้deploy |
| 8de2c27815b7 | boundedviewhistoryfinal | deployWeb+Roomsแล้ว ตรวจrollout/publicmanifestผ่าน;Webgameplayacceptanceยังรอ |

ก่อนปล่อยmelee:
- Web: `wiyazard:30500/zorx-web:input-margin-20261027-1@sha256:ddcf83ea15f568cb821702ca5f3e83833d7b3db1acf2f92cfd992e71da3f7fcd`
- Rooms: `wiyazard:30500/zorx-room-worker:input-margin-20261027-2@sha256:93b6c66b2ffd849d38552ca1c5db6c54df895c3beb91b04e5e0479c2757ffaaf`
- Rollbackก่อนmelee: `build/melee-rewind-rollback.json`
- Releaseสุดท้าย: `build/melee-rewind-release.json` (สร้าง/อัปเดตหลังrollout)

ProfileWorker/Nakamaไม่ต้องเปลี่ยนในแพตช์melee ข้อมูลบัญชี/Secretไม่รวมในเอกสารหรือDockercontext

## 11. บทเรียนที่ต้องยึดในการทำงานต่อ

- ให้ความสำคัญกับอาการrubberband/hitregistrationที่ผู้เล่นรายงานก่อนตัวเลขFPS
- ตรวจclockreferenceให้ตรงก่อนตั้งcontroller;ค่าsnapshotเก่าไม่ใช่เวลาปัจจุบัน
- ไม่ใช้syntheticfixtureแทนห้องจริงโดยไม่บอกข้อจำกัด
- แต่ละขั้นต้องมีสมมติฐานที่หักล้างได้ ไม่เพิ่มdiagnosticแบบไม่มีทางตัดสิน
- การแก้ให้ภาพsmoothต้องไม่ทำให้colliderกับภาพห่างจนเล่นไม่ได้
- รายงานwindowกับcumulativeต้องแยก และข้อมูลสำคัญunexpectedต้องไม่ถูกlognoiseทับ
- Deploymentverifiedต้องแยกจากWebacceptanceและfullsuitepassเสมอ

## 12. หลักฐานไฟล์และการตรวจย้อนหลัง

### แหล่งรายงานที่ใช้ในบันทึกนี้

ไฟล์แนบต้นฉบับอาจย้าย/หมดอายุในอนาคต ตัวเลขสำคัญจึงคัดไว้ในตารางข้างต้น โดยไม่ได้คัดข้อมูลบัญชีหรือ Secret:

- build50fe: attachment `d67ffd53-7d5a-433c-b87b-41182e9d622f` และ `98f2562a-5e59-4d48-a6c0-b14b5fc5acd3`
- buildb51: attachment `0a918733-3749-419b-833e-1672f3ef7840` และ `dd82712a-62b1-4b02-aab1-bc3f7c083ff4`
- buildcaf: attachment `88f7affc-c598-4c51-ac72-8dedfe6f2500` และ `ba14adb6-3829-48c2-b3ec-6f9137b2472a`
- ข้อเสนอ inputmargin ของผู้ใช้: attachment `cf23dca7-9d76-45fd-9922-06badb7164c4`

### โค้ดหลักสำหรับงานต่อ

| ไฟล์ | หน้าที่ |
|---|---|
| `client/session/remote_session.gd` | input history, physics reconcile, predicted owner, per-input view tick/visual AABBs |
| `client/session/control_clock.gd` | fixedDT accumulator, margin feedback, action queue |
| `client/session/prediction_history.gd` | history comparison, reasons, unexpected detail |
| `client/session/remote_interpolation.gd` | remote render clock และ presentation positions |
| `client/stage_view.gd` | วางภาพตาม presentation แทน canonical positions |
| `logic/game_sim.gd` | fixed-step shared simulation / owner prediction / melee target lookup |
| `logic/combat.gd` | attack phase, contact pause, authoritative hit resolution |
| `logic/net_wire.gd` | strict binary INPUT และ optional per-frame viewedtick |
| `server/rooms/room.gd` | authority tick, inputqueue/ACK/fallback/margin, enemy AABB history |
| `server/rooms/transport.gd` | WebSocket poll, sequence/baseline, timestamp validation against ACK |
| `client/perf/state_apply_toggle*.gd` | diagnostic A/B/C และ window counters |

### หลักฐานทดสอบและปล่อยล่าสุด

- `build/melee-melee_lag_compensation_contract.log`
- `build/melee-state_apply_toggle_contract.log`
- `build/melee-state_socket_toggle_contract.log`
- `build/melee-remote_movement_latency_contract.log`
- `build/web-_43oki6h/` — finalWebimport/exportlogs
- `build/melee-rewind-rollback.json` — deploymentก่อนเปลี่ยน
- `build/melee-rewind-release.json` — finalartifact/image/status

คำสั่งทดสอบโดยตรง: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/melee_lag_compensation_contract.gd` จากรากเกม `zorx/` ต้องมีtimeoutและตรวจSCRIPTERRORด้วย ไม่ใช้exit0อย่างเดียว

## 13. ผลการปล่อยแพตช์ล่าสุด

ปล่อยสำเร็จและตรวจ public manifest ตรง build **8de2c27815b7**:

- Web `wiyazard:30500/zorx-web:melee-rewind-20261027-1@sha256:62fdbcc744d29c8fa63fad8eeb1373f247a3533542a26237773c76736a1b46c2`
- Rooms `wiyazard:30500/zorx-room-worker:melee-rewind-20261027-1@sha256:4d74eba3a4e97624d94a0293453b5aeb60f92d23aab24ef1a12eceb0f364c7f1`
- ลำดับ Workerก่อนWeb,ทั้งสองrolloutสำเร็จ;capturedWorkerstartupไม่มีSCRIPTERROR/ParseError
- Profilecontainer imageเท่าเดิม;ไม่ได้แก้Nakama
- สถานะ: **พร้อมทดสอบผู้เล่นจริง ไม่ใช่ยืนยันว่าหายแล้ว**

การลองรอบนี้:เปิดเกมใหม่ให้buildตรง แล้วใช้ดาบ/มีดตีมอนที่กำลังเดินเข้าหาและเดินผ่านตัวในAหรือเกมปกติ หากยังวืด ให้ระบุว่าbasicattackหรือskillและแนบreportเพื่อดูrewind/rejectedview ไม่ต้องเปลี่ยนหลายตัวแปรพร้อมกัน

ก่อนหน้ามีคำสั่งเก็บrollbackติดระบบauto-reviewusagequota ไม่ใช่การตัดสินว่าแพตช์ไม่ปลอดภัย;หลังผู้ใช้สั่งต่อได้เรียกขั้นตอนอนุมัติตามเดิมสำเร็จและเก็บrollbackแล้ว ไม่ได้ข้ามapproval

## 14. 28ตุลาคม — เตรียมทางตรง API/WSS
เพิ่มHTTPSLANrouteเฉพาะAPIแล้ว:directTLShealth200/WSS101ผ่านด้วยcertificatevalidation ไม่ใช้-k;ยังไม่ใช่การทดสอบเล่นจริง Macยังต้องรันadminscriptenableเพื่อhosts+trust รายละเอียด/คืนค่า/expiryดู `docs/tech/lan_api_bypass_20261028_TH.md` ไม่เปลี่ยนgamebuildหรือเส้นทางไฟล์เกมCloudflare ผลroutecomparisonยังOPEN

## 15. 28ตุลาคม — LANยังหน่วงและWorkerlooporder
Latestreport b255a914: A,Web8de,ping48ms,10s214latepacket/231missingtick,packetgap1msmedian/145msp95/167msmax;12smoothcorrections/0hardsnap,unexpected0. UserreportsLANdirectbutreportdoesnotcarryRemoteAddressattestation. LiveRoomscgroupnr_throttled0/throttled_usec0/quota1core. CannotblameCPUcapacityfromthesevalues.
FoundWorkeradvancedsimBEFOREreceivingsocketinput. Changedreceive→tick→flush_states;actualTransportqueuedpacketcontractoldACK0missing1/newACK1missing0withposttickstate,exactcandidateimagepasses. Doesnotproveentire167msgapcause. Addworkerpollgaplast/maxintodelivery. Godotaccept_streamalreadysetsTCP_NODELAY;ourmissingexplicitcallwasnotaprovenNaglebugandnotchanged. WorkeronlyreleaseWebbuildunchanged;see docs/tech/room_poll_order_20261028.md and build/receive-first-release.json.

ReceivefirstWorkerปล่อยสำเร็จtagreceive-first-20261028-1,digest374cbc3f4372db9f85c112be897ace006bd6b785cd36f7ded6dfd2d30c423985;podheadless-875bf68b7-4bm57,Webbuild8deเดิม. ยังรอผลเล่นWebจริง ไม่ถือว่าอาการหายจากrolloutหรือcontractpass

## 16. ผลผู้เล่นหลังreceive-first: ดีขึ้นบางช่วง ยังไม่ปิดปัญหา
ผู้เล่นบอก“ดูดีขึ้น” รายงาน853425e4/73cd692aเป็นAvalidmaparena_aทั้งคู่. window1late24/missing32ต่อ504server_ticks≈6.35%,replay87/504≈0.17,7smooth/0hard,margin2/rate1.0,packetgapล่าสุดp9549ms/max50ms. window2late112/missing137ต่อ544ticks≈25.18%,replay567/544≈1.04,16smooth/0hard,margin-11/rate1.05,packetgapp95150ms/max350ms. ก่อนแก้ตัวอย่าง231missing/606ticks≈38.1%คนละmap/workload จึงไม่อ้างcausalpercentageimprovement. ทั้งสองunexpected0แต่ไม่พิสูจน์allskillpredictionถูก;window2มีauthority_forced_unattributedskill.pose. Workerlastpoll17ms/lifetimemax100msในทั้งสองreport จึงยังไม่อธิบายpacketgap350msด้วยWorkerpollgapalone;ไม่มีtimestampคู่ที่ยืนยันBrowservsnetwork. Subjectiveacceptancepartialดีขึ้น ไม่ใช่หาย. ไม่เพิ่มแพตช์จากรายงานนี้โดยไม่มีสมมติฐานเพิ่ม

ข้อควรระวังเพิ่มเติมsection16: total_frame_msของสองwindowเป็น12,928/12,998ms,maxframe3,435/3,287ms จึงไม่เรียกwindowนี้10sตรงๆ มีช่องว่างcallbackระดับ3วินาทีซึ่งอาจหยุดการส่งinput ไม่ใช่แค่FPSเฉลี่ยต่ำ แต่ยังไม่มีtimestamppair/visibilitytraceเพื่อบอกว่าtabbackground,copydialog,loading,mainthreadหรือOSpause ห้ามฟันธงruntimecause
