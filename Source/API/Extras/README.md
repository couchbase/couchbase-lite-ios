# Couchbase Lite Extras

These are optional classes that you can use in your apps. They're not built into the library, so if you want to use them you should copy the source files into your project.

### CBLEncryptionController

Manages the password/key UI associated with encrypted databases. Takes care of prompting the user for passwords, or determining if Touch ID can be used instead. (iOS only, so far.)

(Note: Database encryption for SQLite-based databases requires building your app with [SQLCipher](http://sqlcipher.net) instead of the OS-provided libSQLite.dylib. If you're using ForestDB storage, you're fine.)

### CBLIncrementalStore

This is an adapter that allows Couchbase Lite to be used as a persistent store for Core Data. Using this, you can write your app using Core Data APIs but still get the synchronization features of Couchbase Lite.

There is a [demo application][COREDATA_SAMPLE] that shows how to use this class. It's a modified version of Apple's "Core Data Recipes" sample that uses Couchbase Lite.

### CBLJSONValidator

Validates JSON objects against [JSON-Schema][JSON_SCHEMA] specs. This can be used in database validation blocks, as a way to implement complex data validations without writing code.

### CBLJSViewCompiler

This adds support for JavaScript-based map/reduce and filter functions in design documents, just like CouchDB. You'll need to link your app with the system JavaScriptCore framework.

### CBLUICollectionSource

This is a data source for a UICollectionView, that's driven by a CBLLiveQuery. In other words it's the collection-view equivalent of CBLUITableSource.

(Thanks to Ewan Mcdougall for writing this!)

### OpenIDConnectUI

An implementation of a user interface for [OpenID Connect][OIDC] logins, for use with a CBLAuthenticator. This code pops up a WebView at the identity provider's login URL, lets the user log in using the website, and automatically closes when login completes.

Note: We've provided both iOS and macOS implementations. Use `OpenIDController.m` on both platforms. On iOS you'll also need `OpenIDController+UIKit.m`, and on macOS `OpenIDController+AppKit.m`.

[COREDATA_SAMPLE]: https://github.com/couchbaselabs/cblite-coredata-sample-ios
[JSON_SCHEMA]: http://json-schema.org
[OIDC]: http://openid.net/connect/
