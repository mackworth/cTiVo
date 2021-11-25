#moved to homebrew for latest version...

#here's the macports-based process to create ctivo binaries on Mojave.
#There are a couple of issues. First with the stdc++ lib transition, MacPorts has given up on 10.7 and 10.8. We're just using the old binaries for the 10.7 version.
#Second Macports isn't really designed to build older versions of software than your current system
#Third, there's a bug in ffmpeg's build process, where it sees "clock_gettime" in the 10.12 SDK and assumes its available for 10.9 on
#Fourth, there's a bug in Macports binary download, where it doesn't honor macosx_deployment_target
#The tricky part is getting it all to compile for previous versions of macOS, and avoid ones you may already have installed for your 
#system. You can either completely empty out MacPorts directory /opt/bin and install using their package installer, 
#OR create a temporary MacPorts directory as follows:


NEWBINARIES="/Users/Hugh/Documents/Develop/ctivoBinaries/cTiVoBinaries-3.5/bin"
WORKINGDIR="/Users/Hugh/Documents/Develop/ctivoBinaries/NewcTivoBinaries"
OLDBINARIES="/Users/Hugh/Documents/Develop/ctivoBinaries/cTiVoBinaries-3.4.0/bin"  


echo BEGINCOMMENT; : <<'ENDCOMMENT'

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



# #May need to copy /include/nettle/nettle-stdint.h
# #to /opt/local/include/nettle
# sudo port install mplayer +a52+mencoder_extras

# Done already:
# lipo ~/Documents/Develop/cTiVoGithub/cTiVo/mp4v2/mp4v2-10.9/libmp4v2.a /opt/homebrew/Cellar/mp4v2/2.0.0/lib/libmp4v2.a -create -output /Users/hugh/Documents/Develop/cTiVoGithub/cTiVo/mp4v2/mp4v2-10.9/combolibmp4v2.a

ENDCOMMENT

mkdir -p "$NEWBINARIES"; mkdir "$NEWBINARIES/../lib"

mkdir "$WORKINGDIR"; cd "$WORKINGDIR"

git clone git://github.com/erikkaashoek/Comskip  
git clone git://github.com/CCExtractor/ccextractor
git clone git://github.com/wmcbrine/tivodecode-ng
git clone git://github.com/essandess/matryoshka-name-tool 

brew install autoconf automake libtool argtable 

echo Building ffmpeg 
brew tap homebrew-ffmpeg/ffmpeg
#if you change options, temporarily change next line to brew reinstall (or add brew uninstall homebrew-ffmpeg/ffmpeg/ffmpeg)
#also if you get an error, the you may need brew uninstall ffmpeg
brew install  homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac --with-libbluray --with-libmodplug --with-openjpeg --with-librsvg --with-srt --with-xvid --with-zimg

echo Building comskip
export MACOSX_DEPLOYMENT_TARGET=10.11
cd "$WORKINGDIR/comskip"
./autogen.sh; ./configure; make; 

echo Collecting and Doing matryoshka on all three executables
cd "$NEWBINARIES"
cp "$WORKINGDIR/comskip/comskip" comskip
cp -f /opt/homebrew/bin/ffmpeg ffmpeg
echo Getting old mencoder...only intel now
cp "$OLDBINARIES/mencoder" mencoder

python "$WORKINGDIR/matryoshka-name-tool/matryoshka_name_tool.py" -d ../lib/ -L "/opt/homebrew/" ffmpeg comskip

# #re-codesign executables; have to move off existing inode to work???
for f in {ffmpeg,comskip}; do
   lipo "$OLDBINARIES/$f" "$NEWBINARIES/$f" -create -output $f-tmp; rm -f $f; mv $f-tmp $f
   mv $f $f-tmp ; ditto $f-tmp $f ;  rm -f $f-tmp ; codesign  -s - -o library -f $f  
done   

cd ../lib
for x86Ver in "$OLDBINARIES"/../lib/*.dylib ; do
    armVer=$(basename "$x86Ver")
    if test -f "$armVer" ; then
        echo "Merging x86 and ARM for $armVer"
        mv "$armVer" "tmp.dylib"
        lipo "tmp.dylib" "$x86Ver" -create -output "$armVer"
        rm -f "tmp.dylib"
    else
        echo "Copying x86 to $armVer"
        ditto "$x86Ver" "$armVer"
    fi
done

for i in *.dylib ; do 
    mv $i tmp.dylib ; ditto tmp.dylib $i ;  yes | rm -f tmp.dylib 
    codesign  -s - -o library -f $i
done  


echo Building ccextractor
cd "$WORKINGDIR/ccextractor/"
mkdir build
cd build

#Generate makefile using cmake and then compile
cmake ../src/ -DWITHOUT_RUST=ON
make

lipo "$OLDBINARIES/ccextractor" ./ccextractor -create -output "$NEWBINARIES/ccextractor"

 echo Building tivodecode-ng
 cd "$WORKINGDIR/tivodecode-ng"
 ./configure ; make; #then rename to tivodecode-ng
 lipo "$OLDBINARIES/tivodecode-ng" ./tivodecode -create -output "$NEWBINARIES/tivodecode"

echo And checking versions:
for f in ../bin/*; do otool -l $f| grep --label=$f -H '^  version '; done
for f in ../lib/*; do otool -l $f| grep --label=$f -H '^  version '; done
echo "please check that lib are all version 10.9 and version 10.11"
read -p "Then press [return] key to copy into project, or Ctrl-C to cancel..."

cd "$NEWBINARIES/.."
rm -f ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/bin/*
rm -f ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/lib/*
ditto bin/* ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/bin/
ditto lib/* ~/Documents/Develop/cTiVoGitHub/cTivo/cTiVoBinaries/lib/

echo "Don't forget to copy latest HandbrakeCLI into cTiVoBinaries/bin folder"

#finally restore your MacPorts:
# sudo mv /opt/oldLocal /opt/local
