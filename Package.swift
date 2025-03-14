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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.2/couchbase-lite-swift_xc_community_3.2.2.zip",
            checksum: "1f80774c8ceeb63a18d1b778e1510ad32fb44092a40be6abfd6ad7d06791a3d0"
        )
    ]
)
