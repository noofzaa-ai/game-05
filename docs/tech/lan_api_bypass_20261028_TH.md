# เทียบ API/WSS ผ่าน LAN โดยไม่ผ่าน Cloudflare

## สถานะ

เพิ่มเส้นทาง HTTPS แยกบน k3s สำหรับ `zorxapi.daiyooo.com` ที่ `192.168.1.99:443` แล้ว ไม่แก้ image เว็บ/Rooms และไม่เปลี่ยน HTTP ingress ที่ Tunnel ใช้อยู่

- `nakama-public-lan-tls`: HTTPS API → Nakama7350
- `room-gameplay-lan-tls`: HTTPS `/room` → Room Worker8060 (pathยาวกว่ามีprecedence)
- คง middleware เดิมของแต่ละroute
- SecretTLSชื่อ `zorxapi-lan-test-tls`; privatekeylocalถูกลบหลังapply ไม่เขียนลงrepoหรือเอกสาร
- CertificateเฉพาะDNS `zorxapi.daiyooo.com`, serverAuth, CA:FALSE, self-signed7วัน
- หมดอายุ **2026-11-04 03:47:32 Asia/Bangkok** (2026-11-03 20:47:32 UTC)
- SHA256: `19:2B:31:A5:67:CF:2A:C8:29:0D:FB:71:32:C6:14:A2:10:9B:36:B9:45:0A:7E:26:AA:E0:A9:82:CF:E6:56:12`
- Publiccertificateอยู่ `build/lan-api-test/zorxapi-lan.crt`; ingressเดิมสำรอง `build/lan-api-test/original-ingress.json`

## ผลตรวจจริง

ใช้curl `--resolve zorxapi.daiyooo.com:443:192.168.1.99` พร้อม `--cacert` ของcertificateนี้ ไม่ใช้ `-k`:

- `/healthcheck`: HTTP200
- `/room`พร้อมWebSocketUpgradeheaders: HTTP101SwitchingProtocols
- `/room`แบบHTTPธรรมดาได้502 ไม่ใช่การทดสอบWebSocketที่ถูกต้อง
- หลังhandshakeไม่มีadmissionticket Workerตัดpendingconnectionตามกติกาเดิม จึงมีcurlEmptyreplyหลัง101ได้

นี่พิสูจน์TLSและroute/WSupgradeเท่านั้น ยังไม่ใช่ผลเปรียบเทียบการเล่นหรือloginจริง

## ขั้นตอนบน Mac ของผู้เล่น

ต้องใช้สิทธิ์adminของmacOS; agentตรวจ `sudo -n true` แล้วขึ้นpasswordrequired จึงยังไม่ได้แตะhostsหรือtruststore

เปิดTerminalแล้วรัน:

```bash
bash /Users/user/godot-project/test01/zorx/tools/net/lan_api_bypass.sh enable
```

สคริปต์:
1. ตรวจcertificateยังไม่หมดอายุ
2. ขอรหัสผ่านผ่านsudoบนเครื่องเท่านั้น
3. Trustเฉพาะcertificateนี้สำหรับSSLและhostname `zorxapi.daiyooo.com` ในSystemkeychain ไม่ติดตั้งgeneralCA
4. สำรองhostsเป็น `/etc/hosts.zorx-lan-api-backup-<timestamp>`
5. เพิ่มเฉพาะบรรทัดมีmarker:

```text
192.168.1.99 zorxapi.daiyooo.com # zorx-lan-api-test
```

6. flushDNSแล้วตรวจhealth

ไม่มีhostsสำหรับ `zorxplay.daiyooo.com` หรือlanding จึงยังดาวน์โหลดเกมผ่านCloudflareเหมือนเดิม อนุญาตAPIตรงเฉพาะเครื่องที่overrideDNSและtrustcertificate ไม่เปลี่ยนDNSpublic

ปิดbrowserทั้งโปรแกรมแล้วเปิดใหม่ เพื่อไม่ใช้WSSsocket/DNSconnectionเก่าค้าง ดูDevToolsNetworkที่APIและ`/room`ว่าRemoteAddressเป็น **192.168.1.99:443** และsocketได้101 ถ้ายังเห็นpublicCloudflareIPถือว่ายังไม่ได้bypass อย่ารวมผลสองเส้นทาง

