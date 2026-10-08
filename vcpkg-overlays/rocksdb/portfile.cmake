# Set SOURCE_PATH to vcpkg's build tree and copy external source
set(SOURCE_PATH "${CURRENT_BUILDTREES_DIR}/src")

message(STATUS "===========================================================")
message(STATUS "SOURCE_PATH     = ${SOURCE_PATH}")
message(STATUS "ROCKSDB_DIR     = $ENV{ROCKSDB_DIR}")
message(STATUS "REAL_VCPKG_ROOT = $ENV{REAL_VCPKG_ROOT}")
message(STATUS "VCPKG_ROOT      = $ENV{VCPKG_ROOT}")
message(STATUS "VCPKG_TRIPLET   = $ENV{VCPKG_TRIPLET}")
message(STATUS "===========================================================")

if(NOT "$ENV{REAL_VCPKG_ROOT}" STREQUAL "$ENV{VCPKG_ROOT}")
  message(WARNING "VCPKG_ROOT is pointing to wrong vcpkg!")
endif()

if(NOT DEFINED ENV{ROCKSDB_DIR})
  message(FATAL_ERROR "ROCKSDB_DIR is not defined!")
elseif("$ENV{ROCKSDB_DIR}" STREQUAL "")
  message(FATAL_ERROR "ROCKSDB_DIR is empty!")
endif()

# Copy source from external directory into vcpkg's build tree
file(REMOVE_RECURSE "${SOURCE_PATH}")
message(STATUS "Copying $ENV{ROCKSDB_DIR}/ to ${SOURCE_PATH}")
file(COPY "$ENV{ROCKSDB_DIR}/" DESTINATION "${SOURCE_PATH}")

string(COMPARE EQUAL "${VCPKG_CRT_LINKAGE}" "dynamic" WITH_MD_LIBRARY)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" ROCKSDB_BUILD_SHARED)

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
  FEATURES
    "liburing" WITH_LIBURING
    "snappy" WITH_SNAPPY
    "lz4" WITH_LZ4
    "zlib" WITH_ZLIB
    "zstd" WITH_ZSTD
    "bzip2" WITH_BZ2
    "numa" WITH_NUMA
  INVERTED_FEATURES
    "no-perf-context" WITH_PERF_CONTEXT
)

# A release ships both variants from this one portfile; losing a compression feature on either
# install would publish a pair that is not configuration-identical.
foreach(compression_option IN ITEMS WITH_SNAPPY WITH_LZ4 WITH_ZLIB WITH_ZSTD WITH_BZ2)
  if(NOT "-D${compression_option}=ON" IN_LIST FEATURE_OPTIONS)
    message(FATAL_ERROR "${compression_option} is not ON; every rocksdb-prebuilds library ships all five compression libraries")
  endif()
endforeach()

message(STATUS "Configuring RocksDB...")
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
  OPTIONS_DEBUG
    -DCMAKE_DEBUG_POSTFIX=d
    -DWITH_RUNTIME_DEBUG=ON
  OPTIONS_RELEASE
    -DWITH_RUNTIME_DEBUG=OFF
)

# vcpkg only warns when a -D names a variable the project never declared, so an upstream rename of
# WITH_PERF_CONTEXT would otherwise flip the variant silently.
set(release_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(GLOB_RECURSE build_system_files
  "${release_build_dir}/build.ninja"
  "${release_build_dir}/*/flags.make"
  "${release_build_dir}/*.vcxproj"
)
if(NOT build_system_files)
  message(FATAL_ERROR "No generated build system found under ${release_build_dir} to check NPERF_CONTEXT against")
endif()
set(nperf_context_defined FALSE)
foreach(build_system_file IN LISTS build_system_files)
  file(STRINGS "${build_system_file}" nperf_context_lines LIMIT_COUNT 1
    REGEX "[-/]D *NPERF_CONTEXT|PreprocessorDefinitions.*NPERF_CONTEXT")
  if(nperf_context_lines)
    set(nperf_context_defined TRUE)
    break()
  endif()
endforeach()
if(WITH_PERF_CONTEXT AND nperf_context_defined)
  message(FATAL_ERROR "NPERF_CONTEXT is defined in ${release_build_dir}, but this is the PerfContext-enabled variant")
elseif(NOT WITH_PERF_CONTEXT AND NOT nperf_context_defined)
  message(FATAL_ERROR "WITH_PERF_CONTEXT=OFF did not define NPERF_CONTEXT in ${release_build_dir}")
endif()
message(STATUS "PerfContext variant: WITH_PERF_CONTEXT=${WITH_PERF_CONTEXT}, NPERF_CONTEXT defined=${nperf_context_defined}")

message(STATUS "Building and installing RocksDB...")
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
