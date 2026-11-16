#include <WiFi.h>
#include <HTTPClient.h>

// EDIT THESE: credentials of Windows Mobile Hotspot, NOT the upstream captive Wi-Fi.
const char* HOTSPOT_SSID = "Windows-ESP32";
const char* HOTSPOT_PASSWORD = "change-this-password";
// Replace with the actual IPv4 shown for the Windows Mobile Hotspot adapter by ipconfig.
const char* WINDOWS_HOTSPOT_IP = "192.168.137.1";
const uint16_t SERVER_PORT = 8080;

void setup() {
  Serial.begin(115200);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(HOTSPOT_SSID, HOTSPOT_PASSWORD);
  Serial.print("Connecting to Windows hotspot");
  const unsigned long started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < 20000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("ESP32 IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("Connection timed out; loop will retry.");
  }
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Wi-Fi disconnected. Reconnecting...");
    WiFi.reconnect();
    delay(10000);
    return;
  }

  String url = String("http://") + WINDOWS_HOTSPOT_IP + ":" + SERVER_PORT + "/health";
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(5000);
  if (!http.begin(url)) {
    Serial.println("Cannot initialize HTTP request.");
    delay(5000);
    return;
  }
  int code = http.GET();
  Serial.printf("GET %s -> HTTP %d\n", url.c_str(), code);
  if (code > 0) {
    Serial.println(http.getString());
  } else {
    Serial.println(http.errorToString(code));
  }
  http.end();
  delay(5000);
}
