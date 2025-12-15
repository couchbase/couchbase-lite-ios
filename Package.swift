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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.3.1/couchbase-lite-swift_xc_community_3.3.1.zip",
            checksum: "1dc441c4a816fe320d6714cd2781560550b56579d37211798116741c02c5b92b"
        )
    ]
)

