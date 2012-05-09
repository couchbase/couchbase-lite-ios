# TouchDB #

by Jens Alfke (jens@couchbase.com)  
with contributions from Alexander Edge, Chris Kau, J Chris Anderson, Marty Schoch, Paul Mietz Egli  
and technical advice from Damien Katz and Filipe Manana

**TouchDB** is a lightweight [Apache CouchDB][1]-compatible database engine suitable for embedding into mobile or desktop apps. Think of it this way: If CouchDB is MySQL, then TouchDB is SQLite.

By "_CouchDB-compatible_" I mean that it can replicate with CouchDB, and that its data model and high-level design are "Couch-like" enough to make it familiar to CouchDB/Couchbase developers. Its API will _not_ be identical and it may not support some CouchDB features (like user accounts) that aren't useful in mobile apps. Its implementation is _not_ based on CouchDB's (it's not even written in Erlang.) It _does_ support replication to and from CouchDB.

By "_suitable for embedding into mobile apps_", I mean that it meets the following requirements:

 * Small code size; currently about 250kbytes. (Code size is important to mobile apps, which are often downloaded over cell networks.)
 * Quick startup time on relatively-slow CPUs; ideally 100ms or less.
 * Low memory usage with typical mobile data-sets. The expectation is the number of documents will not be huge, although there may be sizable multimedia attachments.
 * "Good enough" performance with these CPUs and data-sets.

And by "_mobile apps_" I'm focusing on iOS and [Android][11], although there's no reason we couldn't extend this to other platforms like Windows Phone. And it's not limited to mobile OSs -- the Objective-C implementation runs on Mac OS as well, and on Linux and other Unix-like OSs via [GNUstep][12].

More documentation is available on the [wiki][2].

## Platforms ##

 * **Mac OS X** -- 10.7.2 or higher.
 * **iOS** -- 5.0 or higher.
 * **Linux, BSD, etc** -- Any platform [supported by][13] current [GNUstep][12] and libobjc2.
 * **MS Windows** -- As [supported by][13] GNUstep using MingW.
 * **Android / Java** -- Has its own source base and [repository][11].

## Requirements ##

 * It's written in Objective-C.
 * Xcode 4.3+ is required to build it (Clang 3.0+, with GNUstep).
 * Runtime system requirements for Apple platforms are iOS 5+, or Mac OS X 10.7.2+.

## License ##

 * TouchDB itself is under the Apache License 2.0.
 * [FMDB][5], by [Gus Mueller][8], is under the MIT License.
 * [Google Toolbox For Mac][10] is under the Apache License 2.0.
 * [CocoaHTTPServer][9], by Robbie Hanson, is under the BSD License.
 * [MYUtilities][6] (portions of which are copied into the vendor/MYUtilities directory) is under the BSD License. (But note that I, Jens, wrote MYUtilities and would have no problem re-licensing it under Apache for use here.)

## Development Status ##

TouchDB went alpha in January 201 with version 0.45.

Current versions (0.75 as of this writing) are close to being beta candidates.

Beta should arrive by summer.

## Building TouchDB ##

### On a Mac ###

For full details see the [wiki page][7]. The gist of it is:

 1. Clone the TouchDB repository to your local disk.
 2. In that directory run "`git submodule init`" and then "`git submodule update`". This will clone the [FMDB][5], [MYUtilities][6], and [CocoaHTTPServer][9] repos into the vendor/ subdirectory.
 3. Open the Xcode project and build the "Mac Framework" and/or "iOS Framework" schemes.

### With GNUstep ###

Please refer to the files [BUILDING.txt][14] and [SETUP.txt][15] in the `GNUstep` directory.

[1]: http://couchdb.apache.org
[2]: https://github.com/couchbaselabs/TouchDB-iOS/wiki
[3]: http://couchbase.com
[4]: https://github.com/couchbaselabs/CouchCocoa
[5]: https://github.com/touchbaselabs/fmdb
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
