# Development

## Supported development hosts

### macOS

主な日常開発環境です。

- Hub、Simulator、Recorder
- protocol/schema
- Unity/Web SDK
- C++のplatform-independent tests
- documentation

### Windows x86-64

hardware integrationと正式Bridge artifactの環境です。

- SteamVR/VIVE Hub
- OpenVR/OpenXR probes
- Bridge release build
- Tracker integration tests
- Windows packaging

MacからWindows artifactを生成できることより、Windows上のcanonical buildが再現することを優先します。

## Planned toolchains

### Bridge

- C++20
- supported MSVC
- CMake
- NinjaまたはVisual Studio generator
- vcpkg manifest mode
- OpenVR SDK pinned in repository or reproducible fetch

Candidate libraries:

- standalone Asio
- FlatBuffers
- spdlog
- Catch2

依存を追加するPRでは、ライセンス、version pin、更新方法を記録します。

### Hub

- current supported Xcode/Swift
- SwiftUI
- RealityKit
- Swift Package Manager
- SwiftNIO
- FlatBuffers Swift
- MCAP Swift

### SDKs

- Unityの対象versionはM2開始時にLTSを選定
- Unrealの対象versionはM3開始時に固定
- TypeScriptはNode LTSでbuild

engine versionを「最新」に追従し続けるのではなく、サポートmatrixを明示します。

## Repository boundaries

```text
protocol/       schema、generated code、golden vectors
bridge/         Windows executableとbackend
hub/            macOS appとSwift packages
sdk/            content clients
tools/          operator/developer tools
hardware-tests/ reproducible procedures and results
docs/           architecture and plans
```

generated codeは手編集しません。schema compiler versionを固定し、差分をreviewできる形で生成します。

## Coding rules

### Cross-language

- wire namesは英語の`snake_case`
- public conceptsはprotocol glossaryへ集約
- unit、axis、clock domainを型名またはfield名で明示
- IDをarray indexへ置き換えない
- unknown enum/fieldでprocessをcrashさせない

### C++

- RAII
- ownershipを型で明示
- capture hot pathで不要なallocationをしない
- exception boundaryをprocess/backend境界に置く
- raw OpenVR型をBridge内部から漏らさない

### Swift

- UI stateとnetwork stateを分離
- network event loopをblockingしない
- file I/OをMainActorで行わない
- `Data` copyの回数を計測してから最適化する

### SDK

- engine main threadへのevent dispatchを明示
- latest pose APIとevent APIを分離
- tracking lost時の既定挙動を文書化
- coordinate conversionをgolden testsで検証

## Test strategy

### Unit

- pose/quaternion conversion
- sequence wrap/order
- batch accounting
- tracker state machine
- profile persistence
- MCAP metadata
- interpolation

### Protocol conformance

同じgolden packetをC++、Swift、C#、TypeScriptで読みます。各実装が生成したpacketも他言語で読めることを確認します。

### Integration

- simulated Bridge → Hub
- Hub → Unity test scene
- Hub → Web client
- Recorder → Playback → same state
- runtime reconnect

### Fault

- loss
- duplicate
- out-of-order
- variable delay
- control disconnect
- truncated recording
- corrupt packet
- clock jump

### Hardware

[Hardware Validation](hardware-validation.md)に従います。通常CIと区別し、機材/runtime/firmwareを証跡へ含めます。

## Planned CI

| Job | Host | Scope |
| --- | --- | --- |
| docs | Linux | Markdown/local links |
| protocol | Linux/macOS/Windows | schema generation、golden vectors |
| bridge-unit | Windows + macOS | common code、Windows artifact |
| hub-unit | macOS | Swift packages |
| unity | supported Unity runner | package tests |
| web | Linux | TypeScript tests |
| unreal | Windows | plugin compile、後期導入 |
| hardware | self-hosted Windows | opt-in/manual |

hardware jobは通常PRで自動実行しません。機材の排他制御とruntime状態を管理できるようになってから導入します。

## Branch and review

- feature branchからPR
- protocol/architecture変更はDraft PRで早期共有
- hardware resultは証跡と結論を同じPRへ含める
- merge前に関連ADRとExit Criteriaを確認する
- unrelated generated filesやrecordingを混ぜない

## Configuration

設定の優先順位案:

```text
command line
  > environment variables for deployment
  > versioned config file
  > defaults
```

secretはconfig repositoryへcommitしません。profileとrole mappingはsecretではないものの、machine-local stateとportable exportを分離します。

## Logging

structured log fields:

- timestamp
- level
- component
- bridge/session/source ID
- tracker ID when relevant
- event code
- message

poseを通常ログへ毎frame出しません。必要時はMCAP recordingまたはsampling debug logを使います。

## Release

### Bridge

- Windows x86-64 artifact
- checksum
- bundled dependency inventory
- config example
- runtime compatibility notes

### Hub

- signed/notarized macOS app
- minimum macOS version
- profile migration notes
- SDK compatibility matrix

versioningは最初の外部利用前にSemVer方針を確定します。protocol、app、recording schemaのversionは独立して管理します。

## Documentation checks

初期段階はrelative linkとMarkdown構造をreviewします。実装scaffold追加時にmarkdownlintとlink checkerをCIへ導入し、外部リンクの一時的障害で開発全体を止めない設定にします。
