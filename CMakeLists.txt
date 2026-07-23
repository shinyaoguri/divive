cmake_minimum_required(VERSION 3.24)

project(
    divive
    VERSION 0.1.0
    DESCRIPTION "VIVE Tracker cross-platform tracking infrastructure"
    LANGUAGES CXX
)

set(CMAKE_CXX_EXTENSIONS OFF)

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

include(CTest)
add_subdirectory(bridge)
