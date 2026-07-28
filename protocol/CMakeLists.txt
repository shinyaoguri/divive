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
set(
    DIVIVE_STAGE_SCHEMA
    "${CMAKE_CURRENT_SOURCE_DIR}/schema/stage.fbs"
)
set(
    DIVIVE_STAGE_SUBSCRIPTION_SCHEMA
    "${CMAKE_CURRENT_SOURCE_DIR}/schema/stage_subscription.fbs"
)
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
    DIVIVE_PROTOCOL_SWIFT_COMMITTED_DIR
    "${CMAKE_SOURCE_DIR}/hub/Sources/HubProtocol/Generated"
)
set(
    DIVIVE_PROTOCOL_SWIFT_NORMALIZER
    "${CMAKE_SOURCE_DIR}/scripts/normalize_generated_swift.py"
)

# stage schemaはpose schemaをincludeし、flatcはinclude元のbindingも書き出す。
# schemaごとにcommandを分けると同じfileへ並行して書き込むため、1 commandでまとめる。
set(
    DIVIVE_PROTOCOL_SWIFT_STAMP
    "${CMAKE_CURRENT_BINARY_DIR}/generated/swift.stamp"
)

add_custom_command(
    OUTPUT "${DIVIVE_PROTOCOL_SWIFT_STAMP}"
    COMMAND
        "${CMAKE_COMMAND}"
        -E
        rm
        -rf
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}"
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
        "${DIVIVE_STAGE_SCHEMA}"
        "${DIVIVE_STAGE_SUBSCRIPTION_SCHEMA}"
    COMMAND
        "${Python3_EXECUTABLE}"
        "${DIVIVE_PROTOCOL_SWIFT_NORMALIZER}"
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}/pose_generated.swift"
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}/stage_generated.swift"
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}/stage_subscription_generated.swift"
    COMMAND "${CMAKE_COMMAND}" -E touch "${DIVIVE_PROTOCOL_SWIFT_STAMP}"
    DEPENDS
        flatc
        "${DIVIVE_PROTOCOL_SCHEMA}"
        "${DIVIVE_STAGE_SCHEMA}"
        "${DIVIVE_STAGE_SUBSCRIPTION_SCHEMA}"
        "${DIVIVE_PROTOCOL_SWIFT_NORMALIZER}"
    COMMENT "FlatBuffers Swift bindingを生成"
    VERBATIM
)

set(
    DIVIVE_GENERATED_BINDING_CHECKER
    "${CMAKE_SOURCE_DIR}/scripts/check_generated_bindings.py"
)

add_custom_target(
    divive_protocol_swift_codegen_check
    COMMAND
        "${Python3_EXECUTABLE}"
        "${DIVIVE_GENERATED_BINDING_CHECKER}"
        "${DIVIVE_PROTOCOL_SWIFT_GENERATED_DIR}"
        "${DIVIVE_PROTOCOL_SWIFT_COMMITTED_DIR}"
        --suffix
        .swift
    DEPENDS
        "${DIVIVE_PROTOCOL_SWIFT_STAMP}"
        "${DIVIVE_GENERATED_BINDING_CHECKER}"
    COMMENT "commit済みSwift bindingの生成差分を検査"
    VERBATIM
)

# Unity Packageへcommitする C# bindingも同じschemaから生成する。
# C#はincludeされたschemaを自動生成しないため、pose schemaも明示的に渡す。
set(
    DIVIVE_PROTOCOL_CSHARP_GENERATED_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/generated/csharp"
)
set(
    DIVIVE_PROTOCOL_CSHARP_COMMITTED_DIR
    "${CMAKE_SOURCE_DIR}/unity/com.divive.tracking/Runtime/Generated"
)
set(
    DIVIVE_PROTOCOL_CSHARP_STAMP
    "${CMAKE_CURRENT_BINARY_DIR}/generated/csharp.stamp"
)

add_custom_command(
    OUTPUT "${DIVIVE_PROTOCOL_CSHARP_STAMP}"
    COMMAND
        "${CMAKE_COMMAND}"
        -E
        rm
        -rf
        "${DIVIVE_PROTOCOL_CSHARP_GENERATED_DIR}"
    COMMAND
        "${CMAKE_COMMAND}"
        -E
        make_directory
        "${DIVIVE_PROTOCOL_CSHARP_GENERATED_DIR}"
    COMMAND
        "$<TARGET_FILE:flatc>"
        --csharp
        -o
        "${DIVIVE_PROTOCOL_CSHARP_GENERATED_DIR}"
        "${DIVIVE_PROTOCOL_SCHEMA}"
        "${DIVIVE_STAGE_SCHEMA}"
        "${DIVIVE_STAGE_SUBSCRIPTION_SCHEMA}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${DIVIVE_PROTOCOL_CSHARP_STAMP}"
    DEPENDS
        flatc
        "${DIVIVE_PROTOCOL_SCHEMA}"
        "${DIVIVE_STAGE_SCHEMA}"
        "${DIVIVE_STAGE_SUBSCRIPTION_SCHEMA}"
    COMMENT "FlatBuffers C# bindingを生成"
    VERBATIM
)

add_custom_target(
    divive_protocol_csharp_codegen_check
    COMMAND
        "${Python3_EXECUTABLE}"
        "${DIVIVE_GENERATED_BINDING_CHECKER}"
        "${DIVIVE_PROTOCOL_CSHARP_GENERATED_DIR}"
        "${DIVIVE_PROTOCOL_CSHARP_COMMITTED_DIR}"
        --suffix
        .cs
    DEPENDS
        "${DIVIVE_PROTOCOL_CSHARP_STAMP}"
        "${DIVIVE_GENERATED_BINDING_CHECKER}"
    COMMENT "commit済みC# bindingの生成差分を検査"
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
