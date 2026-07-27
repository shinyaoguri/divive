add_executable(divive_openvr_bridge main.cpp)

set_target_properties(
    divive_openvr_bridge
    PROPERTIES
        OUTPUT_NAME "divive-openvr-bridge"
)

target_compile_features(divive_openvr_bridge PRIVATE cxx_std_20)
target_link_libraries(
    divive_openvr_bridge
    PRIVATE
        divive_bridge_transport
        divive_openvr_backend
)
divive_enable_warnings(divive_openvr_bridge)

add_custom_command(
    TARGET divive_openvr_bridge
    POST_BUILD
    COMMAND
        "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:divive_openvr_sdk>"
        "$<TARGET_FILE_DIR:divive_openvr_bridge>"
    VERBATIM
)

install(TARGETS divive_openvr_bridge RUNTIME DESTINATION .)
