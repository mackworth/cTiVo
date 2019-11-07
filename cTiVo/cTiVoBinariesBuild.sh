#here's the macports-based process to create ctivo binaries on Mojave.
#There are a couple of issues. First with the stdc++ lib transition, MacPorts has given up on 10.7 and 10.8. We're just using the old binaries for the 10.7 version.
#Second Macports isn't really designed to build older versions of software than your current system
#Third, there's a bug in ffmpeg's build process, where it sees "clock_gettime" in the 10.12 SDK and assumes its available for 10.9 on
#Fourth, there's a bug in Macports binary download, where it doesn't honor macosx_deployment_target
#The tricky part is getting it all to compile for previous versions of macOS, and avoid ones you may already have installed for your 
#system. You can either completely empty out MacPorts directory /opt/bin and install using their package installer, 
#OR create a temporary MacPorts directory as follows:

echo "Until further debugged, you probably want to run this one step at a time to ensure it works."
echo "Just copy commands into a Terminal session"
exit

if [ -d "/opt/oldLocal" ]; then
  echo "Backup directory for MacPorts already exists! Exiting..."
  exit
fi

sudo mv /opt/local /opt/oldLocal
echo "Download MacPorts (https://www.macports.org/install.php) and run the Installer"
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

if [ ! -d "/opt/local" ]; then
    echo "MacPorts not installed! Exiting..."
    exit
fi

##Bug: NEED TO fix permissions on $TARGET to allow admin writing
#Now add 10.9 to the macports configuration file
TARGET="/opt/local/etc/macports/macports.conf"
SEARCH="macosx_deployment_target 10.9"
if grep -q "$SEARCH" "$TARGET"; then  
    echo Already has "$SEARCH"
else  
    echo Adding "$SEARCH"
    sudo echo "$SEARCH" >> $TARGET
fi

export MACOSX_DEPLOYMENT_TARGET=10.9

