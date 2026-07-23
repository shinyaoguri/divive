include(FetchContent)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# compilerとruntimeを同じreleaseへ固定する。FlatBuffersはcalendar versioningを使う。
set(FLATBUFFERS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_INSTALL OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_FLATLIB OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_FLATC ON CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_FLATHASH OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_GRPCTEST OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_SHAREDLIB OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_ENABLE_PCH ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    divive_flatbuffers
    GIT_REPOSITORY https://github.com/google/flatbuffers.git
    GIT_TAG 03fffb25e2d777462b719cb4964249c30b19d58f
    GIT_SHALLOW FALSE
)
FetchContent_MakeAvailable(divive_flatbuffers)

set(DIVIVE_PROTOCOL_SCHEMA "${CMAKE_CURRENT_SOURCE_DIR}/schema/pose.fbs")
set(DIVIVE_PROTOCOL_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(
    DIVIVE_PROTOCOL_GENERATED_HEADER
    "${DIVIVE_PROTOCOL_GENERATED_DIR}/pose_generated.h"
)

add_custom_command(
    OUTPUT "${DIVIVE_PROTOCOL_GENERATED_HEADER}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${DIVIVE_PROTOCOL_GENERATED_DIR}"
    COMMAND
        "$<TARGET_FILE:flatc>"
        --cpp
        --scoped-enums
        --filename-suffix
        _generated
        -o
        "${DIVIVE_PROTOCOL_GENERATED_DIR}"
        "${DIVIVE_PROTOCOL_SCHEMA}"
    DEPENDS flatc "${DIVIVE_PROTOCOL_SCHEMA}"
    COMMENT "FlatBuffers C++ bindingを生成"
    VERBATIM
)

set(
    DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/generated/swift"
)
set(
    DIVIVE_PROTOCOL_SWIFT_GENERATED_SOURCE
    "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}/pose_generated.swift"
)
set(
    DIVIVE_PROTOCOL_SWIFT_COMMITTED_SOURCE
    "${CMAKE_SOURCE_DIR}/hub/Sources/HubProtocol/Generated/pose_generated.swift"
)
set(
    DIVIVE_PROTOCOL_SWIFT_NORMALIZER
    "${CMAKE_SOURCE_DIR}/scripts/normalize_generated_swift.py"
)

add_custom_command(
    OUTPUT "${DIVIVE_PROTOCOL_SWIFT_GENERATED_SOURCE}"
    COMMAND
        "${CMAKE_COMMAND}"
        -E
        make_directory
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}"
    COMMAND
        "$<TARGET_FILE:flatc>"
        --swift
        -o
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}"
        "${DIVIVE_PROTOCOL_SCHEMA}"
    COMMAND
        "${Python3_EXECUTABLE}"
        "${DIVIVE_PROTOCOL_SWIFT_NORMALIZER}"
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_SOURCE}"
    DEPENDS
        flatc
        "${DIVIVE_PROTOCOL_SCHEMA}"
        "${DIVIVE_PROTOCOL_SWIFT_NORMALIZER}"
    COMMENT "FlatBuffers Swift bindingを生成"
    VERBATIM
)

add_custom_target(
    divive_protocol_swift_codegen_check
    COMMAND
        "${CMAKE_COMMAND}"
        -E
        compare_files
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_SOURCE}"
        "${DIVIVE_PROTOCOL_SWIFT_COMMITTED_SOURCE}"
    DEPENDS "${DIVIVE_PROTOCOL_SWIFT_GENERATED_SOURCE}"
    COMMENT "commit済みSwift bindingの生成差分を検査"
    VERBATIM
)

add_library(
    divive_protocol
    STATIC
    "${DIVIVE_PROTOCOL_GENERATED_HEADER}"
    src/envelope.cpp
    src/frame_packetizer.cpp
    src/pose_codec.cpp
)

target_compile_features(divive_protocol PUBLIC cxx_std_20)
target_include_directories(
    divive_protocol
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE
        "${DIVIVE_PROTOCOL_GENERATED_DIR}"
)
target_link_libraries(divive_protocol PUBLIC FlatBuffers::FlatBuffers)
divive_enable_warnings(divive_protocol)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
