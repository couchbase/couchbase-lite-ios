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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.6/couchbase-lite-swift_xc_community_3.1.6.zip",
            checksum: "749510257a61f41f1b1c6605d3025ed1d493ec5f6b236106b753202a6bf261d9"
        )

        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.6/couchbase-lite-swift_xc_enterprise_3.1.6.zip",
            checksum: "c5e870fa7ba491293bcf405d3da94b945d2c23aa63e683b4b61841435a9c332e"
        )
    ]
)
