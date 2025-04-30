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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.3/couchbase-lite-swift_xc_community_3.2.3.zip",
            checksum: "ce4038c247fdebbf4e91bcba7de46a41f8aa22919614352456f7b655006bdbb7"
        )
    ]
)

