// swift-tools-version:5.8
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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.0/couchbase-lite-swift_xc_community_3.1.0.zip",
            checksum: "556d6ae41df3b5ebf91dbe45d38214dd7032f97ac1b132f925356d20e3b9ada5"
        )
    ]
)
