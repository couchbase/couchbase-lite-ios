# Couchbase Lite Extras

These are optional classes that you can use in your apps. They're not built into the library, so if you want to use them you should copy the source files into your project.

### CBLEncryptionController

Manages the password/key UI associated with encrypted databases. Takes care of prompting the user for passwords, or determining if Touch ID can be used instead. (iOS only, so far.)

(Note: Database encryption requires building your app with [SQLCipher](http://sqlcipher.net) instead of the OS-provided libSQLite.dylib.)

### CBLIncrementalStore

This is an adapter that allows Couchbase Lite to be used as a persistent store for Core Data. Using this, you can write your app using Core Data APIs but still get the synchronization features of Couchbase Lite.

There is a [demo application][COREDATA_SAMPLE] that shows how to use this class. It's a modified version of Apple's "Core Data Recipes" sample that uses Couchbase Lite.

### CBLUICollectionSource

This is a data source for a UICollectionView, that's driven by a CBLLiveQuery. In other words it's the collection-view equivalent of CBLUITableSource.

(Thanks to Ewan Mcdougall for writing this!)

### CBLJSViewCompiler

This adds support for JavaScript-based map/reduce and filter functions in design documents, just like CouchDB. You'll need to link your app with the system JavaScriptCore framework.

[COREDATA_SAMPLE]: https://github.com/couchbaselabs/cblite-coredata-sample-ios
