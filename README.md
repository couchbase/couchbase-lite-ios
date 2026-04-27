
# Couchbase Lite for iOS and MacOS

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine.

Couchbase Lite implementation is on top of [Couchbase Lite Core](https://github.com/couchbase/couchbase-lite-core), which is also a new cross-platform implementation of database CRUD and query features, as well as document versioning.

## Requirements

- Xcode 26.4+
- iOS 15.0+
- macOS 13.0+

## Installation

### Swift Package 

#### Community Edition
```
dependencies: [
        .package(name: "CouchbaseLiteSwift",
                 url: "https://github.com/couchbase/couchbase-lite-swift.git", 
                 from: "4.0.0"),
    ],
```

#### Enterprise Edition

```
dependencies: [
        .package(name: "CouchbaseLiteSwift",
                 url: "https://github.com/couchbase/couchbase-lite-swift-ee.git", 
                 from: "4.0.0"),
    ],
```

More detailed information on how to setup is available here: [swift package manager](https://docs.couchbase.com/couchbase-lite/current/swift/start/swift-gs-install.html)

### CocoaPods

Swift Package Manager is the recommended installation method for new projects. [CocoaPods](https://cocoapods.org/) remains supported; add the pod that matches the API and edition you want to your [Podfile](https://guides.cocoapods.org/using/the-podfile.html):

| API         | Community Edition           | Enterprise Edition                     |
| ----------- | --------------------------- | -------------------------------------- |
| Objective-C | `CouchbaseLite`             | `CouchbaseLite-Enterprise`             |
| Swift       | `CouchbaseLite-Swift`       | `CouchbaseLite-Swift-Enterprise`       |

```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite-Swift'
end
```

## How to build the framework files

1. Clone the repo and update submodules

```
$ git clone https://github.com/couchbase/couchbase-lite-ios.git
$ cd couchbase-lite-ios
$ git submodule update --init --recursive
```

2. Run ./Scripts/build_xcframework.sh to build an XCFramework for either Swift or Objective-C API.
```
# For building the Swift XCFramework
$ ./Scripts/build_xcframework.sh -s CBL_Swift -o output

# For building the ObjC XCFramework
$ ./Scripts/build_xcframework.sh -s CBL_ObjC -o output
```

## Documentation

- [Swift](https://docs.couchbase.com/couchbase-lite/current/swift/quickstart.html)
- [Objective-C](https://docs.couchbase.com/couchbase-lite/current/objc/quickstart.html)

## License

Like all Couchbase source code, this is released under the Apache 2 [license](LICENSE).
