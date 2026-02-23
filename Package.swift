// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v15), .macOS(.v13)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.3.2/couchbase-lite-swift_xc_community_3.3.2.zip",
            checksum: "eefb8205c2b19a95aea29c8071df2c631bf1b345c85ea6e2909d286f9cfa19da"
        )
    ]
)

