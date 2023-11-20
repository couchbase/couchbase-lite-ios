// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.3/couchbase-lite-swift_xc_community_3.1.3.zip",
            checksum: "37191fbfe5319f1a3e18bb625891f940d2067d6c02bb18e0158cf0a95ab373cd"
        )
    ]
)
