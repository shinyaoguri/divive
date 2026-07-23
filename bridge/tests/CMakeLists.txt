add_executable(
    divive_probe_core_tests
    probe_core_tests.cpp
)

target_link_libraries(divive_probe_core_tests PRIVATE divive_probe_core)
target_compile_features(divive_probe_core_tests PRIVATE cxx_std_20)
divive_enable_warnings(divive_probe_core_tests)

add_test(NAME divive_probe_core_tests COMMAND divive_probe_core_tests)

if(TARGET divive_bridge_transport)
    add_executable(
        divive_bridge_transport_tests
        bridge_transport_tests.cpp
    )

    target_link_libraries(
        divive_bridge_transport_tests
        PRIVATE
            divive_bridge_transport
            divive_protocol
    )
    if(WIN32)
        target_link_libraries(divive_bridge_transport_tests PRIVATE ws2_32)
    endif()
    target_compile_features(divive_bridge_transport_tests PRIVATE cxx_std_20)
    divive_enable_warnings(divive_bridge_transport_tests)

    add_test(NAME divive_bridge_transport_tests COMMAND divive_bridge_transport_tests)
endif()
