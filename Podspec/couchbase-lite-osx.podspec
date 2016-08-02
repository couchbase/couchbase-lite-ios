Pod::Spec.new do |s|
  s.name            = 'couchbase-lite-osx'
  s.version         = '<RELEASE VERSION NUMBER>'
  s.license         = { :type => 'Apache License, Version 2.0', :file => 'LICENSE.txt' }
  s.homepage        = 'http://mobile.couchbase.com'
  s.summary         = 'An embedded syncable NoSQL database for macOS apps.'
  s.author          = 'Couchbase'
  s.source          = { :http => '<RELEASE ZIP FILE URL>' }
  s.preserve_paths  = 'LICENSE.txt'
  s.osx.deployment_target = '10.8'
  s.frameworks      = 'CFNetwork', 'Security', 'SystemConfiguration'
  s.libraries       = 'z', 'c++'
  s.xcconfig        = { 'OTHER_LDFLAGS' => '-ObjC' }

  s.default_subspec = 'Core'

  s.subspec 'Core' do |ss|
    ss.preserve_paths = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
    ss.vendored_frameworks = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
    ss.osx.resources = 'CouchbaseLite.framework', 'CouchbaseLiteListener.framework'
  end
end
