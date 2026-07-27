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

divive_enable_warnings(divive_probe_core)

if(DIVIVE_BUILD_PROTOCOL)
    find_package(Threads REQUIRED)

    add_library(
        divive_bridge_transport
        STATIC
        src/openvr_bridge_options.cpp
        src/openvr_pose_adapter.cpp
        src/pose_sender.cpp
        src/sender_options.cpp
        src/udp_publisher.cpp
        src/uuid.cpp
    )

    target_compile_features(divive_bridge_transport PUBLIC cxx_std_20)
    target_include_directories(
        divive_bridge_transport
        PUBLIC
            "${CMAKE_CURRENT_SOURCE_DIR}/include"
    )
    target_link_libraries(
        divive_bridge_transport
        PUBLIC
            divive_protocol
            Threads::Threads
    )
    if(WIN32)
        target_link_libraries(divive_bridge_transport PRIVATE ws2_32)
    endif()
    divive_enable_warnings(divive_bridge_transport)

    add_subdirectory(tools/send-test)
endif()

if(DIVIVE_BUILD_OPENVR_PROBE)
    if(NOT WIN32)
        message(FATAL_ERROR "OpenVR probeはWindows x86-64だけを対象とします")
    endif()
    add_subdirectory(probes/openvr)
    if(DIVIVE_BUILD_PROTOCOL)
        add_subdirectory(tools/openvr-bridge)
    endif()
endif()

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
