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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.0-beta.1/couchbase-lite-swift_xc_community_3.2.0-beta.1.zip",
            checksum: "39dd4d80a8edb6eb87a2f5ae91753b16064c04c6c74f10f7ef2707902efe14c4"
        )
    ]
)

