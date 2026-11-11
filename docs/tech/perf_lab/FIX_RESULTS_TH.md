# ผลพิสูจน์และแพตช์ client prediction — 27 ตุลาคม 2569

พบสาเหตุหนึ่งที่พิสูจน์ซ้ำได้: เมื่อรับสถานะ 20 ครั้ง/วินาที client สร้าง GameSim แล้ว replay ประวัติ input ล่วงหน้า ทุก tick เรียก simulation ทั้งห้อง รวมผู้เล่นอื่น การชนโจมตีและโปรเจกไทล์ ทั้งที่ผลเหล่านี้มาจากเซิร์ฟเวอร์อยู่แล้ว ยิ่งมี prediction lead ยิ่งทำงานซ้ำมาก งานนี้อยู่บน main thread ของ Web และไม่ปรากฏเป็นภาระใน log k3s ฝั่งเกม client.

## หลักฐานบนเว็บจริง

Google Chrome 155 / WebGL2 / ANGLE Metal Apple M1 / viewport 1335×720, render_scale 0.5, AA2, outline/shadows/fog/glow เปิด. ไม่ใช่การวัดบน RTX3070Ti หรือมือถือของ Boss. บัญชีจำลองและห้องแยก ไม่อ่าน/เขียนข้อมูลบัญชีจริง.

V3 ส่ง Wire.inputs จริงและใช้ RemoteSession._step_impl: E แบบเดิมเทียบ K แบบแก้ อย่างละ 3 รอบ สลับลำดับ. K ร่ายครบ 4 สกิลทุกครั้ง; E ได้ 2/2/1 ครั้ง และ input ที่เซิร์ฟเวอร์ใช้ได้ไม่เท่ากัน จึงไม่ถือเป็นงานเท่ากันอย่างสมบูรณ์. median p95 E/K 28.9/22.8 ms และ replay 1834.6/463.3 ms ต่อรอบ12วินาที. J ตัด refresh ownership จาก cooldown อย่างเดียวได้ผลน้อยกว่า; H ปิด VFX ก็ยังมีต้นทุน replay สูง. V2 lead ไม่พอและสกิลขาดหลายรอบ เก็บ raw ไว้แต่ไม่ใช้สรุป FPS แบบงานเท่ากัน.

## ยืนยันด้วยแพ็กเก็ตเดียวกัน

V4 build `fb2e23b49840`: อัด N ที่เซิร์ฟเวอร์ร่ายครบ 4 สกิล แล้ว replay ชุดเดิม 298 packet ตามเวลาเดิมบนเว็บ โดยไม่ต่อ WS ระหว่างรอบ R/P. อุ่นด้วย B/N ก่อน สลับ R/P/P/R/R/P. เปิด VFX ทั้งสองโหมด. ผล median ของโหมดละ3รอบ:

|ค่า|R เดิม|P แก้|
|---|---:|---:|
|Frame p95|27.1 ms|20.1 ms|
|Frame mean|17.71 ms|16.81 ms|
|Replay รวมต่อรอบ ~12s|1772.8 ms|459.4 ms|
|Replay ต่อ tick|564.9 µs|154.8 µs|
|Accept snapshot รวม|2343.3 ms|986.4 ms|

Replay รวมลด 74.1%; frame p95 ลด25.8%. ไม่ใช่ FPS เพิ่ม74%. จำนวน replay ticks เปลี่ยนเล็กน้อยตาม frame scheduling จึงแสดงต้นทุนต่อ tick ด้วย. เมื่อถอด live WebSocket ออกแล้วปัญหาเดิมยังเกิด และการเปลี่ยนเฉพาะขอบเขต prediction ลดต้นทุนลง เป็นหลักฐานเชิงแทรกแซงว่าต้นทุนนี้อยู่ใน client จริง.

## สิ่งที่แก้

`RemoteSession._advance_prediction` เรียก `GameSim.tick(local_player_id)` เฉพาะ client prediction. ใช้ logic ท่าโจมตี/บล็อก/แดช/กระโดด/เดิน/สถานะ/การหยุดจาก hitstop ของ actor เดิม แต่ไม่ tick ตัวอื่น ไม่ resolve damage, projectile, AI, loot หรือ economy ซ้ำ. Snapshot ยังอัปเดตทุกตัวตาม authority. ฝั่งเซิร์ฟเวอร์ยังใช้ `tick()` ตามเดิม และยังตัดสิน HP/ดาเมจ/สตามินา/คูลดาวน์/รางวัลเอง. การกดสกิลและข้อมูลบัญชียังผ่าน server validation เดิม.

