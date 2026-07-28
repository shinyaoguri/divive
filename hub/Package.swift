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
    .library(name: "HubCalibration", targets: ["HubCalibration"]),
    .library(name: "HubSimulator", targets: ["HubSimulator"]),
    .library(name: "HubDistribution", targets: ["HubDistribution"]),
    .library(name: "HubAppUI", targets: ["HubAppUI"]),
    .executable(name: "divive-receiver", targets: ["DiviveReceiver"]),
    .executable(name: "divive-simulator", targets: ["DiviveSimulator"]),
    .executable(name: "divive-hub-app", targets: ["DiviveHubApp"]),
    .executable(name: "divive-stage-golden", targets: ["DiviveStageGolden"]),
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
      name: "HubCalibration",
      dependencies: ["HubCore", "HubProtocol"]
    ),
    .target(
      name: "HubSimulator",
      dependencies: ["HubCore", "HubProtocol"]
    ),
    .target(
      name: "HubDistribution",
      dependencies: [
        "HubCalibration",
        "HubCore",
        "HubProtocol",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
    .target(
      name: "HubAppUI",
      dependencies: [
        "HubCalibration",
        "HubCore",
        "HubNetworking",
        "HubProtocol",
        "HubSimulator",
      ]
    ),
    .executableTarget(
      name: "DiviveReceiver",
      dependencies: ["HubCore", "HubNetworking", "HubProtocol"]
    ),
    .executableTarget(
      name: "DiviveSimulator",
      dependencies: [
        "HubCalibration",
        "HubCore",
        "HubDistribution",
        "HubProtocol",
        "HubSimulator",
      ]
    ),
    .executableTarget(
      name: "DiviveHubApp",
      dependencies: ["HubAppUI"]
    ),
    .executableTarget(
      name: "DiviveStageGolden",
      dependencies: ["HubProtocol"]
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
      name: "HubCalibrationTests",
      dependencies: ["HubCalibration", "HubCore", "HubProtocol"]
    ),
    .testTarget(
      name: "HubSimulatorTests",
      dependencies: ["HubCore", "HubProtocol", "HubSimulator"]
    ),
    .testTarget(
      name: "HubDistributionTests",
      dependencies: [
        "HubCalibration",
        "HubCore",
        "HubDistribution",
        "HubProtocol",
        "HubSimulator",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
    .testTarget(
      name: "HubAppUITests",
      dependencies: [
        "HubAppUI",
        "HubCalibration",
        "HubCore",
        "HubNetworking",
        "HubProtocol",
        "HubSimulator",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
  ]
)
