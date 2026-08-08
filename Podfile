# Transitive dependencies of the SmartAirKey binary SDK (AirKeySmartDeviceCore).
# These are the public pods the SDK links against; the SmartAirKey-specific
# binaries themselves are vendored as xcframeworks (see project.yml / Vendor/SDK).
#
# Usage:  xcodegen generate && pod install && open SmartAirKey.xcworkspace

platform :ios, '16.0'

target 'SmartAirKey' do
  use_frameworks!

  pod 'CocoaLumberjack'
  pod 'Protobuf'
  pod 'SSZipArchive'
  pod 'RWMRecurrenceRule', :git => 'https://github.com/rmaddy/RWMRecurrenceRule.git'
  pod 'TransitionKit', :git => 'https://github.com/blakewatters/TransitionKit'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      # Pods must not be code-signed at build time (the app target re-signs the
      # embedded frameworks when archiving). Without this, the app's manually
      # specified provisioning profile "leaks" onto pod targets that don't
      # support profiles (e.g. SSZipArchive), failing the archive.
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
