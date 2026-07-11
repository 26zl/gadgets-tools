// GPS track point + buffer decimation, shared with native tests.
#pragma once
#include <cstdint>
#include <vector>

struct Trk { double lat, lng; uint32_t t; };

// Halve the track by keeping every other point; preserves session span at half density.
static inline size_t decimateTrack(std::vector<Trk>& t) {
  size_t w = 0;
  for (size_t r = 0; r < t.size(); r += 2) t[w++] = t[r];
  t.resize(w);
  return w;
}
