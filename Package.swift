// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SideShift",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SideShift", targets: ["SideShift"]),
    ],
    targets: [
        .target(name: "SideShift", path: "Sources/SideShift", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "SideShiftTests", dependencies: ["SideShift"], path: "Tests/SideShiftTests"),
    ]
)
