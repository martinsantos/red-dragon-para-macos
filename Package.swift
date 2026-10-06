// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "RedragonMac", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "RedragonMac", targets: ["RedragonMac"]),
    .executable(name: "s136ctl", targets: ["S136CLI"]),
    .executable(name: "protocol-checks", targets: ["ProtocolChecks"]),
  ],
  targets: [
    .target(name: "RedragonCore"),
    .executableTarget(name: "RedragonMac", dependencies: ["RedragonCore"]),
    .executableTarget(name: "S136CLI", dependencies: ["RedragonCore"]),
    .executableTarget(
      name: "ProtocolChecks", dependencies: ["RedragonCore"], path: "Tests/ProtocolChecks"),
  ])
