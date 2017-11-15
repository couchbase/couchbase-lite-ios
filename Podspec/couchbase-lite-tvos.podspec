Pod::Spec.new do |s|
  s.name            = 'couchbase-lite-tvos'
  s.version         = '1.4.1'
  s.license         = { :type => 'Apache License, Version 2.0', :file => 'LICENSE.txt' }
  s.homepage        = 'http://mobile.couchbase.com'
  s.summary         = 'An embedded syncable NoSQL database for tvOS apps.'
  s.author          = 'Couchbase'
  s.source          = { :http => 'https://packages.couchbase.com/releases/couchbase-lite/tvos/1.4.1/couchbase-lite-tvos-community_1.4.1.zip' }
  s.preserve_paths  = 'LICENSE.txt'
  s.tvos.deployment_target = '9.0'
  s.frameworks      = 'CFNetwork', 'Security', 'SystemConfiguration', 'JavaScriptCore'
  s.libraries       = 'z', 'c++'
  s.xcconfig        = { 'OTHER_LDFLAGS' => '-ObjC' }
  s.default_subspec = 'SQLite'

  s.subspec 'SQLite' do |ss|
    ss.libraries = 'sqlite3'
    ss.vendored_library = 'Extras/libCBLJSViewCompiler.a'
    ss.source_files = 'CouchbaseLite.framework/Headers/*.h', 'CouchbaseLiteListener.framework/Headers/*.h', 'Extras/CBLRegisterJSViewCompiler.h'
    ss.preserve_paths = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
    ss.vendored_frameworks = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
  end

  s.subspec 'SQLCipher' do |ss|
    ss.vendored_libraries = 'Extras/libsqlcipher.a', 'Extras/libCBLJSViewCompiler.a'
    ss.source_files = 'CouchbaseLite.framework/Headers/*.h', 'CouchbaseLiteListener.framework/Headers/*.h', 'Extras/CBLRegisterJSViewCompiler.h'
    ss.preserve_paths = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
    ss.vendored_frameworks = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
  end

  s.subspec 'ForestDB' do |ss|
    ss.libraries = 'sqlite3'
    ss.vendored_libraries = 'Extras/libCBLForestDBStorage.a', 'Extras/libCBLJSViewCompiler.a'
    ss.source_files = 'CouchbaseLite.framework/Headers/*.h', 'CouchbaseLiteListener.framework/Headers/*.h', 'Extras/CBLRegisterJSViewCompiler.h'
    ss.preserve_paths = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
    ss.vendored_frameworks = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
  end
end
