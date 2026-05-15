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
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.compiler_flags = '-DDART_SHARED_LIB -DFEATURE_SOUND'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'CoreFoundation'
  s.libraries = 'c++', 'm'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src" "$(PODS_TARGET_SRCROOT)/../src/doomgeneric" "$(PODS_TARGET_SRCROOT)/../src/opl"'
  }
  s.swift_version = '5.0'
end
