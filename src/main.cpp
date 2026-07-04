// Feberis Pro firmware for WiFi scanning, GPS tracking, and local exports.

#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <esp_random.h>
#include <TinyGPSPlus.h>
#include <vector>
#include <algorithm>
#include <cstring>
#include "datetime.h"
#include "web_ui.h"

static const char* AP_SSID = "FeberisRecon";

static const int GPS_RX = 4;      // GPS TX  -> ESP32 GPIO4  (we read here)
static const int GPS_TX = 13;     // ESP32 GPIO13 -> GPS RX
static const int LED_PIN = 25;

static const uint32_t SCAN_EVERY_MS   = 8000;
static const uint32_t SCAN_TIMEOUT_MS = 20000;  // recover a stuck/failed scan
static const uint32_t TRACK_EVERY_MS  = 3000;
static const uint32_t GPS_STALE_MS    = 5000;   // a fix older than this is not "current"
static const size_t   MAX_APS   = 500;
static const size_t   MAX_TRACK = 1000;   // Adaptive downsampling preserves session coverage.
static const size_t   JSON_APS  = 60;     // top-N by RSSI go to the live view; full set is in the CSV

WebServer server(80);
TinyGPSPlus gps;
HardwareSerial GPSserial(1);

// Fixed-size access-point record.
struct Ap { uint8_t bssid[6]; char ssid[33]; int16_t rssi; uint8_t channel, enc;
            double lat, lng; uint32_t firstSeen; bool hasPos; };
struct Trk { double lat, lng; uint32_t t; };
std::vector<Ap> aps;
std::vector<Trk> track;

char apPass[64];
double curLat = 0, curLng = 0;
uint32_t curEpoch = 0;
bool haveFix = false;       // position AND time both current
bool haveTime = false;
int sats = 0;
size_t dropped = 0;         // APs seen but not stored (buffer full)
size_t scanFails = 0;       // scans that timed out / failed to start
uint32_t minHeap = 0xFFFFFFFF;
uint32_t trackInterval = TRACK_EVERY_MS;   // grows when the track buffer fills
uint32_t lastScan = 0, lastTrack = 0, scanStart = 0;
bool scanning = false;

static const char* loadOrMakePass() {
#ifdef FEBERIS_AP_PASS
  if (strlen(FEBERIS_AP_PASS) < 8 || strlen(FEBERIS_AP_PASS) > 63)
    Serial.println("WARNING: FEBERIS_AP_PASS must be 8..63 chars");
  snprintf(apPass, sizeof apPass, "%s", FEBERIS_AP_PASS);
#else
  Preferences p;
  p.begin("feberis", false);
  String s = p.getString("appass", "");
  if (s.length() < 8) {                                   // Generate a 128-bit password.
    static const char hx[] = "0123456789abcdef";
    uint32_t r[4] = { esp_random(), esp_random(), esp_random(), esp_random() };
    char buf[33];
    for (int w = 0; w < 4; w++)
      for (int i = 0; i < 8; i++) buf[w * 8 + i] = hx[(r[w] >> (i * 4)) & 0xF];
    buf[32] = 0;
    s = buf;
    p.putString("appass", s);
    Serial.println("Generated new random AP password (stored in NVS)");
  }
  p.end();
  snprintf(apPass, sizeof apPass, "%s", s.c_str());
#endif
  return apPass;
}

static String tsStr(uint32_t e) {  // "YYYY-MM-DD HH:MM:SS"
  int Y, M, D, h, mi, s; fromEpoch(e, Y, M, D, h, mi, s);
  char b[24]; snprintf(b, sizeof b, "%04d-%02d-%02d %02d:%02d:%02d", Y, M, D, h, mi, s); return b;
}
static String isoStr(uint32_t e) { // "YYYY-MM-DDTHH:MM:SSZ"
  int Y, M, D, h, mi, s; fromEpoch(e, Y, M, D, h, mi, s);
  char b[24]; snprintf(b, sizeof b, "%04d-%02d-%02dT%02d:%02d:%02dZ", Y, M, D, h, mi, s); return b;
}
static String macStr(const uint8_t* b) {
  char t[18]; snprintf(t, sizeof t, "%02X:%02X:%02X:%02X:%02X:%02X", b[0], b[1], b[2], b[3], b[4], b[5]);
  return t;
}
static const char* encStr(int m) {
  switch (m) {
    case WIFI_AUTH_OPEN: return "OPEN";
    case WIFI_AUTH_WEP: return "WEP";
    case WIFI_AUTH_WPA_PSK: return "WPA";
    case WIFI_AUTH_WPA2_PSK: return "WPA2";
    case WIFI_AUTH_WPA_WPA2_PSK: return "WPA/2";
    case WIFI_AUTH_WPA3_PSK: return "WPA3";
    case WIFI_AUTH_WPA2_WPA3_PSK: return "WPA2/3";
    default: return "ENT";
  }
}
static String authWigle(int m) { return m == WIFI_AUTH_OPEN ? "[ESS]" : String("[") + encStr(m) + "-PSK][ESS]"; }

