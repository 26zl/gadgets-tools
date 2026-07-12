// SSID formatting shared with native tests: JSON escaping and CSV field quoting.
// These are the injection-prone paths (SSID bytes are attacker-controlled), so they live
// here — free of Arduino types — to be regression-tested by tests/format_test.cpp.
#pragma once
#include <string>
#include <cstdio>
#include <cstring>

// Return `s` as a JSON string body (caller adds the quotes): escape " \ and control chars,
// and replace any invalid UTF-8 with U+FFFD so the response is always well-formed JSON.
static inline std::string jsonEscape(const char* s) {
  std::string j;
  const unsigned char* p = (const unsigned char*)s;
  while (*p) {
    unsigned char c = *p;
    if (c == '"' || c == '\\') { j += '\\'; j += (char)c; ++p; }
    else if (c < 0x20) { char b[7]; snprintf(b, sizeof b, "\\u%04x", c); j += b; ++p; }
    else if (c < 0x80) { j += (char)c; ++p; }
    else {                                         // multi-byte UTF-8: pass through only if well-formed
      int len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 0;
      bool ok = len > 0;
      for (int i = 1; ok && i < len; i++) ok = (p[i] & 0xC0) == 0x80;   // stops at the NUL terminator
      if (ok) { for (int i = 0; i < len; i++) j += (char)p[i]; p += len; }
      else { j += "\xEF\xBF\xBD"; ++p; }           // U+FFFD replacement, resync one byte
    }
  }
  return j;
}

// Return `s` as one RFC4180 CSV field, neutralizing a leading spreadsheet-formula character
// (= + - @ tab CR) so a captured SSID can't inject a formula into WiGLE-CSV consumers.
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
