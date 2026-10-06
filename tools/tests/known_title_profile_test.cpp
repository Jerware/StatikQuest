#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>

#include "core/known_title_profile.h"

using namespace Core::KnownTitle::Profiles;

void Check(bool condition, const char *what) {
  if (!condition) {
    std::cerr << "FAIL: " << what << '\n';
    std::exit(1);
  }
}

void Put(std::vector<u8> &image, u64 at, u64 value, u32 bytes) {
  Check(Contains(image, at, bytes), "fixture fits its buffer");
  std::memcpy(image.data() + at, &value, bytes);
}

void Populate(std::vector<u8> &image, const Profile &p) {
  std::memcpy(image.data() + p.recentre, RecentreCode.data(),
              RecentreCode.size());
  if (p.recentre == Known[1].recentre) {
    for (const auto &check : AlternateCode) {
      std::memcpy(image.data() + check.at, check.bytes.data(), check.size);
    }
  }
  Put(image, p.frame_rate, std::bit_cast<u64>(60.0), 8);
  Put(image, p.frame_seconds, std::bit_cast<u32>(1.0f / 60.0f), 4);
  Put(image, p.frame_microseconds, 16666, 8);
  for (u32 i = 0; i < ConsoleSizes.size(); ++i) {
    Put(image, p.widths + 4 * i, ConsoleSizes[i][0], 4);
    Put(image, p.heights + 4 * i, ConsoleSizes[i][1], 4);
    Put(image, p.pixels + 32 * i, u64{ConsoleSizes[i][0]} * ConsoleSizes[i][1],
        8);
  }
  for (const auto &c :
       ResolutionChanges(p, ConsoleSizes, ConsoleTargetPool, ConsoleSmallPool,
                         ConsoleGraphicsHeap)) {
    Put(image, c.at, c.was, c.bytes);
  }
}

void VerifyPatching(std::vector<u8> image, const Profile &p) {
  auto scaled = ConsoleSizes;
  for (u32 i = 3; i <= 6; ++i) {
    scaled[i][0] *= 2;
    scaled[i][1] *= 2;
  }
  const auto changes =
      ResolutionChanges(p, scaled, 0x37000000, 0x2c00000, 0x8f600000);
  u64 rejected{};
  for (const auto &c : changes) {
    image[c.at] ^= 1;
    Check(Detect(image, "CUSA12392") == nullptr,
          "every corrupt patch location rejects profile");
    const auto before = image;
    Check(!Apply(image, changes, rejected),
          "corrupt image rejects patch transaction");
    Check(rejected == c.at, "reports the mismatched destination");
    Check(image == before,
          "failed transaction writes no bytes, even with late mismatch");
    image[c.at] ^= 1;
  }
  Check(Apply(image, changes, rejected), "verified patch transaction succeeds");
  for (const auto &c : changes) {
    Check(Equals(image, c.at, c.now, c.bytes),
          "all related buffers and tables are scaled");
  }
  Check(Equals(image, p.widths + 24, 2880, 4), "2880 eye width applied");
  Check(Equals(image, p.heights + 24, 3072, 4), "3072 eye height applied");
  Check(Equals(image, p.widths + 8, 1920, 4), "TV resolution unchanged");
  const auto before = image;
  Check(!Apply(image, changes, rejected) && image == before,
        "a repeated application fails without modifying scaled data");
}

int main(int argc, char **argv) {
  for (const auto &p : Known) {
    std::vector<u8> image(0x3100000);
    Populate(image, p);
    Check(Detect(image, "CUSA12392") == &p, "selects the expected profile");
    Check(!Detect(image, "CUSA00000"), "different title is rejected");
    Check(!Detect(std::span{image}.first(p.recentre + 8), "CUSA12392"),
          "truncated signature rejected");
    Check(!Detect(std::span{image}.first(p.manager_pointer + 7), "CUSA12392"),
          "truncated pointer rejected");
    image[p.frame_seconds] ^= 1;
    Check(!Detect(image, "CUSA12392"), "unexpected time-step data rejected");
    image[p.frame_seconds] ^= 1;
    VerifyPatching(image, p);
    std::cout << "PASS fixture: " << p.name << '\n';
  }
  std::vector<u8> ambiguous(0x3100000);
  for (const auto &p : Known) {
    Populate(ambiguous, p);
  }
  Check(!Detect(ambiguous, "CUSA12392"), "ambiguous image rejected");
  Check(!Detect({}, "CUSA12392"), "empty image rejected");
  u64 rejected{};
  const std::array<Change, 1> outside{{{UINT64_MAX, 0, 1, 8}}};
  Check(!Apply(ambiguous, outside, rejected),
        "overflowing destination rejected");
  for (const auto &c : AlternateCode) {
    std::vector<u8> image(0x3100000);
    Populate(image, Known[1]);
    image[c.at] ^= 1;
    Check(!Detect(image, "CUSA12392"),
          "changed singleton/time getter rejected");
  }
  Check(argc <= 3, "at most two mapped images: original, alternate");
  for (int i = 1; i < argc; ++i) {
    std::ifstream file(argv[i], std::ios::binary);
    Check(file.good(), "local image opened");
    std::vector<u8> image((std::istreambuf_iterator<char>(file)), {});
    const auto *p = Detect(image, "CUSA12392");
    Check(p == &Known[i - 1], "actual local dump matches expected profile");
    VerifyPatching(image, *p);
    std::cout << "PASS actual local image: " << p->name << '\n';
  }
  std::cout << "PASS: profile selection, rejection guards and preflighted "
               "resolution patches\n";
}
