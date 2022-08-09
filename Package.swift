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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.0.2/couchbase-lite-swift_xc_community_3.0.2.zip",
            checksum: "59d93cbcbc498dfe34be87630464d42e2ccc13843a442412831717b50ebdb2c6"
        )
    ]
)
