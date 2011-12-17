# TouchDB #

by Jens Alfke (jens@couchbase.com)

**TouchDB** is a lightweight [CouchDB][1]-compatible database engine suitable for embedding into mobile apps. Think of it this way: If CouchDB is MySQL, then TouchDB is SQLite.

By "_CouchDB-compatible_" I mean that it can replicate with CouchDB and [Couchbase Server][3], and that its data model and high-level design are "Couch-like" enough to make it familiar to CouchDB/Couchbase developers. Its API will _not_ be identical and it may not support some CouchDB features (like user accounts) that aren't useful in mobile apps. Its implementation is _not_ based on CouchDB's (it's not even written in Erlang.) It _does_ support replication to and from CouchDB.

By "_suitable for embedding into mobile apps_", I mean that it meets the following requirements:

 * Small code size; ideally less than 256kbytes. (Code size is important to mobile apps, which are often downloaded over cell networks.)
 * Quick startup time on relatively-slow CPUs; ideally 100ms or less.
 * Low memory usage with typical mobile data-sets. The expectation is the number of documents will not be huge, although there may be sizable multimedia attachments.
 * "Good enough" performance with these CPUs and data-sets.

And by "_mobile apps_" I'm focusing on iOS and Android, although there's no reason we couldn't extend this to other platforms like Windows Phone. And it's not limited to mobile OSs -- the initial Objective-C implementation runs on Mac OS as well.

More documentation is available on the [wiki][2].

## Requirements ##

 * It's written in Objective-C.
 * Xcode 4.2 is required to build it.
 * Runtime system requirements are iOS 5+, or Mac OS X 10.7.2+.

## License ##

 * TouchDB is under the Apache License 2.0.
 * [FMDB][5] is under the MIT License.
 * [MYUtilities][6] (portions of which are copied into the vendor/MYUtilities directory) is under the BSD License. (But note that I, Jens, wrote MYUtilities and would have no problem re-licensing it under Apache for use here.)

## Building TouchDB ##

 1. Clone the TouchDB repository to your local disk.
 2. In that directory run "`git submodule init`". This will clone the [FMDB][5] library (an Objective-C wrapper for sqlite) into vendor/FMDB.
 3. Open the Xcode project and build the "Mac Framework" and/or "iOS Framework" schemes.
 4. You should now have a "TouchDB.framework" in your build output directory.

### Building The Demo Apps ###

The demo apps use the CouchCocoa framework, which you'll need to check out and build separately:

 1. Clone the [CouchCocoa repository][4] to your local disk.
 2. Check out the "touchdb" branch.
 3. Open the Xcode project and build the appropriate scheme ("Mac Framework" and/or "iOS Framework").
 4. Copy or symlink the built "CouchCocoa.framework" into the "Frameworks" subdirectory of the appropriate TouchDB demo subdirectory.
 5. Now you can open the TouchDB Xcode project and build and run the demo app(s).

[1]: http://couchdb.apache.org
[2]: https://github.com/couchbaselabs/TouchDB-iOS/wiki
[3]: http://couchbase.com
[4]: https://github.com/couchbaselabs/CouchCocoa
[5]: https://github.com/ccgus/fmdb
[6]: https://bitbucket.org/snej/myutilities/overview
