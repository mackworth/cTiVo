# Uncomment the next line to define a global platform for your project
platform :macos, '10.11'

target 'cTiVo' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  pod 'Firebase/Analytics'
  pod 'Firebase/Crashlytics'
end

target 'cTiVo MAS' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  pod 'Firebase/Analytics'
  pod 'Firebase/Crashlytics'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
    end
  end
end

