Pod::Spec.new do |s|
  s.name                  = 'CouchbaseLite-Swift'
  s.version               = '3.3.0'
  s.license               = 'Apache License, Version 2.0'
  s.homepage              = 'https://github.com/couchbase/couchbase-lite-ios'
  s.summary               = 'An embedded syncable NoSQL database for iOS and MacOS apps.'
  s.author                = 'Couchbase'
  s.source                = { :git => 'https://github.com/couchbase/couchbase-lite-ios.git', :tag => s.version, :submodules => true }

  s.prepare_command = <<-CMD
    sh Scripts/prepare_cocoapods.sh "CBL_Swift"
  CMD

  s.ios.preserve_paths = 'frameworks/CBL_Swift/iOS/CouchbaseLiteSwift.framework'
  s.ios.vendored_frameworks = 'frameworks/CBL_Swift/iOS/CouchbaseLiteSwift.framework'

  s.osx.preserve_paths = 'frameworks/CBL_Swift/macOS/CouchbaseLiteSwift.framework'
  s.osx.vendored_frameworks = 'frameworks/CBL_Swift/macOS/CouchbaseLiteSwift.framework'

  s.ios.deployment_target  = '12.0'
  s.osx.deployment_target  = '12.0'
end
