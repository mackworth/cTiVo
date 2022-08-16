# Uncomment the next line to define a global platform for your project
platform :macos, '10.15'
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
end

post_install do |installer|
    puts 'Patching DDLog.m to fix RegisteredClasses bug, if needed.'
    filename = "Pods/CocoaLumberjack/Sources/CocoaLumberjack/DDLog.m"
    outStr = %x(patch --forward #{filename} < DDlogPatch.patch)
    errStr = <<"EOS"  #if patch gives this exact error message, don't alarm user
patching file #{filename}
Reversed (or previously applied) patch detected!  Skipping patch.
1 out of 1 hunk ignored -- saving rejects to file #{filename}.rej
EOS
    if outStr == errStr
      puts ("Patch already applied")
      %x{ rm -f #{filename}.rej } #remove "rejected patch" file if created
    else
      puts outStr
    end
end
