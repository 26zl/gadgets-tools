// Native epoch-conversion regression tests through 2106.
#include "../src/datetime.h"
#include <ctime>
#include <cassert>
#include <cstdio>

int main() {
  assert(toEpoch(1970, 1, 1, 0, 0, 0) == 0u);
  assert(toEpoch(2000, 1, 1, 0, 0, 0) == 946684800u);
  // Boundaries that expose 32-bit overflow in the intermediate (see datetime.h):
  assert(toEpoch(2038, 1, 19, 3, 14, 8) == 2147483648u);   // 2^31
  assert(toEpoch(2106, 2, 7, 6, 28, 15) == 4294967295u);   // uint32 max

  // Cross-check against POSIX timegm + round-trip fromEpoch across 1970..2106.
  long checks = 0;
  for (uint32_t e = 0; e < 4294900000u; e += 26000) {   // odd step avoids only-midnights
    time_t tt = (time_t)e; struct tm tmv{}; gmtime_r(&tt, &tmv);
    assert(toEpoch(tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
                   tmv.tm_hour, tmv.tm_min, tmv.tm_sec) == e);
    int Y, M, D, h, mi, s; fromEpoch(e, Y, M, D, h, mi, s);
    assert(Y == tmv.tm_year + 1900 && M == tmv.tm_mon + 1 && D == tmv.tm_mday &&
           h == tmv.tm_hour && mi == tmv.tm_min && s == tmv.tm_sec);
    checks++;
  }
  printf("date math ok: %ld cross-checks vs timegm passed\n", checks);
  return 0;
}
