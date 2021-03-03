// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v9), .macOS(.v10_11)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/2.8.4/couchbase-lite-swift_xc_community_2.8.4.zip",
            checksum: "f0e2af71c6583e94a3be49296c3132d19c9b81fa744f34cccb6c3cff4ade778c"
        )
    ]
)
