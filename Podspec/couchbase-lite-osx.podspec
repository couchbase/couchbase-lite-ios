Pod::Spec.new do |s|
  s.name            = 'couchbase-lite-osx'
  s.version         = '1.1.0'
  s.license         = { :type => 'Apache License, Version 2.0', :file => 'LICENSE.txt' }
  s.homepage        = 'http://mobile.couchbase.com'
  s.summary         = 'An embedded syncable NoSQL database for osx apps.'
  s.author          = 'Couchbase'
  s.source          = { :http => 'TBD' }
  s.preserve_paths  = 'LICENSE.txt'
  s.osx.deployment_target = '10.8'
  s.frameworks      = 'CFNetwork', 'Security', 'SystemConfiguration'
  s.libraries       = 'sqlite3', 'z'
  s.xcconfig        = { 'OTHER_LDFLAGS' => '-ObjC' }

  s.default_subspec = 'Core'

  s.subspec 'Core' do |ss|
    ss.preserve_paths = 'CouchbaseLite.framework'
    ss.vendored_frameworks = 'CouchbaseLite.framework'
    ss.osx.resource = 'CouchbaseLite.framework'
  end

  s.subspec 'Listener' do |ss|
    ss.dependency 'couchbase-lite-osx/Core'
    
    ss.preserve_paths = 'CouchbaseLiteListener.framework'
    ss.vendored_frameworks = 'CouchbaseLiteListener.framework'
    ss.osx.resource = 'CouchbaseLiteListener.framework'
  end
end
