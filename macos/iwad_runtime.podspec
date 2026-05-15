#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint iwad_runtime.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'iwad_runtime'
  s.version          = '0.1.0'
  s.summary          = 'Flutter IWAD runtime native backend.'
  s.description      = <<-DESC
Embeds the native IWAD runtime used by the Flutter package.
                       DESC
  s.homepage         = 'https://kicknext.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'KickNext' => 'dev@kicknext.dev' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{c,m,h}'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'iwad_runtime_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.compiler_flags = '-DDART_SHARED_LIB -DFEATURE_SOUND'
  s.frameworks = 'AudioToolbox', 'CoreAudio', 'CoreFoundation'
  s.libraries = 'c++', 'm'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src" "$(PODS_TARGET_SRCROOT)/../src/doomgeneric" "$(PODS_TARGET_SRCROOT)/../src/opl"'
  }
  s.swift_version = '5.0'
end
