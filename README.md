
# Couchbase Lite for iOS and MacOS

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Build Status](https://travis-ci.org/couchbase/couchbase-lite-ios.svg?branch=master)](https://travis-ci.org/couchbase/couchbase-lite-ios) [![Coverage Status](https://coveralls.io/repos/github/couchbase/couchbase-lite-ios/badge.svg?branch=master)](https://coveralls.io/github/couchbase/couchbase-lite-ios?branch=master)

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine.

Couchbase Lite 2.x has a completely new set of APIs. The implementation is on top of [Couchbase Lite Core](https://github.com/couchbase/couchbase-lite-core), which is also a new cross-platform implementation of database CRUD and query features, as well as document versioning.


## Requirements
- iOS 9.0+ | macOS 10.11+
- Xcode 10.0


## Installation

### Swift Package 

#### Requirements:
- XCode 12+

##### Community Edition
```
dependencies: [
        .package(name: "CouchbaseLiteSwift",
                 url: "https://github.com/couchbase/couchbase-lite-ios.git", 
                 from: "2.8.0"),
    ],
```

##### Enterprise Edition

```
dependencies: [
        .package(name: "CouchbaseLiteSwift",
                 url: "https://github.com/couchbase/couchbase-lite-swift-ee.git", 
                 from: "2.8.0"),
    ],
```

More detailed information on how to setup is available here: [swift package manager](https://docs.couchbase.com/couchbase-lite/current/swift/start/swift-gs-install.html)

### CocoaPods

You can use [CocoaPods](https://cocoapods.org/) to install `CouchbaseLite` for Objective-C API or `CouchbaseLiteSwift` for Swift API by adding it in your [Podfile](https://guides.cocoapods.org/using/the-podfile.html):

#### Objective-C

##### Community Edition
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite'
end
```

##### Enterprise Edition
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite-Enterprise'
end
```

#### Swift

##### Community Edition
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite-Swift'
end
```

##### Enterprise Edition
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite-Swift-Enterprise'
end
```

### Carthage

You can use [Carthage](https://github.com/Carthage/Carthage) to install `CouchbaseLite` by adding it in your [Cartfile](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#cartfile):

##### Community Edition
```
binary "https://packages.couchbase.com/releases/couchbase-lite-ios/carthage/CouchbaseLite-Community.json"
```

##### Enterprise Edition
```
binary "https://packages.couchbase.com/releases/couchbase-lite-ios/carthage/CouchbaseLite-Enterprise.json"
```

> When running `carthage update or build`, Carthage will build both CouchbaseLite and CouchbaseLiteSwift framework.

## How to build the framework files.

1. Clone the repo and update submodules

```
$ git clone https://github.com/couchbase/couchbase-lite-ios.git
$ cd couchbase-lite-ios
$ git submodule update --init --recursive
```

2. If not already installed, install _doxygen_, `brew install doxygen`

3. Run ./Scripts/build_framework.sh to build a platform framework which could be either an Objective-C or a Swift framework. The supported platforms include iOS, tvOS, and macOS.

```
$ ./Scripts/build_framework.sh -s "CBL ObjC" -p iOS -o output    // For building the ObjC framework for iOS
$ ./Scripts/build_framework.sh -s "CBL Swift" -p iOS -o output   // For building the Swift framework for iOS
```

## Documentation

- [Swift](https://docs.couchbase.com/couchbase-lite/2.6/swift.html)
- [Objective-C](https://docs.couchbase.com/couchbase-lite/2.6/objc.html)

## Sample Apps

- [Todo](https://github.com/couchbaselabs/mobile-training-todo/tree/feature/2.5) : Objective-C and Swift


## License

Like all Couchbase source code, this is released under the Apache 2 [license](LICENSE).
