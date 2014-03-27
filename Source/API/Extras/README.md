# Couchbase Lite Extras

These are optional classes that you can use in your apps. They're not built into the library, so if you want to use them you should copy the source files into your project.

### CBLIncrementalStore

This is an adapter that allows Couchbase Lite to be used as a persistent store for Core Data. Using this, you can write your app using Core Data APIs but still get the synchronization features of Couchbase Lite.

There is a [demo application][COREDATA_SAMPLE] that shows how to use this class. It's a modified version of Apple's "Core Data Recipes" sample that uses Couchbase Lite.

### CBLUICollectionSource

This is a data source for a UICollectionView, that's driven by a CBLLiveQuery. In other words it's the collection-view equivalent of CBLUITableSource.

(Thanks to Ewan Mcdougall for writing this!)

### CBLJSViewCompiler

This adds support for JavaScript-based map/reduce and filter functions in design documents, just like CouchDB.

It requires the JavaScriptCore framework; this is a public system framework on iOS 7 and on Mac OS, but private
    on iOS 6. If your app needs to support iOS 6, you'll have to link your app with [your own copy of
    JavaScriptCore][JSCORE].

[COREDATA_SAMPLE]: https://github.com/couchbaselabs/cblite-coredata-sample-ios
[JSCORE]: https://github.com/phoboslab/JavaScriptCore-iOS
