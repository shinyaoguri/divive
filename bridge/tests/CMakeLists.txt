add_executable(
    divive_probe_core_tests
    probe_core_tests.cpp
)

target_link_libraries(divive_probe_core_tests PRIVATE divive_probe_core)
target_compile_features(divive_probe_core_tests PRIVATE cxx_std_20)
divive_enable_warnings(divive_probe_core_tests)

add_test(NAME divive_probe_core_tests COMMAND divive_probe_core_tests)
