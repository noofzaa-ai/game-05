# ผลแยกสาเหตุแลคบน Web — 27 ตุลาคม 2569

**พบหลักฐานว่า client prediction/reconciliation เป็นตัวเพิ่มภาระจริง และมีต้นทุน rendering/warmup แยกอีกส่วน ไม่ใช่หลักฐานว่า WebSocket/server/ฐานข้อมูลเป็นต้นเหตุเดียวทั้งหมด**

รันจริง35รอบผ่าน Google Chrome155 / WebGL2 / ANGLE Metal Apple M1 /1335×720 จาก https://zorxplay.daiyooo.com/perf-lab/ build`d1b257c52b2a`. ไม่มี native Godot benchmark ในตารางนี้ ไม่มีการใช้บัญชีหรือบันทึกของจริง และไม่อัปเดตเกมหลัก.

## ชุดยืนยันสลับลำดับ C/D/E (อย่างละ3รอบ)

ตัวเลขคือ median ของผลแต่ละรอบ;เฟรมp95ยิ่งต่ำยิ่งดี ไม่ใช่ค่าFPSเฉลี่ย

|โหมด|เฟรมp50 ms|เฟรมp95 ms|รับแพ็กเก็ต/ปรับสถานะ p95 ms ต่อเฟรม|เวลา accept รวมต่อรอบ12s|
|---|---:|---:|---:|---:|
|C — ไม่มี prediction|21.1|26.8|4.1|343.3 ms|
|D — replay เฉพาะการเดิน|16.9|26.5|6.0|744.8 ms|
|E — replay แบบปัจจุบัน|18.5|31.0|11.6|1976.6 ms|

DเทียบE:เวลาacceptรวมลด62.3% แต่เฟรมp95ลด14.5% จึงห้ามตีความว่าFPSเพิ่ม62% ระบบDเป็น diagnostic branch ที่ replayเฉพาะMovement.step ของตัวเรา ยังไม่ใช่ production patch สำหรับ combat responsiveness

## ครบA–Eและreplay (รอบหลัก8โหมด×3รอบ)

|โหมด|เฟรมp95 ms median|drain p95 ms|เฟรมเกิน50msรวม3รอบ|
|---|---:|---:|---:|
|A|51.3|2.8|37|
|B|47.2|0.1|42|
|C|39.5|4.8|28|
|D|48.4|9.0|26|
|E|61.8|23.6|99|
|R|42.3|16.5|63|
|N|34.5|11.2|14|
|Z|17.7|2.7|6|

N=รับข้อมูล+replayแต่ปิดภาพ;A=แสดงภาพจากสถานะ/เหตุการณ์ที่อัดไว้;B=เกมเต็มในbrowserผ่านLocalSession;C=serverไม่prediction;D=servermovement-only;E=servercurrentprediction;R=replayแพ็กเก็ตเดิมไม่มีliveWS;Z=decode+applydeltaอย่างเดียวไม่วาด/ไม่จำลอง

ผลรอบแรกยังมีwarmupสูง: Aเฟรมp95=87.1ms รอบ2=51.3 รอบ3=24.3 จึงรายงานแยกและสลับลำดับC/D/Eอีกชุด ไม่ถือว่าสาเหตุwarmupถูกแยกละเอียดว่าเกิดจากshader/texture/V8/OSทั้งหมดแล้ว

## สิ่งที่พิสูจน์ได้

1. D/Eใช้server/canonicalstate/inputscript/ภาพเหมือนกัน แต่เปลี่ยน replayfunction: fullGameSim replay ใช้ CPUเพิ่มจริง. ขั้นตอนปัจจุบันสร้าง predictionGameSimและทุกentityใหม่ราว20ครั้ง/วินาที แล้วจำลองinputย้อนหลังหลายticks ซึ่งเป็นจุดแก้ถัดไปได้โดยไม่ลด server authority
2. Rไม่มีliveWebSocketแล้วยังเสียเวลากับdecode/accept/replayอยู่ ส่วนZเบากว่ามาก จึงไม่ควรเริ่มจากการย้ายฐานข้อมูลหรือทิ้ง server architecture ทั้งชุด
3. AและBเกิดframe spikesได้โดยไม่มีnetwork/auth/DB: rendering/first-use workมีส่วนแยกต่างหาก. drawcallsช่วงหนักราว1333ใน workloadนี้ ซึ่งสูงพอให้ต้องติดตามต่อ แต่ไม่ได้พิสูจน์ว่าdrawcallsอธิบายทุกspike
4. isolatedservertickp95ราว3.5ms ต่ำกว่างบ16.7ms ในโหลด1ห้อง/8มอนครั้งนี้;ไม่ได้พิสูจน์ว่าproductionหลายห้องไม่เคยค้าง
5. ข้อมูลstateรวมต่อรอบประมาณ355882bytes (~29.7KB/s) และคิวpacketในชุดยืนยันสูงสุด2:ไม่ได้พบหลักฐานthroughputตันในชุดนี้. ไม่มีRTT/end-to-endinputlatency acceptanceจากharnessนี้

