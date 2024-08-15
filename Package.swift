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
            url: "https://packages.couchbase.com/releases/couchbase-lite-ios/3.1.9/couchbase-lite-swift_xc_community_3.1.9.zip",
            checksum: "26fb83bd3c417d094f44e87ff8876842619a126f9707c1d834476c680702facb"
        )
    ]
)
