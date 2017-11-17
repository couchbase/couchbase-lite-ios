
# Couchbase Lite 2.0 (Developer Build)

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine.

Couchbase Lite 2.0 has a completely new set of APIs. The implementation is on top of [Couchbase Lite Core](https://github.com/couchbase/couchbase-lite-core), which is also a new cross-platform implementation of database CRUD and query features, as well as document versioning.

THIS IS NOT A RELEASED PRODUCT. THIS IS NOT FINISHED CODE. This is currently in a very early stage of the implementation.


## Requirements
- iOS 8.0+ | macOS 10.10+ | tvOS 9.0+
- Xcode 8


## Installation

### CocoaPods

You can use [CocoaPods](https://cocoapods.org/) to install `CouchbaseLite` for Objective-C API or `CouchbaseLiteSwift` for Swift API by adding it in your [Podfile](https://guides.cocoapods.org/using/the-podfile.html):

#### CouchbaseLite (Objective-C API)
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite', :git => 'https://github.com/couchbase/couchbase-lite-ios.git', :tag => '2.0DB020', :submodules => true
end
```

#### CouchbaseLiteSwift (Swift API)
```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLiteSwift', :git => 'https://github.com/couchbase/couchbase-lite-ios.git', :tag => '2.0DB020', :submodules => true
end
```

### Carthage

You can use [Carthage](https://github.com/Carthage/Carthage) to install `CouchbaseLite` by adding it in your [Cartfile](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#cartfile):

```
github "couchbase/couchbase-lite-ios" "2.0DB020"
```

> When running `carthage update or build`, Carthage will build both CouchbaseLite and CouchbaseLiteSwift framework.

## How to build the framework files.

1. Clone the repo and update submodules

```
$ git clone https://github.com/couchbase/couchbase-lite-ios.git
$ git checkout feature/2.0
$ git submodule update --init --recursive
$ cd couchbase-lite-ios
```

2. Run ./Scripts/build_framework.sh to build a platform framework which could be either an Objective-C or a Swift framework. The supported platforms include iOS, tvOS, and macOS.

```
$ ./Scripts/build_framework.sh -s "CBL ObjC" -p iOS -o output    // For building the ObjC framework for iOS
$ ./Scripts/build_framework.sh -s "CBL Swift" -p iOS -o output   // For building the Swift framework for iOS
```

## Sample Apps

- [Todo](https://github.com/couchbaselabs/mobile-training-todo/tree/feature/2.0) : Objective-C and Swift


## License

Like all Couchbase source code, this is released under the Apache 2 [license](LICENSE).
