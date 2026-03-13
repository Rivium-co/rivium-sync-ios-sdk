Pod::Spec.new do |s|
  s.name             = 'RiviumSync'
  s.version          = '0.1.0'
  s.summary          = 'Realtime database SDK for iOS with offline-first sync'
  s.description      = 'Realtime database SDK for iOS with offline-first sync powered by pn-protocol'
  s.homepage         = 'https://rivium.co'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Rivium' => 'support@rivium.co' }
  s.source           = { :git => 'https://github.com/Rivium-co/rivium-sync-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/**/*.swift'

  s.dependency 'PNProtocol', '~> 0.2'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
