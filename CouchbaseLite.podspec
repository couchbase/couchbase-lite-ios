Pod::Spec.new do |s|
  s.name                  = 'CouchbaseLite'
  s.version               = '2.0DB023'
  s.license               = 'Apache License, Version 2.0'
  s.homepage              = 'http://mobile.couchbase.com'
  s.summary               = 'An embedded syncable NoSQL database for iOS and MacOS apps.'
  s.author                = 'Couchbase'
  s.source                = { :git => 'https://github.com/couchbase/couchbase-lite-ios.git', :tag => s.version, :submodules => true }

  s.prepare_command = <<-CMD
    sh Scripts/prepare_cocoapods.sh "CBL ObjC"
  CMD

  s.ios.preserve_paths = 'frameworks/CBL ObjC/iOS/CouchbaseLite.framework'
  s.ios.vendored_frameworks = 'frameworks/CBL ObjC/iOS/CouchbaseLite.framework'

  s.osx.preserve_paths = 'frameworks/CBL ObjC/macOS/CouchbaseLite.framework'
  s.osx.vendored_frameworks = 'frameworks/CBL ObjC/macOS/CouchbaseLite.framework'

  s.ios.deployment_target  = '9.0'
  s.osx.deployment_target  = '10.11'
end
