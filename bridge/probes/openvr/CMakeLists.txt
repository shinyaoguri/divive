include(FetchContent)

# OpenVR SDK 2.15.6。tag移動の影響を避けるためcommit SHAへ固定する。
FetchContent_Declare(
    openvr_sdk
    GIT_REPOSITORY https://github.com/ValveSoftware/openvr.git
    GIT_TAG 0924064316de3effbcd1acf1e309182a2deb1c05
    GIT_SHALLOW FALSE
    SOURCE_SUBDIR _divive_no_cmake_project
)
FetchContent_MakeAvailable(openvr_sdk)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "divive-openvr-probeはWindows x86-64だけを対象とします")
endif()

add_library(divive_openvr_sdk SHARED IMPORTED GLOBAL)
set_target_properties(
    divive_openvr_sdk
    PROPERTIES
        IMPORTED_IMPLIB "${openvr_sdk_SOURCE_DIR}/lib/win64/openvr_api.lib"
        IMPORTED_LOCATION "${openvr_sdk_SOURCE_DIR}/bin/win64/openvr_api.dll"
        INTERFACE_INCLUDE_DIRECTORIES "${openvr_sdk_SOURCE_DIR}/headers"
)

add_executable(
    divive_openvr_probe
    main.cpp
    openvr_session.cpp
    openvr_session.hpp
)

set_target_properties(
    divive_openvr_probe
    PROPERTIES
        OUTPUT_NAME "divive-openvr-probe"
)

target_compile_features(divive_openvr_probe PRIVATE cxx_std_20)
target_link_libraries(
    divive_openvr_probe
    PRIVATE
        divive_probe_core
        divive_openvr_sdk
)
divive_enable_warnings(divive_openvr_probe)

add_custom_command(
    TARGET divive_openvr_probe
    POST_BUILD
    COMMAND
        "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:divive_openvr_sdk>"
        "$<TARGET_FILE_DIR:divive_openvr_probe>"
    VERBATIM
)

install(TARGETS divive_openvr_probe RUNTIME DESTINATION .)
install(
    FILES "${openvr_sdk_SOURCE_DIR}/bin/win64/openvr_api.dll"
    DESTINATION .
)
install(
    FILES "${openvr_sdk_SOURCE_DIR}/LICENSE"
    DESTINATION "licenses/openvr"
)
