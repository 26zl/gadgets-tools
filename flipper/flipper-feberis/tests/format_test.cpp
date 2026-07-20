// Native tests for the security-relevant SSID formatters: CSV-field quoting and JSON escaping.
#include "../src/format.h"
#include <cassert>
#include <cstdio>

int main() {
  // CSV formula injection is neutralized with a leading apostrophe.
  assert(csvField("=cmd()") == "'=cmd()");
  assert(csvField(" =cmd()") == "' =cmd()");        // formula after a leading space
  assert(csvField("\t=x") == "'\t=x");              // leading tab is itself a trigger
  assert(csvField("home.sub") == "home.sub");       // benign value passes through
  assert(csvField("a,b") == "\"a,b\"");             // comma -> RFC4180 quoted
  assert(csvField("a\"b") == "\"a\"\"b\"");          // quote -> doubled inside quotes
  assert(csvField("") == "");                       // empty stays empty

  // JSON escaping: quotes, backslash, control chars.
  assert(jsonEscape("plain") == "plain");
  assert(jsonEscape("a\"b\\c") == "a\\\"b\\\\c");
  assert(jsonEscape("tab\there") == "tab\\u0009here");

  // UTF-8: valid multi-byte sequences pass through; invalid bytes become U+FFFD (valid JSON).
  assert(jsonEscape("caf\xC3\xA9") == "caf\xC3\xA9");                    // é
  assert(jsonEscape("bad\xFF" "tail") == "bad\xEF\xBF\xBD" "tail");      // lone invalid byte
  assert(jsonEscape("\xE2\x82") == "\xEF\xBF\xBD\xEF\xBF\xBD");          // truncated 3-byte -> two U+FFFD

  printf("format ok\n");
  return 0;
}
