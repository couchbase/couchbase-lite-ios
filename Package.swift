// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v12), .macOS(.v12)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.6/couchbase-lite-swift_xc_community_3.2.6.zip",
            checksum: "0ca79b63adf58e2d4c51552c9fbc0ff6ff3c822d5ca635cf05bc18435fb6516b"
        )
    ]
)

