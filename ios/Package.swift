// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoordinateInput",
    targets: [
        .target(name: "CoordinateInput", path: "SailingGPS", exclude: ["SailingGPSApp.swift", "NavigationMapView.swift", "Assets.xcassets"], sources: ["CoordinateInput.swift"]),
        .testTarget(name: "CoordinateInputTests", dependencies: ["CoordinateInput"], path: "Tests")
    ]
)
