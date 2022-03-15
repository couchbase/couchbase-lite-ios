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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.0.1/couchbase-lite-swift_xc_community_3.0.1.zip",
            checksum: "972e3a440fe3388414c9aa0a81cbd242abd53b26085b5d110f9406ddfaa7097c"
        )
    ]
)
