file(REMOVE_RECURSE ${CMAKE_BINARY_DIR}/package)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/package)
file(COPY ${QGC_STAGING_BUNDLE_PATH} DESTINATION ${CMAKE_BINARY_DIR}/package)

get_filename_component(_staging_bundle_name "${QGC_STAGING_BUNDLE_PATH}" NAME)
if(NOT _staging_bundle_name STREQUAL "${TARGET_APP_NAME}.app")
    file(RENAME
        "${CMAKE_BINARY_DIR}/package/${_staging_bundle_name}"
        "${CMAKE_BINARY_DIR}/package/${TARGET_APP_NAME}.app"
    )
endif()

message(STATUS "Creating DMG: ${TARGET_APP_NAME}.dmg")
execute_process(
    COMMAND ${CREATE_DMG_PROGRAM} --volname "${TARGET_APP_NAME}" --filesystem "APFS" "${TARGET_APP_NAME}.dmg" "${CMAKE_BINARY_DIR}/package/"
    COMMAND_ERROR_IS_FATAL ANY
)