ถ้าbrowserแสดงcertificatewarning ให้หยุดตรวจtrust/fingerprint ไม่ปิดsecurityทั้งbrowserหรือใช้ignore-certificate-errors

## วิธีเทียบให้ตอบคำถามเดิม

1. LAN: buildเดิม/บัญชีเดิม/mapและgraphicsเดิม เล่นเดินเลี้ยวแดชและตีมอน เก็บreport
2. คืนCloudflareด้วยคำสั่งdisableด้านล่าง ปิดbrowserเปิดใหม่ ตรวจRemoteAddressเปลี่ยนแล้ว เล่นแบบเดียวกัน
3. เทียบinputmargin,late_input_packets,missing_input_ticks,packetgap_p95/max,correctionระยะ/จำนวน และความรู้สึกดึงขา/ตีโดนภาพ
4. ถ้าทางLANดีขึ้นสม่ำเสมอ เป็นหลักฐานว่าขาเส้นทางมีผล แต่ยังไม่แยกCloudflareedge/Tunnel/TCP/ISPทั้งหมด ถ้าทั้งคู่ยังมีปัญหา ให้ตรวจworker/reconcileต่อจากข้อมูลเดียวกัน
5. ไม่ต้องbuild/deployเกมใหม่เพื่อสลับสองเส้นทาง

## คืนค่าบน Mac

```bash
bash /Users/user/godot-project/test01/zorx/tools/net/lan_api_bypass.sh disable
```

ลบเฉพาะhostsmarkerนี้ ถอนtrustและcertificateนี้ แล้วflushDNS ไม่ทับhostsทั้งไฟล์จากbackup เพราะผู้ใช้อาจแก้รายการอื่นระหว่างทดสอบ

## เก็บกวาดฝั่ง k3s หลังเลิกทดสอบ

ยังไม่ได้รันคำสั่งนี้เพราะต้องใช้ทางLANทดสอบก่อน:

```bash
kubectl -n zorx-staging delete ingress nakama-public-lan-tls room-gameplay-lan-tls
kubectl -n zorx-staging delete secret zorxapi-lan-test-tls
```

ไม่ลบingressหลัก/Secretบัญชี และควรdisableบนMacก่อนcertificateหมดอายุเพื่อไม่ทิ้งhostsชี้ทางตรงที่browserไม่เชื่อถือ

## Chrome trust correction — ยังรอ apply Secret
ChromeจริงเปิดAPIhealthพบNET::ERR_CERT_AUTHORITY_INVALID แม้macOSsecurityverifyผ่าน จึงยังไม่ถือว่าBrowserTLSพร้อม สร้างCA7วันแบบnameConstraintsDNSzorxapi.daiyooo.com/pathlen0 และleafSANเฉพาะhostnameนี้แล้ว;CAprivatekeyลบหลังsign มีเพียงleafkeyชั่วคราวรอส่งเข้าTLSSecretเดิมแล้วลบlocal
CA SHA256 `B8:97:8F:53:C6:D4:AB:3D:E5:26:E9:1A:D4:D7:6A:5B:68:E1:F5:C5:39:0B:E3:A8:A9:16:A5:F0:EC:F4:83:1E`;หมดอายุ2026-11-04 05:19:06Asia/Bangkok
Scriptปรับให้trustCAแทนleafและถอนlegacytrust ไม่ปิดcertificatevalidation ไม่กดข้ามChromeinterstitial
Automaticapprovalreviewปฏิเสธการส่งgeneratedleafprivatekeyไปk3s192.168.1.99และแทนSecretzorxapi-lan-test-tls โดยให้ขอhumanapprovalเฉพาะขั้นนี้ ยังไม่ได้เปลี่ยนSecretหรือtrustใหม่ อย่าอ้างว่าแก้แล้วหรือให้enableใหม่จนกว่าจะapplyสำเร็จ
