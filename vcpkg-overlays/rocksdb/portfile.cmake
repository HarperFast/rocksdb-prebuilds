# Set SOURCE_PATH to vcpkg's build tree and copy external source
set(SOURCE_PATH "${CURRENT_BUILDTREES_DIR}/src")

# Copy source from external directory into vcpkg's build tree
file(REMOVE_RECURSE "${SOURCE_PATH}")
file(COPY "$ENV{ROCKSDB_DIR}/" DESTINATION "${SOURCE_PATH}")

string(COMPARE EQUAL "${VCPKG_CRT_LINKAGE}" "dynamic" WITH_MD_LIBRARY)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" ROCKSDB_BUILD_SHARED)

# Build feature list conditionally based on platform
set(COMMON_FEATURES
    "snappy" WITH_SNAPPY
    "lz4" WITH_LZ4
    "zlib" WITH_ZLIB
    "zstd" WITH_ZSTD
    "bzip2" WITH_BZ2
    "tbb" WITH_TBB
)

if(VCPKG_TARGET_IS_LINUX)
  list(APPEND COMMON_FEATURES "liburing" WITH_LIBURING "numa" WITH_NUMA)
endif()

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
  FEATURES ${COMMON_FEATURES}
)

# Set platform-specific options
if(NOT VCPKG_TARGET_IS_LINUX)
  set(LINUX_ONLY_OPTIONS -DWITH_LIBURING=OFF -DWITH_NUMA=OFF)
else()
  set(LINUX_ONLY_OPTIONS)
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  OPTIONS
    -DWITH_GFLAGS=OFF
    -DWITH_TESTS=OFF
    -DWITH_BENCHMARK_TOOLS=OFF
    -DWITH_TOOLS=OFF
    -DUSE_RTTI=ON
    -DROCKSDB_INSTALL_ON_WINDOWS=ON
    -DFAIL_ON_WARNINGS=OFF
    -DWITH_MD_LIBRARY=${WITH_MD_LIBRARY}
    -DPORTABLE=1 # Minimum CPU arch to support, or 0 = current CPU, 1 = baseline CPU
    -DROCKSDB_BUILD_SHARED=${ROCKSDB_BUILD_SHARED}
    -DCMAKE_DISABLE_FIND_PACKAGE_Git=TRUE
    ${FEATURE_OPTIONS}
    ${LINUX_ONLY_OPTIONS}
  OPTIONS_DEBUG
    -DCMAKE_DEBUG_POSTFIX=d
    -DWITH_RUNTIME_DEBUG=ON
  OPTIONS_RELEASE
    -DWITH_RUNTIME_DEBUG=OFF
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/rocksdb)

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

vcpkg_fixup_pkgconfig()

vcpkg_install_copyright(COMMENT [[
RocksDB is dual-licensed under both the GPLv2 (found in COPYING)
and Apache 2.0 License (found in LICENSE.Apache). You may select,
at your option, one of the above-listed licenses.
]]
  FILE_LIST
    "${SOURCE_PATH}/LICENSE.leveldb"
    "${SOURCE_PATH}/LICENSE.Apache"
    "${SOURCE_PATH}/COPYING"
)