static void jsonEscape(String& j, const char* s) {
  for (const unsigned char* p = (const unsigned char*)s; *p; ++p) {
    unsigned char c = *p;
    if (c == '"' || c == '\\') { j += '\\'; j += (char)c; }
    else if (c < 0x20) { char b[7]; snprintf(b, sizeof b, "\\u%04x", c); j += b; }
    else j += (char)c;                                   // bytes >=0x80 passed through (assumed UTF-8)
  }
}
static String csvField(const char* s) {
  String v(s);
  if (v.length() && strchr("=+-@\t\r", v[0])) v = String("'") + v;   // neutralize spreadsheet formulas
  if (v.indexOf(',') < 0 && v.indexOf('"') < 0 && v.indexOf('\n') < 0 && v.indexOf('\r') < 0) return v;
  String o = "\""; for (char c : v) { if (c == '"') o += '"'; o += c; } o += '"'; return o;  // RFC4180
}

static void feedGps() { while (GPSserial.available()) gps.encode(GPSserial.read()); }

static void ingest(int n) {
  for (int i = 0; i < n; i++) {
    uint8_t* b = WiFi.BSSID(i);
    if (!b) continue;
    int rssi = WiFi.RSSI(i);
    Ap* found = nullptr;
    for (auto& a : aps) if (memcmp(a.bssid, b, 6) == 0) { found = &a; break; }
    if (found) {
      if (rssi > found->rssi) found->rssi = rssi;
      if (!found->hasPos && haveFix) {                    // Add coordinates after GPS lock.
        found->lat = curLat; found->lng = curLng; found->firstSeen = curEpoch; found->hasPos = true;
      }
      continue;
    }
    if (aps.size() >= MAX_APS) { dropped++; continue; }
    Ap a{};
    memcpy(a.bssid, b, 6);
    snprintf(a.ssid, sizeof a.ssid, "%s", WiFi.SSID(i).c_str());
    a.rssi = rssi; a.channel = (uint8_t)WiFi.channel(i); a.enc = (uint8_t)WiFi.encryptionType(i);
    a.lat = haveFix ? curLat : 0; a.lng = haveFix ? curLng : 0;
    a.firstSeen = haveFix ? curEpoch : 0; a.hasPos = haveFix;
    aps.push_back(a);
  }
}

static void handleData() {
  std::vector<const Ap*> top;
  for (auto& a : aps) top.push_back(&a);
  std::sort(top.begin(), top.end(), [](const Ap* x, const Ap* y) { return x->rssi > y->rssi; });
  if (top.size() > JSON_APS) top.resize(JSON_APS);

  String j = "{\"gps\":{\"fix\":"; j += haveFix ? "true" : "false";
  j += ",\"time\":"; j += haveTime ? "true" : "false";
  j += ",\"lat\":" + String(curLat, 6) + ",\"lng\":" + String(curLng, 6) + ",\"sats\":" + String(sats) + "}";
  j += ",\"count\":" + String((int)aps.size());
  j += ",\"max\":" + String((int)MAX_APS);
  j += ",\"dropped\":" + String((unsigned)dropped);
  j += ",\"scanfails\":" + String((unsigned)scanFails);
  j += ",\"track\":" + String((int)track.size());
  j += ",\"trkgap\":" + String((unsigned)(trackInterval / 1000));
  j += ",\"heap\":" + String((unsigned)ESP.getFreeHeap());
  j += ",\"minheap\":" + String((unsigned)minHeap);
  j += ",\"scanning\":"; j += scanning ? "true" : "false";
  j += ",\"aps\":[";
  bool first = true;
  for (auto* a : top) {
    if (!first) j += ',';
    first = false;
    j += "{\"ssid\":\""; jsonEscape(j, a->ssid);
    j += "\",\"rssi\":" + String(a->rssi) + ",\"ch\":" + String(a->channel) +
         ",\"enc\":\"" + encStr(a->enc) + "\"";
    if (a->hasPos) j += ",\"lat\":" + String(a->lat, 6) + ",\"lng\":" + String(a->lng, 6);
    j += "}";
  }
  j += "]}";
  server.send(200, "application/json", j);
}

