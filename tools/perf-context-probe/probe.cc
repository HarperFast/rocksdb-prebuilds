// Decides which PerfContext variant a packaged RocksDB library is, by using it.
//
// Usage: perf-context-probe <enabled|disabled> <scratch dir>
//
// A symbol scan cannot run on the cross-compiled Windows targets and proves only that a name is
// absent; this asserts the consumer-visible behaviour that the name's absence is supposed to mean.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

#include "rocksdb/db.h"
#include "rocksdb/iterator.h"
#include "rocksdb/options.h"
#include "rocksdb/perf_context.h"
#include "rocksdb/perf_level.h"

namespace {

constexpr int kKeyCount = 2000;

std::string Key(int i) {
  char buf[32];
  std::snprintf(buf, sizeof(buf), "key%08d", i);
  return std::string(buf);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3 || (std::strcmp(argv[1], "enabled") != 0 &&
                    std::strcmp(argv[1], "disabled") != 0)) {
    std::fprintf(stderr, "usage: %s <enabled|disabled> <scratch dir>\n", argv[0]);
    return 2;
  }
  const bool expect_enabled = std::strcmp(argv[1], "enabled") == 0;

  rocksdb::Options options;
  options.create_if_missing = true;
  options.error_if_exists = true;

  std::unique_ptr<rocksdb::DB> db;
  rocksdb::Status status = rocksdb::DB::Open(options, argv[2], &db);
  if (!status.ok()) {
    std::fprintf(stderr, "DB::Open failed: %s\n", status.ToString().c_str());
    return 2;
  }

  for (int i = 0; i < kKeyCount; ++i) {
    status = db->Put(rocksdb::WriteOptions(), Key(i), "v");
    if (!status.ok()) {
      std::fprintf(stderr, "Put failed: %s\n", status.ToString().c_str());
      return 2;
    }
  }

  // Counting is off by default at kDisable, and a stale count would make the disabled case pass for
  // the wrong reason, so the window being measured starts from an explicit level and a reset.
  rocksdb::SetPerfLevel(rocksdb::PerfLevel::kEnableCount);
  rocksdb::get_perf_context()->Reset();

  // Memtable lookups and an iteration both compare user keys, so an instrumented build cannot leave
  // the counter at zero here.
  std::string value;
  for (int i = 0; i < kKeyCount; ++i) {
    status = db->Get(rocksdb::ReadOptions(), Key(i), &value);
    if (!status.ok()) {
      std::fprintf(stderr, "Get failed: %s\n", status.ToString().c_str());
      return 2;
    }
  }
  bool iterator_ok = false;
  {
    std::unique_ptr<rocksdb::Iterator> it(db->NewIterator(rocksdb::ReadOptions()));
    for (it->SeekToFirst(); it->Valid(); it->Next()) {
    }
    iterator_ok = it->status().ok();
  }

  const uint64_t comparisons = rocksdb::get_perf_context()->user_key_comparison_count;
  rocksdb::SetPerfLevel(rocksdb::PerfLevel::kDisable);

  if (!iterator_ok) {
    std::fprintf(stderr, "iteration failed\n");
    return 2;
  }

  std::printf("user_key_comparison_count=%llu (expected %s)\n",
              static_cast<unsigned long long>(comparisons),
              expect_enabled ? "> 0" : "== 0");

  if (expect_enabled && comparisons == 0) {
    std::fprintf(stderr, "PerfContext is compiled out of a library expected to have it enabled\n");
    return 1;
  }
  if (!expect_enabled && comparisons != 0) {
    std::fprintf(stderr, "PerfContext still records counters in a library expected to have it compiled out\n");
    return 1;
  }
  return 0;
}
