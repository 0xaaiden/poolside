// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Poolside", platforms: [.macOS(.v14)], products: [.executable(name: "Poolside", targets: ["Poolside"])], targets: [
    .executableTarget(name: "Poolside", resources: [.copy("Resources/sample.json"), .copy("Resources/Icons")])
])
