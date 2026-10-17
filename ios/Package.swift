// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoordinateInput",
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "CoordinateInput", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")], path: "SailingGPS", exclude: ["SailingGPSApp.swift", "NavigationMapView.swift", "Assets.xcassets", "WatchNavigationBridge.swift"], sources: ["CoordinateInput.swift", "WaypointArchive.swift", "MapLibrary.swift", "KmlArchive.swift"]),
        .target(name: "WatchNavigation", path: "Shared"),
        .testTarget(name: "CoordinateInputTests", dependencies: ["CoordinateInput", "WatchNavigation"], path: "Tests")
    ]
)
