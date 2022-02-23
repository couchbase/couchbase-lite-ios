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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.0.0/couchbase-lite-swift_xc_community_3.0.0.zip",
            checksum: "1c77f6f9e6eb41e19dec32fbae4463601196c5edca3ae2a164d81e311e57a8d1"
        )
    ]
)
