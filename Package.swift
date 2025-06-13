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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.4/couchbase-lite-swift_xc_community_3.2.4.zip",
            checksum: "75a196d24cd573643aaf2dfdfa890610cf6064ab4e92517ec735cb09a9c3c104"
        )
    ]
)

