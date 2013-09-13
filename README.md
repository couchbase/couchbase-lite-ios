# Couchbase Lite 

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine. 

Get more info and downloads of Couchbase Lite (for iOS and Android) via [the Couchbase mobile portal](http://mobile.couchbase.com)

Latency matters a lot to users so a local database takes frustration out of the equation. It’s got JSON documents, and the same map reduce as Couchbase Server, in a pint-sized edition.

Native code for iOS and Android. Less than 1 MB optimized for quick launch and snappy user experience on occasionally connected devices when data matters.

**Lightweight** means:

* Embedded: The database engine is a library linked into the app, not a separate server process.
* Small code size: currently under 400kbytes. This is important to mobile apps, which are often downloaded over cell networks.
* Quick startup time on relatively-slow CPUs: currently under 50ms on recent iPhones.
* Low memory usage with typical mobile data-sets. The expectation is the number of documents will not be huge, although there may be sizable multimedia attachments.
* "Good enough" performance with these CPUs and data-sets. (Exact figures depend on your data and application, of course.)

**Document-oriented** means:

* Like Couchbase Server, it stores records in flexible [JSON](http://json.org) format instead of requiring predefined schemas or normalization.
* Records/documents can have arbitrary-sized binary attachments, like multimedia content.
* Your application's data format can evolve over time without any need for explicit migrations.
* Map/reduce indexing allows fast lookups without needing to use special query languages.

**[Syncable](http://syncable.org/)** means:

* Any two copies of a database can be brought into sync via an efficient, reliable, proven REST-based [protocol][23].
* Sync can be on-demand or continuous (with a latency of a few seconds).
* The sync engine supports intermittent and unreliable network connections.
* Conflicts can be detected and resolved, with app logic in full control of merging.
* Revision trees allow for complex replication topologies, including server-to-server (for multiple data centers) and peer-to-peer, without data loss or false conflicts.

The native APIs are Objective-C (iOS, Mac) and Java (Android), but an optional internal REST API adapter allows it to be called from other languages like JavaScript and C#, for use in apps built with PhoneGap, Titanium or MonoTouch.

## More Information

* [Why Couchbase Lite?](https://github.com/couchbase/couchbase-lite-ios/wiki/Why-Couchbase-Lite%3F)
* [The Guidebook](https://github.com/couchbase/couchbase-lite-ios/wiki/Guide%3A-Introduction)
* [API Reference](http://couchbase.github.com/couchbase-lite-ios/docs/html/annotated.html)
* There's lots more information on the [wiki][2].
* There's a "Grocery Sync" [demo app][18] for iOS, that implements a simple shared to-do list.
* Or if you want to ask questions or get help, join the [mailing list][17].

## Platforms ##

 * **Mac OS X** -- 10.7.2 or higher.
 * **iOS** -- 5.0 or higher.
 * **Android / Java** -- The [Android version of Couchbase Lite][11] is here.

## Requirements ##

 * It's written in Objective-C.
 * Xcode 4.5+ is required to build it (Clang 3.1+, with GNUstep).
 * Runtime system requirements for Apple platforms are iOS 5+, or Mac OS X 10.7.2+.

## Credits ##

**Design, coding:** Jens Alfke (jens@couchbase.com)  
**Contributions from:** Alexander Edge, Chris Kau, David Venable, Derek Clarkson, Fabien Franzen, fcandalija, J Chris Anderson, Marty Schoch, Mike Lamb, Paul Mietz Egli, Robin Lu  
**Technical advice from:** Damien Katz, Filipe Manana, and several other gurus on the CouchDB mailing list
 
## License ##

 * Couchbase Lite itself is under the Apache License 2.0.
 * [FMDB][5], by [Gus Mueller][8], is under the MIT License.
 * [Google Toolbox For Mac][10] is under the Apache License 2.0.
 * [CocoaHTTPServer][9], by Robbie Hanson, is under the BSD License.
 * [MYUtilities][6] (portions of which are copied into the vendor/MYUtilities directory) is under the BSD License. (But note that I, Jens, wrote MYUtilities and would have no problem re-licensing it under Apache for use here.)

## Downloading Couchbase Lite ##

Get Couchbase Lite via [the Couchbase mobile portal](http://mobile.couchbase.com)

## Building Couchbase Lite ##

You shouldn't need to do this unless you plan to contribute patches.

### On a Mac ###

(You might prefer to just [download][20] the latest build. But if you want to build it yourself...)

For full details see the [wiki page][7]. The basic steps are:

 1. Clone the Couchbase Lite repository to your local disk.
 2. In that directory run "`git submodule init`" and then "`git submodule update`". This will clone the dependent library repos (such as [FMDB][5] and [MYUtilities][6]) into the vendor/ subdirectory.
 3. Open the Xcode project and build the "CBL Mac" and/or "CBL iOS" schemes (whether it targets a device or simulator shouldn't matter).  
 4. (optional) Find resulting framework.  After it builds it should create a `CouchbaseLite.framework` folder in the `/Users/you/Library/Developer/Xcode/DerivedData` directory, which can be copied into other projects.

[1]: http://couchdb.apache.org
[2]: https://github.com/couchbase/couchbase-lite-ios/wiki
[3]: http://couchbase.com
[5]: https://github.com/couchbaselabs/fmdb
[6]: https://bitbucket.org/snej/myutilities/overview
[7]: https://github.com/couchbase/couchbase-lite-ios/wiki/Building-Couchbase-Lite
[8]: https://github.com/ccgus/
[9]: https://github.com/robbiehanson/CocoaHTTPServer
[10]: http://code.google.com/p/google-toolbox-for-mac/
[11]: https://github.com/couchbase/couchbase-lite-android
[12]: http://www.gnustep.org/
[13]: http://wiki.gnustep.org/index.php/Platform_compatibility
[14]: https://github.com/couchbase/couchbase-lite-ios/blob/master/GNUstep/BUILDING.txt
[15]: https://github.com/couchbase/couchbase-lite-ios/blob/master/GNUstep/SETUP.txt
[17]: https://groups.google.com/forum/?fromgroups#!forum/mobile-couchbase
[18]: https://github.com/couchbaselabs/iOS-Couchbase-Demo
[19]: http://files.couchbase.com/developer-previews/mobile/ios/CouchbaseLite/
[20]: http://files.couchbase.com/developer-previews/mobile/ios/CouchbaseLite/CouchbaseLite.zip
[21]: https://github.com/couchbaselabs/TouchDB-iOS
[22]: https://github.com/couchbase/couchbase-lite-ios/wiki/Why-Couchbase-Lite%3F#history
[23]: https://github.com/couchbase/couchbase-lite-ios/wiki/Replication-Algorithm
