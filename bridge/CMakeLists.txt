add_library(
    divive_probe_core
    STATIC
    src/json.cpp
    src/metrics.cpp
    src/model.cpp
    src/options.cpp
    src/pose_math.cpp
)

target_compile_features(divive_probe_core PUBLIC cxx_std_20)
target_include_directories(
    divive_probe_core
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

function(divive_enable_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
    else()
        target_compile_options(
            ${target}
            PRIVATE
                -Wall
                -Wextra
                -Wpedantic
                -Wconversion
                -Wsign-conversion
        )
    endif()
endfunction()

divive_enable_warnings(divive_probe_core)

if(DIVIVE_BUILD_OPENVR_PROBE)
    if(NOT WIN32)
        message(FATAL_ERROR "OpenVR probeはWindows x86-64だけを対象とします")
    endif()
    add_subdirectory(probes/openvr)
endif()

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
