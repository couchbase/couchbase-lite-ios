# Couchbase Lite 

**Couchbase Lite** is an embedded lightweight, document-oriented (NoSQL), syncable database engine. 

Get more info and downloads of Couchbase Lite (for iOS and Android) via [the Couchbase mobile portal](http://mobile.couchbase.com)

[Click here for **official documentation for Couchbase Lite iOS**](http://developer.couchbase.com/mobile/)

Latency matters a lot to users, so a local database takes frustration out of the equation. It’s got JSON documents, and the same map/reduce as Couchbase Server, in a pint-sized edition.

Couchbase Lite compiles natively for iOS, Android, Mac OS and .NET. Half a megabyte optimized, for quick launch and snappy user experience on occasionally connected devices when data matters.

**Lightweight** means:

* Embedded: The database engine is a library linked into the app, not a separate server process.
* Small code size: currently under 600kbytes. This is important to mobile apps, which are often downloaded over cell networks.
* Quick startup time on relatively-slow CPUs: currently under 50ms on recent iPhones.
* Low memory usage with typical mobile data-sets. The expectation is the number of documents will not be huge, although there may be sizable multimedia attachments.
* "Good enough" performance with these CPUs and data-sets. (Exact figures depend on your data and application, of course.)

**Document-oriented** means:

* Like Couchbase Server, it stores records in flexible [JSON](http://json.org) format instead of requiring predefined schemas or normalization.
* Records/documents can have arbitrary-sized binary attachments, like multimedia content.
* Your application's data format can evolve over time without any need for explicit migrations.
* Map/reduce indexing allows fast lookups without needing to use special query languages.
* Documents can contain free-form text or geographic coordinates, which are efficiently indexed for full-text search or geo-querying.

**[Syncable](http://syncable.org/)** means:

* Any two copies of a database can be brought into sync via an efficient, reliable, proven REST-based [protocol][23].
* Sync can be on-demand or continuous (with a latency of a few seconds).
* The sync engine supports intermittent and unreliable network connections.
* Conflicts can be detected and resolved, with app logic in full control of merging.
* Revision trees allow for complex replication topologies, including server-to-server (for multiple data centers) and peer-to-peer, without data loss or false conflicts.

The native APIs are Objective-C (iOS, tvOS, Mac), Java (Android), and C# (.NET, Xamarin); but an optional internal REST API adapter allows it to be called from other languages like JavaScript, for use in apps built with PhoneGap/Cordova or Titanium.

## More Information

* [Why Couchbase Lite?](https://github.com/couchbase/couchbase-lite-ios/wiki/Why-Couchbase-Lite%3F)
* [API Overview](http://developer.couchbase.com/documentation/mobile/current/get-started/couchbase-lite-overview/index.html)
* [API Reference](http://couchbase.github.com/couchbase-lite-ios/docs/html/annotated.html)
* There's lots more information on the [wiki][2].
* Demo apps:
    * [Grocery Sync][18] - implements a simple shared grocery list.
    * [TodoLite-iOS](https://github.com/couchbaselabs/TodoLite-iOS) - a generic ToDo list with photos and sharing. 
    * [CRM](https://github.com/couchbaselabs/Couchbase-Lite-Demo-CRM) - An enterprise CRM
* Or if you want to ask questions or get help, join the [mailing list][17].

## Platforms ##

 * **Mac OS X** -- 10.8 or higher.
 * **iOS** -- 7.0 or higher.
 * **tvOS** (AppleTV) -- 9.0 or higher.
 * **Android / Java** -- The [Android version of Couchbase Lite][11] is here.
 * **.NET / Xamarin** -- The [C# version of Couchbase Lite][24] is here.

## Requirements ##

 * It's written in Objective-C and C++.
 * Xcode 7 or later is required to build it.

## Credits ##

**Design, coding:** Jens Alfke (jens@couchbase.com), Pasin Suriyentrakorn (pasin@couchbase.com)
**Contributions from:** Alexander Edge, Chris Kau, David Venable, Derek Clarkson, Fabien Franzen, fcandalija, J Chris Anderson, Marty Schoch, Mike Lamb, Paul Mietz Egli, Robin Lu, Traun Leyden, Fonkymasto, Tiago Duarte, cflorion, Evan Kyle, Qihe Bian, sarbogast, Tim Macfarlane, mglasgow, Manu Troquet, monowerker... 
**Technical advice from:** Damien Katz, Filipe Manana, Robert Newson, and several other gurus on the CouchDB mailing list
 
## License ##

 * Couchbase Lite itself, and ForestDB, are under the Apache License 2.0.
 * [CocoaHTTPServer][9], by Robbie Hanson, is under the BSD License.
 * [FMDB][5], by [Gus Mueller][8], is under the MIT License.
 * [Google Toolbox For Mac][10] is under the Apache License 2.0.
 * [MYUtilities][6] (portions of which are copied into the vendor/MYUtilities directory) is under the BSD License.
 * [SQLite3-unicodesn](https://github.com/illarionov/sqlite3-unicodesn) by Alexey Illiaronov, is in the public domain, but we wanted to say thanks anyway.
 * [YAJL](https://github.com/lloyd/yajl), by Lloyd Hilael, is under the ISC license (which appears similar to BSD.)

These are all permissive, commercial-friendly licenses, and you can abide by them simply by putting copyright and permission notices for each in your app's UI / credits / README. For details read the individual licenses.

## Downloading Couchbase Lite ##

Get Couchbase Lite via [the Couchbase mobile portal](http://mobile.couchbase.com)

## Building Couchbase Lite ##

If you want the very latest and greatest (and possibly buggy) version, you'll need to build it yourself. For instructions see the [wiki page][7].

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
[21]: https://github.com/couchbaselabs/TouchDB-iOS
[22]: https://github.com/couchbase/couchbase-lite-ios/wiki/Why-Couchbase-Lite%3F#history
[23]: https://github.com/couchbase/couchbase-lite-ios/wiki/Replication-Algorithm
[24]: https://github.com/couchbase/couchbase-lite-net
