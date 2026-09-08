// SPDX-License-Identifier: GPL-3.0-or-later
#include <cstdlib>
#include <iostream>
#include <map>
#include <string>

namespace rime::grammar {
std::string encode(const char* begin, const char* end);
}

static std::string Utf8(unsigned u) {
  std::string out;
  if (u < 0x80) out += char(u);
  else if (u < 0x800) {
    out += char(0xc0 | (u >> 6)); out += char(0x80 | (u & 63));
  } else if (u < 0x10000) {
    out += char(0xe0 | (u >> 12)); out += char(0x80 | ((u >> 6) & 63));
    out += char(0x80 | (u & 63));
  } else {
    out += char(0xf0 | (u >> 18)); out += char(0x80 | ((u >> 12) & 63));
    out += char(0x80 | ((u >> 6) & 63)); out += char(0x80 | (u & 63));
  }
  return out;
}

int main() {
  // Exercise the actual linked plugin, not a copied implementation. The old
  // loop repeated its first 7-bit group for characters outside U+4000..9FFF.
  std::map<std::string, unsigned> keys;
  for (unsigned u : {0u, 0x7fu, 0x80u, 0x81u, 0x7ffu, 0x800u, 0x801u,
                     0x3400u, 0x3401u, 0x3fffu, 0x4000u, 0x4f60u, 0x597du,
                     0x9fffu, 0xa000u, 0xa001u, 0xffffu, 0x10000u, 0x10001u,
                     0x1f600u, 0x1f601u, 0x20000u, 0x20001u, 0x10ffffu}) {
    const auto text = Utf8(u);
    const auto encoded = rime::grammar::encode(text.data(), text.data() + text.size());
    if (encoded.empty() || !keys.emplace(encoded, u).second) {
      std::cerr << "grammar encoding collision at U+" << std::hex << u << '\n';
      return 1;
    }
  }
  const std::string ordinary = "你好";
  if (rime::grammar::encode(ordinary.data(), ordinary.data() + ordinary.size()) !=
      std::string("\x8f\x60\x99\x7d", 4)) {
    std::cerr << "ordinary Chinese model keys changed\n";
    return 1;
  }
  std::cout << "ZIME grammar encoding: PASS (24 Unicode boundaries; ordinary Chinese keys preserved)\n";
}
