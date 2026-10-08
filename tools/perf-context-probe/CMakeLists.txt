cmake_minimum_required(VERSION 3.20)
project(perf-context-probe CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Resolved from the extracted archive, so the probe links what consumers download rather than a
# build tree, and picks up the same dependency libraries the packaged CMake config names.
find_package(RocksDB CONFIG REQUIRED)

add_executable(perf-context-probe probe.cc)
target_link_libraries(perf-context-probe PRIVATE RocksDB::rocksdb)

# The archive ships one CMake package, describing the library at the historical lib/ path. Pointing
# the imported target at the other variant's file is how a consumer selects it, and keeps the rest
# of the link line byte-identical between the two probe builds.
if(ROCKSDB_LIBRARY_OVERRIDE)
  if(NOT EXISTS "${ROCKSDB_LIBRARY_OVERRIDE}")
    message(FATAL_ERROR "ROCKSDB_LIBRARY_OVERRIDE does not exist: ${ROCKSDB_LIBRARY_OVERRIDE}")
  endif()
  set_target_properties(RocksDB::rocksdb PROPERTIES
    IMPORTED_LOCATION "${ROCKSDB_LIBRARY_OVERRIDE}"
    IMPORTED_LOCATION_RELEASE "${ROCKSDB_LIBRARY_OVERRIDE}"
    IMPORTED_LOCATION_DEBUG "${ROCKSDB_LIBRARY_OVERRIDE}"
    IMPORTED_LOCATION_RELWITHDEBINFO "${ROCKSDB_LIBRARY_OVERRIDE}"
    IMPORTED_LOCATION_MINSIZEREL "${ROCKSDB_LIBRARY_OVERRIDE}")
endif()
