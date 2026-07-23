add_executable(
    divive_protocol_tests
    protocol_tests.cpp
)

target_link_libraries(divive_protocol_tests PRIVATE divive_protocol)
target_compile_features(divive_protocol_tests PRIVATE cxx_std_20)
target_include_directories(
    divive_protocol_tests
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_definitions(
    divive_protocol_tests
    PRIVATE
        DIVIVE_PROTOCOL_GOLDEN_HEX_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../golden/pose_v1.packet.hex"
)
divive_enable_warnings(divive_protocol_tests)

add_executable(
    divive_protocol_golden_tool
    golden_tool.cpp
)

target_link_libraries(divive_protocol_golden_tool PRIVATE divive_protocol)
target_compile_features(divive_protocol_golden_tool PRIVATE cxx_std_20)
target_include_directories(
    divive_protocol_golden_tool
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
)
divive_enable_warnings(divive_protocol_golden_tool)

add_test(NAME divive_protocol_tests COMMAND divive_protocol_tests)
