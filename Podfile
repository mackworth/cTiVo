DEPLOYMENT_TARGET_MACOS = '10.15'

platform :macos, DEPLOYMENT_TARGET_MACOS
use_frameworks!


target 'cTiVo' do
  pod 'AppCenter/Analytics'
  pod 'Firebase/Crashlytics'
  pod 'CocoaLumberjack/Swift'
  target 'cTiVoTests' do
    inherit! :search_paths
  end
end

target 'cTiVo MAS' do
  pod 'AppCenter/Analytics'
  pod 'Firebase/Crashlytics'
  pod 'CocoaLumberjack/Swift'
end

post_install do |installer|
    puts 'Patching DDLog.m to fix RegisteredClasses bug, if needed.'
    filename = "Pods/CocoaLumberjack/Sources/CocoaLumberjack/DDLog.m"
    outStr = %x(patch --forward #{filename} < DDlogPatch.patch)
    errStr = <<"EOS"  #if patch gives this exact error message, don't alarm user
patching file '#{filename}'
Ignoring previously applied (or reversed) patch.
1 out of 1 hunks ignored--saving rejects to '#{filename}.rej'
EOS
    if outStr == errStr
      puts ("Patch already applied")
      %x{ rm -f #{filename}.rej } #remove "rejected patch" file if created
    else
      puts outStr
    end
    installer.pods_project.build_configurations.each do |config|
      config.build_settings['DEAD_CODE_STRIPPING'] = 'YES'
    end
    
    # Fix deployment target for pods that don't specify one
    # or specify one that is older than our own deployment target.
    desired_macos = Gem::Version.new(DEPLOYMENT_TARGET_MACOS)
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings.delete 'ARCHS'

            settings = config.build_settings
            actual = Gem::Version.new(settings['MACOSX_DEPLOYMENT_TARGET'])
            if actual < desired_macos
                settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET_MACOS
            end
        end
    end

end
