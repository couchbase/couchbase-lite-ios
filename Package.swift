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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.10/couchbase-lite-swift_xc_community_3.1.10.zip",
            checksum: "3005b52f55eb6426cdec361a1ffbaeab592f5eb1aeb81a66377ed9ab1a87dcbb"
        )
    ]
)
