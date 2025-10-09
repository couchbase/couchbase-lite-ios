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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.3.0/couchbase-lite-swift_xc_community_3.3.0.zip",
            checksum: "933c16e353249bd40f8ff0b47c6496f863f0a33e5cd2de461dcd86c958b7c548"
        )
    ]
)

