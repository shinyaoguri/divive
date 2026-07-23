// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "DiviveHub",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "HubProtocol", targets: ["HubProtocol"]),
    .library(name: "HubNetworking", targets: ["HubNetworking"]),
    .library(name: "HubCore", targets: ["HubCore"]),
    .library(name: "HubSimulator", targets: ["HubSimulator"]),
    .executable(name: "divive-receiver", targets: ["DiviveReceiver"]),
    .executable(name: "divive-simulator", targets: ["DiviveSimulator"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/google/flatbuffers.git",
      revision: "03fffb25e2d777462b719cb4964249c30b19d58f"
    ),
    .package(
      url: "https://github.com/apple/swift-nio.git",
      exact: "2.101.3"
    ),
  ],
  targets: [
    .target(
      name: "HubProtocol",
      dependencies: [
        .product(name: "FlatBuffers", package: "flatbuffers")
      ]
    ),
    .target(
      name: "HubNetworking",
      dependencies: [
        "HubProtocol",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
    .target(
      name: "HubCore",
      dependencies: ["HubProtocol"]
    ),
    .target(
      name: "HubSimulator",
      dependencies: ["HubCore", "HubProtocol"]
    ),
    .executableTarget(
      name: "DiviveReceiver",
      dependencies: ["HubCore", "HubNetworking", "HubProtocol"]
    ),
    .executableTarget(
      name: "DiviveSimulator",
      dependencies: ["HubCore", "HubProtocol", "HubSimulator"]
    ),
    .testTarget(
      name: "HubProtocolTests",
      dependencies: ["HubProtocol"]
    ),
    .testTarget(
      name: "HubNetworkingTests",
      dependencies: [
        "HubCore",
        "HubNetworking",
        "HubProtocol",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
    .testTarget(
      name: "HubCoreTests",
      dependencies: ["HubCore", "HubProtocol"]
    ),
    .testTarget(
      name: "HubSimulatorTests",
      dependencies: ["HubCore", "HubProtocol", "HubSimulator"]
    ),
  ]
)
