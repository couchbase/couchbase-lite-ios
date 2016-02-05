How to publish the Cocoapod Specs:

1. Install Cocoapod

 ```
 sudo gem install cocoapods
 ```

2. Register a new session (Optional if the previous session hasn't been expired)

 ```
 pod trunk register YOURNAME@couchbase.com "Full Name"
 ```

3. Open the podspec files and modify version number and the release zip file url.

4. Publish the spec files

 ```
 pod trunk push --verbose couchbase-lite-ios.podspec
 pod trunk push --verbose couchbase-lite-osx.podspec
 ```
