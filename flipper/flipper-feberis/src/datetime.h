// UTC epoch conversion shared with native tests.
#pragma once
#include <cstdint>

static inline uint32_t toEpoch(int y, int m, int d, int hh, int mm, int ss) {
  y -= m <= 2;
  int era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long days = (long)era * 146097 + (long)doe - 719468;
  // Use 64-bit arithmetic beyond the 2038 boundary.
  return (uint32_t)((int64_t)days * 86400 + hh * 3600 + mm * 60 + ss);
}

static inline void fromEpoch(uint32_t e, int& Y, int& M, int& D, int& h, int& mi, int& s) {
  long z = e / 86400; long secs = e % 86400;
  h = secs / 3600; mi = (secs % 3600) / 60; s = secs % 60;
  z += 719468;
  long era = (z >= 0 ? z : z - 146096) / 146097;
  unsigned doe = (unsigned)(z - era * 146097);
  unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  long y = (long)yoe + era * 400;
  unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  unsigned mp = (5 * doy + 2) / 153;
  D = doy - (153 * mp + 2) / 5 + 1;
  M = mp + (mp < 10 ? 3 : -9);
  Y = y + (M <= 2);
}
