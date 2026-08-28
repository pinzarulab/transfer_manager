Pod::Spec.new do |s|
  s.name             = 'transfer_manager_ios'
  s.version          = '2.2.1'
  s.summary          = 'iOS background URLSession implementation for transfer_manager.'
  s.description      = <<-DESC
Durable background downloads and uploads for the transfer_manager Flutter package.
                       DESC
  s.homepage         = 'https://github.com/pinzarulab/transfer_manager'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Pinzaru Lab' => 'opensource@pinzarulab.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.default_subspec  = 'Plugin'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version    = '5.0'
  s.resource_bundles = {
    'transfer_manager_ios_privacy' => [
      'transfer_manager_ios/Sources/transfer_manager_ios/PrivacyInfo.xcprivacy'
    ]
  }

  s.subspec 'LiveActivitySupport' do |ss|
    ss.source_files = 'transfer_manager_ios/Sources/TransferManagerLiveActivitySupport/**/*'
  end

  s.subspec 'Plugin' do |ss|
    ss.source_files = 'transfer_manager_ios/Sources/transfer_manager_ios/**/*'
    ss.dependency 'Flutter'
    ss.dependency 'transfer_manager_ios/LiveActivitySupport'
  end
end
