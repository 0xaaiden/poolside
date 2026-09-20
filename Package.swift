// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LumaLP", platforms: [.macOS(.v14)], products: [.executable(name: "LumaLP", targets: ["LumaLP"])], targets: [
    .executableTarget(name: "LumaLP", resources: [.copy("Resources/sample.json"), .copy("Resources/Icons")])
])
