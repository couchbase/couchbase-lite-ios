// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v10), .macOS(.v10_12)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.0.0-beta02/couchbase-lite-swift_xc_community_3.0.0-beta02.zip",
            checksum: "ff2ff7ad9180e5916d08e47fa160fa35546c50b12fd6dd834e9e4f48a75a6575"
        )
    ]
)