ยังไม่ได้ใช้การ reuse simulator F หรือเปลี่ยน ownership refresh J ในเกมปกติ เพื่อลดขอบเขตแพตช์.

## ตรวจความถูกต้องและข้อจำกัด

- `tests/prediction_local_actor.gd`: 5 อาวุธ ×240 tick ผ่าน; เทียบตำแหน่ง/ความเร็ว/grounded/ท่า/เฟรม/สตามินา/แดชกับ simulation เดิม รวม hitstop, guard, skill freeze และ knockback. ตรวจว่าตัวอื่นกับ projectile ไม่ถูกเดินต่อโดย prediction. เป็น correctness check ไม่ใช่ native performance benchmark.
- ทั้งชุด `tests/run_all.gd` ไม่ผ่าน: ก่อนหยุดมี887 PASS/87 FAIL และติด loop ที่ `test_combat.gd:793` รออัลติเก่าที่ถูกปิดแล้ว. มี fixture เก่าเกี่ยวกับ profile/ชุด/อัลติด้วย. ไม่อ้างว่าผ่านทั้ง suite; log อยู่ใน results/regressions.log.
- ยังมี rendering/warmup เพิ่มเติม และมี material-null diagnostics ใน rendered runs ของห้องทดลอง ไม่สรุปว่าทุกอาการ lag ถูกกำจัดแล้ว.
- Worker tick p95 ในการทดลองราว3.5ms สำหรับหนึ่งห้อง ไม่ใช่ load test production/ฐานข้อมูล. การทดสอบนี้ไม่ตัดปัญหาเครือข่ายหรือเซิร์ฟเวอร์เมื่อใช้งานหนักออกทั้งหมด.
- เกมหลัก deploy แล้วหลัง Boss ยืนยัน: build `48cbbab5c2f2`, image prediction-20261027-1 digest befd553d88e43335fc89cba5c9a04c162095c8ac907867c20cec23cceaa8b1e2. Feature perf_labปิด, authเดิมคงอยู่. Rolloutสำเร็จและpublicmanifestตรง,16/16assetURLsHTTP200. Fresh Chrome smokeไม่มี uncaught JS errorและredirectไป landingตามปกติเพราะไม่ได้ล็อกอิน; ไม่อ้างว่าเป็นการเล่นบัญชีจริงหลังdeploy. Authority/profile workersไม่เปลี่ยน,lab0. รายละเอียดและrollback: build/prediction-main-release.json และ prediction-main-rollback.json.

Raw: results/web_input_v2.json, web_input_v3.json, web_exact_replay.json, fix_verdict.json และ browser_exact_replay.png. วิธีทำซ้ำ: tools/perf/run_exact_replay.cjs.


### Renderer diagnostic follow-up

เก็บ console เต็มจาก Chrome บนเว็บทดลองอีกหนึ่งรอบ (ไม่ใช้รอบนี้เปรียบเทียบ FPS): error ระบุ `material_casts_shadows`, `material_is_animated`, `material_get_instance_shader_parameters`, `material_update_dependency` ที่ `drivers/gles3/storage/material_storage.cpp` บรรทัด2579–2630. แต่ละ rendered run พบส่วนมาก84ข้อความ; no-render Nไม่พบ. โหมด H ที่ปิด combat VFX ก็ยังพบ84 จึงยังกล่าวไม่ได้ว่าเกิดจาก VFX cleanup. เป็น renderer-side material lookup และยังไม่ทราบ GDScript caller ที่ทำให้ RID ถูกปล่อย; ไม่ใส่แพตช์เดาสาเหตุลง candidate. Full browser log: results/material_browser_console.log. Candidate production imageไม่เปลี่ยนจากที่ตรวจแล้ว. รอบแรกของ diagnostic click ก่อน cold-load เสร็จและ timeout; รอบถัดไปรอ65วินาทีและจบ B ได้จริง. Lab scaled0หลังเก็บข้อมูล.
