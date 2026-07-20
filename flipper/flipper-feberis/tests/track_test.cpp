// Native test for track decimation.
#include "../src/track.h"
#include <cassert>
#include <cstdio>

int main() {
  std::vector<Trk> t;
  for (uint32_t i = 0; i < 1000; i++) t.push_back({ (double)i, (double)i, i });
  assert(decimateTrack(t) == 500);                          // 1000 -> 500
  for (size_t k = 0; k < t.size(); k++) assert(t[k].t == 2 * k);   // kept indices 0,2,4,...

  std::vector<Trk> odd = { {0, 0, 0}, {0, 0, 1}, {0, 0, 2}, {0, 0, 3}, {0, 0, 4} };
  assert(decimateTrack(odd) == 3);                          // 5 -> 3 (indices 0,2,4)
  assert(odd[0].t == 0 && odd[1].t == 2 && odd[2].t == 4);

  std::vector<Trk> empty;
  assert(decimateTrack(empty) == 0);                        // empty stays empty
  printf("track decimation ok\n");
  return 0;
}
