# CouchLite #

CouchLite is a simple persistent storage manager. It's built on top of SQLite, but is itself not relational.

## Data Model ##

The basics are similar to SQLite: CouchLite stores **databases** in individual disk files. A database can contain any number of named **tables**. A table contains **documents**, each identified by a numeric **key**.

Documents, however, are different from relational rows. Their contents are a set of key-value pairs, and documents aren't all required to have the same keys, even within the same table. (They're *schemaless*.) Moreover, the values of the keys can be arrays or dictionaries, not just scalar values -- you can think of a document as containing a property-list. (This is similar to the JSON data model used by CouchDB and MongoDB.)

Every document also contains a **revision number**. This number starts at zero when a document is created in memory, and is incremented every time it's saved on disk. It enables *multiversion concurrency control*: when  a modified document is saved back to the database, the save will fail if the current on-disk document has a different revision number than it did when the document was read. This detects race conditions where two clients read the same document, modify it in different ways, and both try to save it back. Without concurrency control, the second save would overwrite the first and lose the changes it made. But in CouchLite, the second save will fail, and the client will need to fetch the updated version of the document, reconcile the changes, and try again.