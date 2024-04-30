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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.2.0-beta.2/couchbase-lite-swift_xc_community_3.2.0-beta.2.zip",
            checksum: "c3d8401ac61af19ad82462e50161824a43089f05dcfc36f59052811ce7b8f6dd"
        )
    ]
)

