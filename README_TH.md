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
| `install_windows.ps1` | ดาวน์โหลดไฟล์ที่หาย ตรวจ SHA-256 ติดตั้ง Python/Playwright/Chromium และสร้าง config ที่ขาด |
| `files.sha256.json` | รายการไฟล์และ SHA-256 สำหรับตรวจไฟล์ที่ดาวน์โหลด |
| `start_windows.ps1` | เริ่มตัวตรวจ Wi-Fi โดยเลือก Manual หรือ Auto |
| `config.example.json` | ตัวอย่างค่าหน้า Login สำหรับ Auto |
| `requirements.txt` | ไลบรารีสำหรับ Auto Login เท่านั้น |
| `windows/wifi_portal_monitor.ps1` | ตรวจอินเทอร์เน็ตและเปิดหน้า Login ให้กรอกเอง |
| `windows/auto_login.py` | ตรวจอินเทอร์เน็ตและกรอกฟอร์ม username/password ทั่วไป |
| `windows/esp32_server.py` | HTTP server บน Windows: GET `/health`, POST `/data` |
| `esp32/esp32_test/esp32_test.ino` | เชื่อม Windows Hotspot และเรียก `/health` |

## ติดตั้งบน Windows Server จาก GitHub

ใช้ Windows Server 2019 ขึ้นไปแบบ x64 ที่มี Desktop Experience และ PowerShell 5.1 ขึ้นไป
[ดูระบบที่ Playwright รองรับ](https://playwright.dev/python/docs/intro)
โหมด Auto ปัจจุบันเปิดเบราว์เซอร์แบบมีหน้าต่าง จึงต้องรันใน session ผู้ใช้ที่ล็อกอินอยู่
ยังไม่ได้จัดเป็น Windows Service หรืองานเริ่มอัตโนมัติหลัง reboot
เครื่องต้องมีอะแดปเตอร์ Wi-Fi, ไดรเวอร์ และฟีเจอร์ Wireless LAN ที่พร้อมใช้งาน หากจะเชื่อม Wi-Fi
ส่วน Mobile Hotspot ต้องตรวจการรองรับบน Windows/ไดรเวอร์จริง สคริปต์ไม่เปิดฟีเจอร์นี้หรือเปลี่ยน Firewall ให้เอง

ครั้งแรกต้องมีอินเทอร์เน็ตเพื่อดาวน์โหลดจาก GitHub, python.org, PyPI และเซิร์ฟเวอร์ Chromium
ถ้า Wi-Fi SPU ยังติดหน้า Login ให้ล็อกอินผ่านเบราว์เซอร์เองก่อน หรือใช้อินเทอร์เน็ตอีกทางระหว่างติดตั้ง
ไม่ต้องลง Git, Python, winget หรือ Arduino IDE บนเซิร์ฟเวอร์ล่วงหน้า

เปิด PowerShell แล้ววางชุดคำสั่งนี้ (ไม่ต้องเปิด Administrator เมื่อติดตั้งในตำแหน่งเริ่มต้น):

```powershell
$setupFile = Join-Path $env:TEMP 'install_wifi_esp32.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/tonklaspu/wifi_esp32_unified/main/install_windows.ps1' -OutFile $setupFile
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupFile -Mode Auto -Ssid '.@ SPU WiFi-2' -PortalUrl 'http://1.1.1.2/ac_portal/20251106155820/pc.html?template=20251106155820&tabs=pwd&dual_stack=0&vlanid=0&_ID_=0&switch_url=&url=http://1.1.1.2/homepage/index.html&controller_type=&mac=00-00-00-00-00-00' -Run
```

ชื่อหลัง `-Ssid` ต้องตรงกับโปรไฟล์ที่บันทึกใน `netsh wlan show profiles` ให้เชื่อมต่อผ่าน Windows อย่างน้อยหนึ่งครั้งก่อน
รหัสผ่านไม่ต้องใส่ในคำสั่ง โปรแกรมจะถาม username/password ตอนเริ่ม Auto

ตัวติดตั้งจะทำงานดังนี้:

1. เลือก commit จาก GitHub หนึ่งครั้ง แล้วอ่าน manifest และดาวน์โหลดไฟล์ทั้งหมดจาก commit เดียวกัน
2. ตรวจไฟล์ที่มีอยู่ เติมไฟล์ที่หาย และตรวจ SHA-256 ของไฟล์ที่ดาวน์โหลด
3. สร้าง `config.local.json` หากยังไม่มี โดยใช้ `-PortalUrl` ที่ระบุ และไม่เขียนทับ config เดิม
4. ดาวน์โหลดตัวติดตั้ง Python 3.13 x64 รุ่นที่ใหม่ที่สุดที่มีบนหน้า Windows ของ python.org ตรวจลายเซ็นผู้เผยแพร่ แล้วติดตั้งเฉพาะผู้ใช้ใน `.runtime`
5. สร้าง `.venv` ติดตั้ง dependencies และ Chromium แล้วทดสอบเปิด browser แบบ headless โดยไม่ล็อกอิน Portal
6. ถ้าใส่ `-Run` จะเริ่มโหมดที่เลือกหลังติดตั้งสำเร็จ

ตำแหน่งเริ่มต้นคือ `$env:LOCALAPPDATA\WiFiESP32` เปลี่ยนได้ด้วย `-InstallDir 'D:\WiFiESP32'` โดยผู้ใช้ต้องเขียนโฟลเดอร์นั้นได้
ให้รันติดตั้งและเปิดโปรแกรมด้วยบัญชี Windows เดียวกัน เพราะ Python/browser ติดตั้งแยกตามบัญชี
ถ้าต้องการติดตั้งอย่างเดียวให้เอา `-Run` ออก ถ้าไม่มีข้อมูล Portal จริงให้ตรวจ `config.local.json` ก่อนเริ่ม Auto

หลังติดตั้ง รันซ้ำเพื่อเช็กและเติมไฟล์ที่หายพร้อมเริ่มใช้งานได้:

```powershell
$appDir = Join-Path $env:LOCALAPPDATA 'WiFiESP32'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$appDir\install_windows.ps1" -InstallDir $appDir -Mode Auto -Ssid '.@ SPU WiFi-2' -Run
```

ถ้า `install_windows.ps1` เองหาย ให้ใช้ชุดคำสั่งดาวน์โหลดครั้งแรกอีกครั้ง
ไฟล์ที่มีอยู่แต่ hash ต่างกันจะถูกแจ้งเตือนและเก็บไว้ เพื่อรักษาการแก้โค้ด ESP32 ของคุณ
เพิ่ม `-Repair` เมื่อต้องการสำรองไฟล์ที่แก้ไว้ใน `.repair-backups` แล้วแทนด้วยไฟล์ GitHub
`config.local.json` ไม่ถูกเขียนทับแม้ใช้ `-Repair`; หากต้องเปลี่ยน Portal ภายหลังให้แก้ไฟล์นี้เอง
สามารถใช้ `-Ref '<commit SHA 40 ตัว>'` เพื่อติดตั้งรุ่นที่ระบุแน่นอน

โหมดอื่นใช้ตัวติดตั้งเดียวกัน:

```powershell
# Manual: เตรียมไฟล์และ config ไม่ติดตั้ง Python/Playwright
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$appDir\install_windows.ps1" -InstallDir $appDir -Mode Manual -Run
# Server: ติดตั้ง Python และเริ่ม HTTP server ไม่ติดตั้ง Playwright
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$appDir\install_windows.ps1" -InstallDir $appDir -Mode Server -Run
```

สคริปต์ไม่อัปโหลด ESP32 และไม่บันทึกบัญชี Portal การตั้งค่า Hotspot, Firewall และบอร์ดทำตามหัวข้อด้านล่าง
โฟลเดอร์ `.runtime`, `.venv`, `.downloads`, `.repair-backups` และ `config.local.json` ถูกยกเว้นจาก Git
สำหรับทดสอบหรือเตรียมไฟล์ออฟไลน์ ใช้ `-SourceDirectory '<โฟลเดอร์ชุดที่มี manifest>' -SkipDependencies` โดยไม่ใช้ `-Run` ใน Auto/Server
ตัวเลือกนี้ตรวจเฉพาะไฟล์และ config ไม่ถือว่าติดตั้ง dependencies สำเร็จ

## 1. เตรียม Windows แบบติดตั้งเอง

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
