// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v9), .macOS(.v10_11), .tvOS(.v9)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/2.8.0/couchbase-lite-swift_xc_community_2.8.0.zip",
            checksum: "8acca88ce094967839ed3ae22d9eddc858598853b2a6d9a15d30a915d3c6ddbe"
        )
    ]
)
