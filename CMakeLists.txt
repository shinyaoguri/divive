cmake_minimum_required(VERSION 3.24)

project(
    divive
    VERSION 0.1.0
    DESCRIPTION "VIVE Tracker cross-platform tracking infrastructure"
    LANGUAGES CXX
)

set(CMAKE_CXX_EXTENSIONS OFF)

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

if(WIN32)
    set(DIVIVE_OPENVR_DEFAULT ON)
else()
    set(DIVIVE_OPENVR_DEFAULT OFF)
endif()

option(
    DIVIVE_BUILD_OPENVR_PROBE
    "Windows向けOpenVR実機検証probeをbuildする"
    ${DIVIVE_OPENVR_DEFAULT}
)
option(DIVIVE_BUILD_PROTOCOL "共通wire protocolをbuildする" ON)

include(CTest)

if(DIVIVE_BUILD_PROTOCOL)
    add_subdirectory(protocol)
endif()

add_subdirectory(bridge)
