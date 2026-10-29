// Treat captured SSID bytes as untrusted input in JSON and CSV exports.
#pragma once
#include <string>
#include <cstdio>
#include <cstring>

// Escape a JSON string body, replacing invalid UTF-8 with U+FFFD.
static inline std::string jsonEscape(const char* s) {
  std::string j;
  const unsigned char* p = (const unsigned char*)s;
  while (*p) {
    unsigned char c = *p;
    if (c == '"' || c == '\\') { j += '\\'; j += (char)c; ++p; }
    else if (c < 0x20) { char b[7]; snprintf(b, sizeof b, "\\u%04x", c); j += b; ++p; }
    else if (c < 0x80) { j += (char)c; ++p; }
    else {
      int len = c >= 0xC2 && c <= 0xDF ? 2 : c >= 0xE0 && c <= 0xEF ? 3 :
                c >= 0xF0 && c <= 0xF4 ? 4 : 0;
      bool ok = len > 0;
      for (int i = 1; ok && i < len; i++) ok = (p[i] & 0xC0) == 0x80;   // stops at the NUL terminator
      if (ok && len >= 3) {
        ok = !(c == 0xE0 && p[1] < 0xA0) && !(c == 0xED && p[1] >= 0xA0) &&
             !(c == 0xF0 && p[1] < 0x90) && !(c == 0xF4 && p[1] >= 0x90);
      }
      if (ok) { for (int i = 0; i < len; i++) j += (char)p[i]; p += len; }
      else { j += "\xEF\xBF\xBD"; ++p; }           // U+FFFD replacement, resync one byte
    }
  }
  return j;
}

// Quote one RFC4180 field and neutralize leading spreadsheet formula characters.
static inline std::string csvField(const char* s) {
  std::string v(s);
  size_t lead = 0; while (lead < v.size() && v[lead] == ' ') lead++;    // first non-space char
  if (lead < v.size() && strchr("=+-@\t\r", v[lead])) v.insert(v.begin(), '\'');
  if (v.find_first_of(",\"\n\r") == std::string::npos) return v;
  std::string o = "\"";
  for (char c : v) { if (c == '"') o += '"'; o += c; }
  o += '"';
  return o;
}
