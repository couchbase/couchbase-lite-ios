// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CouchbaseLiteSwift",
    platforms: [
        .iOS(.v9), .macOS(.v10_11)
    ],
    products: [
        .library(
            name: "CouchbaseLiteSwift",
            targets: ["CouchbaseLiteSwift"])
    ],
    targets: [
        .binaryTarget(
            name: "CouchbaseLiteSwift",
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/2.8.1/couchbase-lite-swift_xc_community_2.8.1.zip",
            checksum: "7d9d60960bb08fbcaa775dd0dc18e02115ff98d2a19682c29f38ed98d527d85f"
        )
    ]
)
