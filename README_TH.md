# Wi-Fi Auto Login + Windows Hotspot + ESP32

ชุดนี้ใช้ **Windows และ ESP32 เท่านั้น** ไม่ต้องใช้ Ubuntu VM หรือ VirtualBox

```text
Wi-Fi ต้นทางที่มีหน้า Login
          |
        Windows  -- ล็อกอินแบบ Manual หรือ Auto
          |
   Mobile Hotspot 2.4 GHz
          |
        ESP32  -- เรียก HTTP ไปที่ Windows:8080 (เมื่อใช้สเก็ตช์ทดสอบ)
```

ถ้าต้องการเพียงแชร์อินเทอร์เน็ตให้ ESP32 ให้ตั้งการล็อกอินและ Mobile Hotspot ก็พอ ไม่ต้องเปิด HTTP server หรือพอร์ต 8080 ส่วน server ใช้สำหรับทดสอบเส้นทาง ESP32 → Windows ด้วยสเก็ตช์ตัวอย่างเท่านั้น และผล `/health` ไม่ได้ยืนยันว่าอินเทอร์เน็ตภายนอกใช้งานได้

## ไฟล์สำคัญ

| ไฟล์ | หน้าที่ |
| --- | --- |
| `start_windows.ps1` | เริ่มตัวตรวจ Wi-Fi โดยเลือก Manual หรือ Auto |
| `config.example.json` | ตัวอย่างค่าหน้า Login สำหรับ Auto |
| `requirements.txt` | ไลบรารีสำหรับ Auto Login เท่านั้น |
| `windows/wifi_portal_monitor.ps1` | ตรวจอินเทอร์เน็ตและเปิดหน้า Login ให้กรอกเอง |
| `windows/auto_login.py` | ตรวจอินเทอร์เน็ตและกรอกฟอร์ม username/password ทั่วไป |
| `windows/esp32_server.py` | HTTP server บน Windows: GET `/health`, POST `/data` |
| `esp32/esp32_test/esp32_test.ino` | เชื่อม Windows Hotspot และเรียก `/health` |

## 1. เตรียม Windows

1. เชื่อมต่อ Wi-Fi ต้นทางผ่าน Windows Settings อย่างน้อยหนึ่งครั้ง และบันทึกโปรไฟล์ไว้
2. เปิด PowerShell ที่โฟลเดอร์ `wifi_esp32_unified`
3. เลือกใช้ Manual หรือ Auto เพียงโหมดเดียว อย่าเปิดพร้อมกัน

### Manual — แนะนำให้ลองก่อน

ไม่ต้องติดตั้ง Python เหมาะกับหน้า Login ที่มี OTP, CAPTCHA, SSO หรือหลายขั้นตอน:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_windows.ps1 -Mode Manual -OpenHotspotSettings
```

โปรแกรมจะตรวจทุก 20 วินาทีและเปิดเบราว์เซอร์เมื่อยังออกอินเทอร์เน็ตไม่ได้ กรอกข้อมูลในเบราว์เซอร์ด้วยตนเอง กด `Ctrl+C` ใน PowerShell เพื่อหยุด

ถ้าต้องปรับค่าตรวจอินเทอร์เน็ตใน Manual ให้คัดลอก `config.example.json` เป็น `config.local.json` แก้ค่าที่ต้องการ แล้วเพิ่ม `-ConfigPath .\config.local.json` ในคำสั่งข้างต้น

### Auto — สำหรับฟอร์ม username/password ทั่วไป

ต้องมี Python 3.10 ขึ้นไป ติดตั้งครั้งแรกดังนี้:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m playwright install chromium
Copy-Item .\config.example.json .\config.local.json
```

แก้ `config.local.json` ให้ตรงกับ Portal จริง โดยเฉพาะ `PORTAL_URL` และ `PORTAL_ALLOWED_HOSTS` อย่าใส่ username หรือ password ในไฟล์นี้ ตัวอย่าง `1.1.1.2` เป็นเพียงค่าตัวอย่างและอาจใช้กับเครือข่ายของคุณไม่ได้

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_windows.ps1 -Mode Auto -ConfigPath .\config.local.json -OpenHotspotSettings
```

Auto จะถาม username/password ในเทอร์มินัลและซ่อนรหัสผ่านขณะพิมพ์ หากต้องการสั่งเชื่อมโปรไฟล์ Wi-Fi ที่บันทึกไว้ ให้เพิ่ม `-Ssid "ชื่อโปรไฟล์"` ชื่อนี้ดูได้จาก `netsh wlan show profiles` และอาจต่างจากชื่อ SSID ที่แสดงในรายการ Wi-Fi

หาก selector ของฟอร์มไม่ตรง ให้เพิ่มค่าต่อไปนี้ใน `config.local.json`:

```json
{
  "PORTAL_URL": "http://1.1.1.2/",
  "PORTAL_ALLOWED_HOSTS": "1.1.1.2",
  "PORTAL_TEST_URL": "http://www.msftconnecttest.com/connecttest.txt",
  "PORTAL_TEST_EXPECTED": "Microsoft Connect Test",
  "PORTAL_USER_SELECTOR": "input[name=userid]",
  "PORTAL_PASS_SELECTOR": "input[name=passwd]",
  "PORTAL_SUBMIT_SELECTOR": "button[id=loginBtn]"
}
```

ตรวจสอบโดเมนทุกชื่อก่อนเพิ่มใน allowlist หาก Portal ใช้ OTP, CAPTCHA, SSO หรือ JavaScript ซับซ้อน ให้ใช้ Manual

## 2. เปิด Windows Mobile Hotspot

ไปที่ **Settings → Network & internet → Mobile hotspot** แล้วตั้งค่า:

- Share my internet connection from: Wi-Fi ต้นทาง
- Share over: Wi-Fi
- Network band: 2.4 GHz สำหรับ ESP32 ที่รองรับเฉพาะย่านนี้
- ตั้งชื่อและรหัสผ่าน Hotspot แล้วเปิด On

`-OpenHotspotSettings` เปิดหน้าตั้งค่าให้เท่านั้น ไม่ได้เปิด Hotspot อัตโนมัติ เครื่องและไดรเวอร์ต้องรองรับการรับ Wi-Fi และปล่อย Hotspot พร้อมกัน

รัน `ipconfig` แล้วหา IPv4 ของอะแดปเตอร์ Mobile Hotspot เช่น `192.168.137.1` เก็บค่านี้ไว้ใช้กับ Firewall และ ESP32 หากปิด/เปิด Hotspot แล้ว IP เปลี่ยน ต้องแก้ทุกจุดให้ตรงกัน

## 3. เปิด HTTP server บน Windows (ใช้เมื่อทดสอบสเก็ตช์ตัวอย่าง)

ต้องมี Python 3.10 ขึ้นไป แม้เลือกล็อกอินแบบ Manual ตัว server ใช้ Python standard library จึงไม่ต้องติดตั้ง `requirements.txt` เพิ่ม เปิด PowerShell อีกหน้าต่างที่โฟลเดอร์ชุดนี้ แล้วรันและเปิดหน้าต่างทิ้งไว้:

```powershell
py -3 .\windows\esp32_server.py
```

ทดสอบบน Windows ก่อน:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/health
Invoke-RestMethod http://192.168.137.1:8080/health
```

