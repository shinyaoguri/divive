add_executable(
    divive_bridge_send_test
    main.cpp
)

set_target_properties(
    divive_bridge_send_test
    PROPERTIES
        OUTPUT_NAME "divive-bridge-send-test"
)

target_compile_features(divive_bridge_send_test PRIVATE cxx_std_20)
target_link_libraries(
    divive_bridge_send_test
    PRIVATE
        divive_bridge_transport
        divive_protocol
)
divive_enable_warnings(divive_bridge_send_test)

install(TARGETS divive_bridge_send_test RUNTIME DESTINATION .)