#NNOW patch Macports to download official binaries
open "/opt/local/libexec/macports/lib/port1.0/"
echo 'Now edit portutil.tcl with following patch for get_portimage_name at about line 2565`
````
--- /opt/local/libexec/macports/lib/port1.0/portutil.orig.tcl 2016-11-16 21:25:25.000000000 -0800
+++ /opt/local/libexec/macports/lib/port1.0/portutil.tcl  2017-01-04 10:10:20.000000000 -0800
@@ -2538,13 +2538,20 @@

 # return filename of the archive for this port
 proc get_portimage_name {} {
-    global portdbpath subport version revision portvariants os.platform os.major portarchivetype
-    set ret "${subport}-${version}_${revision}${portvariants}.${os.platform}_${os.major}.[join [get_canonical_archs] -].${portarchivetype}"
+    global portdbpath subport version revision portvariants os.platform os.major portarchivetype macosx_deployment_target
+    set OSVersion ${os.major}
+    if {[string first 10. $macosx_deployment_target] == 0} {
+         set testVersion [string range $macosx_deployment_target 3 end]
+         if {[string is integer -strict $testVersion]} {
+            set OSVersion [expr {$testVersion + 4}]
+         }
+    }
+    set ret "${subport}-${version}_${revision}${portvariants}.${os.platform}_${OSVersion}.[join [get_canonical_archs] -].${portarchivetype}"
     # should really look up NAME_MAX here, but it'\''s 255 for all OS X so far 
     # (leave 10 chars for an extension like .rmd160 on the sig file)
     if {[string length $ret] > 245 && ${portvariants} != ""} {
         # try hashing the variants
-        set ret "${subport}-${version}_${revision}+[rmd160 string ${portvariants}].${os.platform}_${os.major}.[join [get_canonical_archs] -].${portarchivetype}"
+        set ret "${subport}-${version}_${revision}+[rmd160 string ${portvariants}].${os.platform}_${OSVersion}.[join [get_canonical_archs] -].${portarchivetype}"
     }
     if {[string length $ret] > 245} {
         error "filename too long: $ret"
````
'
# Note: due to quoting problems with echo, "it'\''s" above should actually be "it's"
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

sudo port install argtable


open /opt/local/etc/macports/
echo "Now Add the following line BEFORE the rsync URL in sources.conf in /opt/local/etc/macports"
echo "file:///Users/hugh/ports"
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

#ref instructions in Macports on how to create a https://guide.macports.org/#development.local-repositories
mkdir -p ~/ports/multimedia/ffmpeg
cp /opt/local/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports/multimedia/ffmpeg/Portfile ~/ports/multimedia/ffmpeg/portfile
#note this reinplace is specifically for 10.9-10.11 compatibility when compiling on 10.12 or later
#it's a bug in the macports installer, which is fixed in homebrew
#(https://github.com/Homebrew/homebrew-core/pull/4924/commits/76095fceaf751c4b746cb7e8bcc24bc87f5a5912)
#if submitted as a fix, it needs to ensure those conditions are in place:
#psuedocode of: if macosx_deployment_target < "10.12" && MacOS::Xcode.version >= "8.0"
#alternatively just could hack the configure file to change HAS_CLOCKGETTIME YES
open  ~/ports/multimedia/ffmpeg
echo "Now Add the following line to the post-patch section of the ffmpeg/portfile"
echo '   reinplace "s|HAVE_CLOCK_GETTIME|UNDEFINED_GIBBERISH|g" ${worksrcpath}/libavdevice/v4l2.c ${worksrcpath}/libavutil/time.c'
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

#to fix gnutls "can't link connectX" bug
#no longer needed
#mkdir -p ~/ports/devel/gnutls/files
#cp -R “$(port dir gnutls)” ~/ports/devel
#curl -Lo ~/ports/devel/gnutls/files/patch.diff https://raw.github.com/darktable-org/darktable/master/packaging/macosx/gnutls-disable-connectx.diff

#then append following line: to ~/ports/devel/gnutls/Portfile files you just copied
#echo `patchfiles-append patch.diff` >> ~/ports/devel/gnutls/Portfile

#now index above patches.
cd ~/ports
portindex

sudo port install ffmpeg +nonfree+gpl2
echo ensure dependencies all say "darwin_13" (for OS 10.9)
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

#May need to copy /include/nettle/nettle-stdint.h
#to /opt/local/include/nettle
sudo port install mplayer +a52+mencoder_extras

mkdir ~/NewcTivoBinaries
cd ~/NewcTivoBinaries

git clone git://github.com/erikkaashoek/Comskip  
git clone git://github.com/essandess/matryoshka-name-tool 
git clone git://github.com/CCExtractor/ccextractor

#now build comskip
export MACOSX_DEPLOYMENT_TARGET=10.9
cd comskip; ./autogen.sh; ./configure; make; cd ..
mkdir cTiVoBinaries; cd cTiVoBinaries; mkdir bin; mkdir lib; cd bin
cp ../../comskip/comskip comskip; cp /opt/local/bin/mencoder mencoder; cp /opt/local/bin/ffmpeg ffmpeg
python ../../matryoshka-name-tool/matryoshka_name_tool.py -d ../lib/ comskip ffmpeg mencoder

#test for external symbol not available in OSX 10.9
if [[ $(nm -g "/opt/local/lib/libavutil.56.31.100.dylib"  | grep "U _clock_gettime") ]]; then
  echo "Error! still has _clock_gettime symbol"
  exit 1
fi


cd ../../ccextractor/mac
export MACOSX_DEPLOYMENT_TARGET=10.9
./build.command
cp ./ccextractor ../../cTiVoBinaries/bin
cd ../../cTiVoBinaries/bin

for f in *; do otool -l $f| grep --label=$f -H '^  version 10.'; done
for f in ../lib/*; do otool -l $f| grep --label=$f -H '^  version 10.'; done
echo "please check that those are all version 10.9"
read -p "Then press [return] key to continue, or Ctrl-C to cancel..."

cd ..
cp bin/* ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/bin/
cp lib/* ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/lib/

echo "Now copy HandbrakeCLI into cTiVoBinaries/bin folder"

echo "And get tivodecode-ng from https://github.com/wmcbrine/tivodecode-ng/releases"
and ./configure ; make; #then rename to tivodecode-ng
#finally restore your MacPorts:
sudo mv /opt/oldLocal /opt/local