เปลี่ยนคำสั่งที่สองให้เป็น IP ของ Mobile Hotspot จริง ควรได้ JSON ที่มี `"ok": true` และ `"server": "Windows"`

หาก Windows Firewall บล็อก ให้เปิด PowerShell แบบ Administrator แล้วปรับ IP/subnet ให้ตรงก่อนรัน:

```powershell
New-NetFirewallRule -DisplayName "ESP32 Windows Server 8080" -Direction Inbound -Action Allow -Protocol TCP -LocalAddress 192.168.137.1 -LocalPort 8080 -RemoteAddress 192.168.137.0/24
```

กด `Ctrl+C` เพื่อหยุด server หากต้องการเพียงให้อุปกรณ์ออกอินเทอร์เน็ตผ่าน Hotspot และไม่ได้ใช้ `/health` ไม่ต้องเปิด server และไม่ต้องสร้างกฎพอร์ต 8080

## 4. อัปโหลดสเก็ตช์ ESP32

1. เปิด `esp32/esp32_test/esp32_test.ino` ใน Arduino IDE ที่ติดตั้งแพ็กเกจบอร์ด ESP32 แล้ว
2. แก้ `HOTSPOT_SSID` และ `HOTSPOT_PASSWORD` ให้เป็นข้อมูลของ **Windows Mobile Hotspot** ไม่ใช่ Wi-Fi ต้นทาง
3. แก้ `WINDOWS_HOTSPOT_IP` ให้เป็น IPv4 ที่ได้จาก `ipconfig`
4. เลือกบอร์ดและพอร์ต แล้วอัปโหลด
5. เปิด Serial Monitor ที่ `115200 baud`

เมื่อ Hotspot, server และ Firewall ถูกต้อง ควรเห็น `HTTP 200` และ JSON ที่มี `"ok": true` สเก็ตช์ตัวอย่างเรียก GET `/health` ทุกประมาณ 5 วินาที หากนำไปใช้ออกอินเทอร์เน็ตจริง ให้เปลี่ยนโค้ดส่วน HTTP เป็นปลายทางของงานคุณ และไม่จำเป็นต้องรัน server ตัวอย่าง

## แก้ปัญหาเบื้องต้น

- Manual/Auto แจ้งว่าไม่มีอินเทอร์เน็ตทั้งที่เปิดเว็บได้: ปลายทางทดสอบอาจถูกบล็อก ให้ปรับ `PORTAL_TEST_URL` และ `PORTAL_TEST_EXPECTED`
- Auto หาแบบฟอร์มไม่พบ: ตรวจ selector หรือเปลี่ยนเป็น Manual
- `127.0.0.1:8080` ใช้ได้ แต่ IP Hotspot ใช้ไม่ได้: ตรวจ IP และ Windows Firewall
- Windows ทดสอบผ่าน แต่ ESP32 เข้าไม่ได้: ตรวจชื่อ/รหัส Hotspot, ย่าน 2.4 GHz, IP ในสเก็ตช์ และ subnet ของ Firewall
- Serial Monitor แสดง timeout หรือรหัส HTTP ติดลบ: ตรวจว่า server ยังทำงานและ IP/พอร์ตตรงกัน
- เปลี่ยนพอร์ต: ต้องแก้พอร์ตใน server, ESP32 และ Firewall ให้ตรงกันทั้งหมด

## ข้อควรระวัง

- ใช้เฉพาะบัญชี เครือข่าย และการแชร์อินเทอร์เน็ตที่คุณมีสิทธิ์ใช้งาน
- Auto ตรวจหน้าและปลายทางฟอร์มกับ allowlist ก่อนกรอกข้อมูล แต่ไม่สามารถควบคุม JavaScript ทั้งหมดของ Portal ได้ จึงต้องเชื่อถือ Portal ที่อนุญาต
- หาก Portal ใช้ HTTP ข้อมูลอาจไม่ถูกเข้ารหัสระหว่างทาง
- `esp32_server.py` เป็น server ตัวอย่างสำหรับเครือข่ายที่เชื่อถือได้ ไม่มี authentication หรือ TLS และไม่เหมาะกับการเปิดให้เข้าถึงจากอินเทอร์เน็ต