static void handleCsv() {
  server.sendHeader("Content-Disposition", "attachment; filename=\"feberis-wigle.csv\"");
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.send(200, "text/csv", "");
  server.sendContent("WigleWifi-1.4,appRelease=feberis,model=ESP32,release=1,device=FeberisPro,display=,board=esp32,brand=Feberis\r\n");
  server.sendContent("MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type\r\n");
  for (auto& a : aps) {
    feedGps();                                            // keep draining the GPS UART during export
    if (!a.hasPos || !a.firstSeen) continue;              // WiGLE needs a real position + time
    server.sendContent(macStr(a.bssid) + "," + csvField(a.ssid) + "," + authWigle(a.enc) + "," +
                       tsStr(a.firstSeen) + "," + String(a.channel) + "," + String(a.rssi) + "," +
                       String(a.lat, 6) + "," + String(a.lng, 6) + ",0,0,WIFI\r\n");
  }
  server.sendContent("");
}

static void handleGpx() {
  server.sendHeader("Content-Disposition", "attachment; filename=\"feberis-track.gpx\"");
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.send(200, "application/gpx+xml", "");
  server.sendContent("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                     "<gpx version=\"1.1\" creator=\"FeberisPro\" "
                     "xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><trkseg>\n");
  for (auto& t : track) {
    feedGps();
    server.sendContent("<trkpt lat=\"" + String(t.lat, 6) + "\" lon=\"" + String(t.lng, 6) + "\">" +
                       (t.t ? "<time>" + isoStr(t.t) + "</time>" : String("")) + "</trkpt>\n");
  }
  server.sendContent("</trkseg></trk></gpx>\n");
}

static void haltError(const char* msg) {
  Serial.printf("FATAL: %s — halting\n", msg);
  for (;;) {
    digitalWrite(LED_PIN, HIGH); delay(150);
    digitalWrite(LED_PIN, LOW);  delay(150);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  GPSserial.setRxBufferSize(1024);
  GPSserial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);
  WiFi.mode(WIFI_AP_STA);
  const char* pw = loadOrMakePass();
  if (!WiFi.softAP(AP_SSID, pw)) haltError("WiFi.softAP() failed");
  Serial.printf("\nAP \"%s\" up | pass: %s | http://192.168.4.1\n", AP_SSID, pw);
  server.on("/", []() { server.send_P(200, "text/html", INDEX_HTML); });
  server.on("/data.json", handleData);
  server.on("/wigle.csv", handleCsv);
  server.on("/track.gpx", handleGpx);
  server.begin();
}

void loop() {
  server.handleClient();
  feedGps();

  bool freshLoc  = gps.location.isValid() && gps.location.age() < GPS_STALE_MS;
  bool freshTime = gps.date.isValid() && gps.time.isValid() &&
                   gps.date.age() < GPS_STALE_MS && gps.time.age() < GPS_STALE_MS;
  if (freshLoc)  { curLat = gps.location.lat(); curLng = gps.location.lng(); }
  if (freshTime) curEpoch = toEpoch(gps.date.year(), gps.date.month(), gps.date.day(),
                                    gps.time.hour(), gps.time.minute(), gps.time.second());
  haveFix = freshLoc && freshTime;                        // only log observations when both are current
  haveTime = freshTime;
  if (gps.satellites.isValid()) sats = gps.satellites.value();
  uint32_t h = ESP.getFreeHeap(); if (h < minHeap) minHeap = h;
  digitalWrite(LED_PIN, haveFix ? HIGH : ((millis() / 500) % 2));

  if (haveFix && millis() - lastTrack > trackInterval) {
    lastTrack = millis();
    if (track.size() >= MAX_TRACK) {          // Downsample while preserving session coverage.
      size_t w = 0;
      for (size_t r = 0; r < track.size(); r += 2) track[w++] = track[r];
      track.resize(w);
      trackInterval *= 2;
    }
    track.push_back({ curLat, curLng, curEpoch });
  }

  // Scan asynchronously to keep the web server responsive.
  if (!scanning && millis() - lastScan > SCAN_EVERY_MS) {
    WiFi.scanNetworks(true, true); scanning = true; scanStart = millis();
  }
  if (scanning) {
    int n = WiFi.scanComplete();
    if (n >= 0) { ingest(n); WiFi.scanDelete(); scanning = false; lastScan = millis(); }
    else if (millis() - scanStart > SCAN_TIMEOUT_MS) {
      WiFi.scanDelete(); scanning = false; lastScan = millis(); scanFails++;
    }
  }
}
