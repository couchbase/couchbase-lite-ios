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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.0.15/couchbase-lite-swift_xc_community_3.0.15.zip",
            checksum: "414307a7c73f6d707c7e3677a3e3ccff965fae57049c3ab76b87e3358aa4e1db"
        )
    ]
)
