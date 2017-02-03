
# Couchbase Lite 2.0

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine.

Couchbase Lite 2.0 has a completely new set of APIs. The implementation is on top of [Couchbase Lite Core](https://github.com/couchbase/couchbase-lite-core), which is also a new cross-platform implementation of database CRUD and query features, as well as document versioning.

THIS IS NOT A RELEASED PRODUCT. THIS IS NOT FINISHED CODE. This is currently in a very early stage of the implementation.


# Installation

### Cocoapods

Specify CouchbaseLite in the Podfile as follows:

```
target '<your target name>' do
  use_frameworks!
  pod 'CouchbaseLite', :git => 'https://github.com/couchbase/couchbase-lite-ios.git', :branch => 'feature/2.0', :submodules => true
end
```

### Carthage

Specify CouchbaseLite in the Cartfile as follows:

```
github "couchbase/couchbase-lite-ios" "feature/2.0"
```

# Credits

**Design, coding:** Jens Alfke (jens@couchbase.com), Pasin Suriyentrakorn,(pasin@couchbase.com), Jim Borden (jim.borden@couchbase.com)

# License

Like all Couchbase source code, this is released under the Apache 2 [license](LICENSE).
