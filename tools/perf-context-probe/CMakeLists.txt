cmake_minimum_required(VERSION 3.20)
project(perf-context-probe CXX)

# RocksDB 11.8.1's installed headers require C++20 and the package exports no
# target_compile_features to say so.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(RocksDB CONFIG REQUIRED)

add_executable(perf-context-probe probe.cc)
target_link_libraries(perf-context-probe PRIVATE RocksDB::rocksdb)

# The archive ships one CMake package and it names the library at the historical lib/ path, so the
# other variant is selected by overriding the imported location alone — leaving the rest of the link
# line identical between the two probe builds, which is what makes their results comparable.
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
