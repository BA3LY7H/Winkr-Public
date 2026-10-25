# mesh_audit -- cross-check a baked navmesh against its source collision.
# Links mmaps_common for VMAP + Detour, extractor_common for the DB2 layouts.

add_executable(mesh_audit)

CollectAndAddSourceFiles(
  mesh_audit
  ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(mesh_audit
  PRIVATE
    trinity-core-interface
    extractor_common
    mmaps_common)

target_include_directories(mesh_audit
  PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR})

set_target_properties(mesh_audit
  PROPERTIES
    COMPILE_WARNING_AS_ERROR ${WITH_WARNINGS_AS_ERRORS}
    FOLDER "tools")
