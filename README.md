# TouchDB #

by Jens Alfke (jens@couchbase.com)  
with contributions from Alexander Edge, Chris Kau, David Venable, Derek Clarkson, Fabien Franzen, fcandalija, J Chris Anderson, Marty Schoch, Mike Lamb, Paul Mietz Egli, Robin Lu  
and technical advice from Damien Katz and Filipe Manana

**TouchDB** is a lightweight [Apache CouchDB][1]-compatible database engine suitable for embedding into mobile or desktop apps. Think of it this way: If CouchDB is MySQL, then TouchDB is SQLite.

By "_CouchDB-compatible_" I mean that it can replicate with CouchDB, and that its data model and high-level design are "Couch-like" enough to make it familiar to CouchDB/Couchbase developers. Its REST API is nearly identical, though it doesn't support a few CouchDB features, like user accounts, that aren't useful in mobile apps. Its implementation is _not_ based on CouchDB's (it's not even written in Erlang.) It _does_ support replication to and from CouchDB.

By "_suitable for embedding into mobile apps_", I mean that it meets the following requirements:

 * Small code size; currently about 250kbytes. (Code size is important to mobile apps, which are often downloaded over cell networks.)
 * Quick startup time on relatively-slow CPUs; ideally 100ms or less.
 * Low memory usage with typical mobile data-sets. The expectation is the number of documents will not be huge, although there may be sizable multimedia attachments.
 * "Good enough" performance with these CPUs and data-sets.

And by "_mobile apps_" I'm focusing on iOS and [Android][11], although there's no reason we couldn't extend this to other platforms like Windows Phone. And it's not limited to mobile OSs -- the Objective-C implementation runs on Mac OS as well, and on Linux and other Unix-like OSs via [GNUstep][12].

## More Information

* There's lots more information on the [wiki][2].
* There's a "Grocery Sync" [demo app][18] for iOS, that implements a simple shared to-do list.
* Or if you want to ask questions or get help, join the [mailing list][17].

## Platforms ##

 * **Mac OS X** -- 10.7.2 or higher.
 * **iOS** -- 5.0 or higher.
 * **Linux, BSD, etc** -- Any platform [supported by][13] current [GNUstep][12] and libobjc2.
 * **MS Windows** -- As [supported by][13] GNUstep using MingW.
 * **Android / Java** -- Has its own source base and [repository][11].

## Requirements ##

 * It's written in Objective-C.
 * Xcode 4.4+ is required to build it (Clang 3.1+, with GNUstep).
 * Runtime system requirements for Apple platforms are iOS 5+, or Mac OS X 10.7.2+.

## License ##

 * TouchDB itself is under the Apache License 2.0.
 * [FMDB][5], by [Gus Mueller][8], is under the MIT License.
 * [Google Toolbox For Mac][10] is under the Apache License 2.0.
 * [CocoaHTTPServer][9], by Robbie Hanson, is under the BSD License.
 * [MYUtilities][6] (portions of which are copied into the vendor/MYUtilities directory) is under the BSD License. (But note that I, Jens, wrote MYUtilities and would have no problem re-licensing it under Apache for use here.)

## Development Status ##

TouchDB went beta in June 2012. The current stable release is beta 3, [version 0.92][16].

We don't have a formal schedule for 1.0, but expect the blessed event by the end of summer.

## Downloading TouchDB ##

* [Stable builds][16] (releases, betas and candidates)
* [Latest revisions][19] (built hourly after any commits. May not be stable; use at your own risk.)

## Building TouchDB ##

### On a Mac ###

(You might prefer to just [download][16] the latest stable release. But if you want to build it yourself...)

For full details see the [wiki page][7]. The basic steps are:

 1. Clone the TouchDB repository to your local disk.
 2. In that directory run "`git submodule init`" and then "`git submodule update`". This will clone the dependent library repos (such as [FMDB][5] and [MYUtilities][6]) into the vendor/ subdirectory.
 3. Open the Xcode project and build the "Mac Framework" and/or "iOS Framework" schemes.

### With GNUstep ###

Please refer to the files [BUILDING.txt][14] and [SETUP.txt][15] in the `GNUstep` directory.

[1]: http://couchdb.apache.org
[2]: https://github.com/couchbaselabs/TouchDB-iOS/wiki
[3]: http://couchbase.com
[4]: https://github.com/couchbaselabs/CouchCocoa
[5]: https://github.com/couchbaselabs/fmdb
[6]: https://bitbucket.org/snej/myutilities/overview
[7]: https://github.com/couchbaselabs/TouchDB-iOS/wiki/Building-TouchDB
[8]: https://github.com/ccgus/
[9]: https://github.com/robbiehanson/CocoaHTTPServer
[10]: http://code.google.com/p/google-toolbox-for-mac/
[11]: https://github.com/couchbaselabs/TouchDB-Android
[12]: http://www.gnustep.org/
[13]: http://wiki.gnustep.org/index.php/Platform_compatibility
[14]: https://github.com/couchbaselabs/TouchDB-iOS/blob/master/GNUstep/BUILDING.txt
[15]: https://github.com/couchbaselabs/TouchDB-iOS/blob/master/GNUstep/SETUP.txt
[16]: https://github.com/couchbaselabs/TouchDB-iOS/downloads
[17]: https://groups.google.com/forum/?fromgroups#!forum/mobile-couchbase
[18]: https://github.com/couchbaselabs/iOS-Couchbase-Demo
[19]: http://files.couchbase.com/developer-previews/mobile/ios/touchdb/
