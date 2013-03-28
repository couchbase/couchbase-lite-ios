# Couchbase Lite Extras

These are optional classes that you can use in your apps. They're not built into the library, so if you want to use them you should copy the source files into your project.

### CBLUICollectionSource

This is a data source for a UICollectionView, that's driven by a CBLLiveQuery. In other words it's the collection-view equivalent of CBLUITableSource.

(Thanks to Ewan Mcdougall for writing this!)

### CBLJSViewCompiler

This adds support for JavaScript-based map/reduce and filter functions in design documents, just like CouchDB. It requires the JavaScriptCore framework; this is a public system framework on Mac OS but private
    on iOS, so on the latter platform you'll need to link your app with [your own copy of
    JavaScriptCore](https://github.com/phoboslab/JavaScriptCore-iOS).