## ข้อจำกัดสำคัญ

- เครื่องวัดคือAppleM1 ไม่ใช่3070Ti/มือถือของBoss
- Syntheticserverใช้canonicalscriptเพื่อให้ผลจำลองตรงกัน;clientส่งinputpacketsจริงเพื่อตรวจต้นทุนtransport แต่serverไม่ได้ใช้เวลามาถึงinputเป็นตัวกำหนดการเดิน/ยิง จึงไม่ใช่ทดสอบinput scheduling/reconciliation errorจากlatencyจริงแบบproduction
- Auth/admission/DB/CAS/ownership mutations ถูกตัดออกโดยตั้งใจ. Profile/runmetadataเป็นsnapshotจำลอง จึงยังไม่ครอบคลุมค่าใช้จ่ายrefreshคลัง/ตีบวก/สวมใส่จริง
- Cตัดบางmetadata/ownershiprefreshด้วย จึงใช้D/Eเป็นหลักฐานเฉพาะreplayที่ใกล้เคียงกันกว่า
- Workloadแยกใช้camera/renderer/models/VFXจริง แต่ไม่มีUIgameplayครบทุกตัวและไม่ได้เรียกinterpolationrenderpathครบแบบStageView. ผลนี้ไม่ใช่liveaccountFPS guarantee
- Workerห้องทดลองเป็นwrapperเฉพาะไม่ใช่RoomTransportทั้งหมด;tickmetricsวัดpureauthorityscenario. ทดสอบทีละห้อง ไม่ใช่load testหลายผู้เล่น
- WebGLพบmaterial-null diagnosticsตอนcleanupeffectที่มีอยู่เดิม ไม่ได้อ้างว่าแก้ข้อความนี้แล้ว

## ลำดับแก้ที่มีหลักฐานรองรับ

1. แยก localplayer predictionออกจาก fullworld GameSim replay โดยยังให้serverเป็นผู้ตัดสินHP/เงิน/ไอเทม/skilldamage
2. ใช้predictionstateเดิมซ้ำ ไม่สร้างทุกentityใหม่ทุกsnapshot;Dยังไม่ได้แก้การสร้างstate จึงยังมีพื้นที่ลดงานอีก
3. เพิ่มreal-accountperframe/percasttimingsและstatebytes/ownershiprefresh metrics แล้วเทียบบนเครื่องBoss
4. แยกcold-vs-warm shader/texture/animation workและลดdrawcallsต่อ โดยคงหน้าตาเดิม

**ยังไม่แก้หรือdeployระบบpredictionใหม่ในเกมหลัก** ตอนนี้เป็นผลพิสูจน์และdiagnosticbranchเท่านั้น ห้องทดลองจะscale0หลังเก็บผลเพื่อคืนทรัพยากร สามารถเปิดต่อเพื่อวัดเครื่องBossได้

## หลักฐาน

- `results/web_suite.json`:24รอบหลัก
- `results/web_confirmation.json`:11รอบยืนยัน(อุ่นเครื่องB,N + C/D/Eอย่างละ3)
- `results/browser_raf.json`:requestAnimationFrametraceอิสระ
- `results/hardware.json`:ChromeWebGLGPUจริง
- `results/verdict.json`:สรุปmachine-readableและข้อจำกัด
- `results/browser_ready.png`, `results/browser_confirmation.png`:ภาพหน้าWebจริง
- กลไก/วิธีรันและคำจำกัดความแต่ละโหมด: README.md
