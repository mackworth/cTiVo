# Release 3.4.0 (Catalina and Sandboxing)
* Sends videos to Apple's TV app due to obsolescence of iTunes.
* Submits Audio-only downloads to Music app in Catalina.
* Sandboxed cTV app also available.
* New *Get Info* command for TiVos (disk space, network connectivity etc) in *Edit Tivos* and *Remote Control*
* Known as 3.3.2 during beta testing.

### 3.4.1 fixes
* Upgrade all binaries and libraries
* Avoid crash due to manual TiVos with no name
* *Get TiVo Info* improvements:
      * Added to Main Window
      * Remove double-click from Edit> TiVo Tables (confusing with edits)
      * On Mini, Report Screensaver; don't show number of shows
* Provide error on invalid Keyword in template

### Sandboxed cTV version:
The Mac App Store beta version (now called cTV) is also available.  It is completely identical to cTiVo, except...
* Now fully sandboxed, improving security of your Mac.
* New name and icon (due to trademark concerns by Apple).
* You can't change the temporary working directory (but you can change the Download directory).
* Doesn't do its own updates nor moves to App directory, as these will be handled by App Store.

Although it is an otherwise identical product in terms of features, your help is needed to test out the sandboxing part. Just download and run the cTV app.  cTV preferences and cache are migrated from cTIVo. cTiVo version 3.4.0 will reverse that migration, so you can alternate between these versions.  (Although strangely, you'll need to wait a couple minutes between exiting cTV and then starting cTiVo; if not, you'll get a message asking you to do so.) For now, both versions will continue to be available.  

### Fixes:
* Improved reliability for finding completed videos on desk.
* Help files look better in Dark mode.
* Better logging to diagnose occasional delays in SkipMode.
* Misc minor fixes.

# Release 3.3.1 
##  Minor fixes
* cTiVo will immediately notice now when a show has finished recording
* If you have never used Mark before, 3.3.0 upgrade incorrectly turned it on
* Correctly reports "memory buffer" in logs 
* Avoids obscure crash while searching for TiVos
* Note: Handbrake CLI no longer compatible with 10.9 (workaround: don't use HB presets on 10.9)

Also has new status icons, matching TiVo's for in-progress, recently recording, and suggestions

# Release 3.3.0 (SkipMode)

This release takes advantage of TiVo's SkipMode for Marking or Cutting commercials. There are some issues to be aware of, so please see [SkipMode note](#Notes-On-SkipMode) below (also in the help file in Preferences>General>Commercials>? ).

### Main new features:
#### SkipMode use
*    Use TiVo's SkipMode Info when available for Marking/Cutting commercials
*    Hold off processing until SkipMode arrives (or doesn't)
*    Fallback to Comskip if SkipMode unavailable or fails
#### MPEG2 streams only download over a Transport Stream connection.
*  New Download column "Use TS". Set by channel's TS status initially, but changes automatically after bad download.
*  New Advanced Preference: Allow MPEG2 in Transport Streams (Regardless, will retry with Program Stream if MPEG2 fails encoding).
*  Each show now has a column for whether it is MPEG2 or H264 (measured by either actual download attempt OR by the channel).
#### Remote Control Window
*    TiVo remote control emulation
*    Keystroke alternatives
*    Directly select streaming services
#### New TiVo menu 
*    Play on TiVo
*    Delete on TiVo
*    Stop Recording
*    Reload Information
*    Reboot TiVo
*    Redesigned contextual menus
#### Mojave Support
*    Dark Mode in Mojave
*    iTunes permission check and AppleScript warnings for Mojave
*   "Hardened" Apple-notarized binary for increased security
*    Assorted compatibility fixes

###  Minor new features:
*    Mark chapters even when cutting commercials
*    Duplicate downloads now fully supported (e.g. high-res/low-res Format subscriptions)
*    Encrypted TiVo Format to download without decrypting
*    Time before download starts now tracked with progress bar
*    Contextual menus selection now behaves like Mail 
*    Ability to limit subscriptions to a specific channel
*    Optional user script upon completion
*    Pushover integration via Applescript ([see Pushover note below](#Notes-On-Pushover))
*    Delete after Download is now an option per Subscription/Download
*    Remote reboot of TiVo 
*    New  -noStereo flag on Default, and now copy AC3 over rather than regenerate
*    Moved "Export Metadata to pyTiVo"  to Advanced Prefs.
*    Added "Allow Duplicate Downloads/Subscriptions" to Advanced Prefs.
*    Removed "Prefer TVDB's episode Info" option as TiVo's data is now accurate through RPC.
*    First-use defaults changed to enable more features; handles dual TiVos better.
*    All helper apps updated (ffmpeg, ccextractor, comskip, mencoder, HandBrakeCLI).

### Notes on SkipMode
#### Overview
With SkipMode, TiVo marks the commercials for certain shows. As TiVo's SkipMode analysis is done by humans, it is almost 100% accurate. However, there are some complications: 1) SkipMode may not appear until hours after a show ends, 2) SkipMode is only available for popular channels/shows, not news or sports, and may randomly be unavailable for an episode of a show that normally has it, 3) SkipMode is not available on TiVo Suggestions, unless you Keep the show on TiVo, and 4) most annoyingly, the only way to get the SkipMode breakpoints is for cTiVo to literally play the video and jump to each segment to find where it starts, thus disrupting viewing on the TiVo for 10-20 seconds per show. cTiVo makes it as easy as possible to take advantage of SkipMode, while falling back to Comskip as needed.

When SkipMode breakpoints become available, they can be automatically retrieved for shows in the Download Queue. If the SkipMode breakpoints aren't available when needed, the download will pause until they become available or until the four-hour wait time expires. To avoid interrupting your viewing, you can schedule a range of times in Preferences that's acceptable for cTiVo to take over your TiVo (see “Auto SkipMode Restricted to” in Preferences>General). Furthermore, in Automatic mode, cTiVo will only retrieve SkipMode breakpoints when your TiVo is playing Live-TV (as that's the default mode for an idle TiVo). cTiVo will not interrupt a show being played back. 

If you prefer not to have cTiVo retrieve automatically, you can disable Auto SkipMode, and the breakpoints can be retrieved manually by selecting a Show or Download and selecting "Get SkipMode from TiVo" from the cTiVo menus (either TiVo menu or right-click contextual menu). 

#### Best of Both Worlds (for Commercials at least):
In Preferences>General>Commercial>Strategy, you can choose whether to use Comskip or SkipMode only, or "SkipMode → Comskip", which means "Use SkipMode but if it's not available, fall back to Comskip instead". if you're concerned about losing any content due to any incorrect guesses in Comskip: set "Commercial Handling" to "SkipMode → Comskip (Mark)", then if you do a Skip on a show, and SkipMode is not available (or fails), then cTiVo will Mark using Comskip instead.

#### So, if you want to use SkipMode...
*	Go to Preferences>General>Commercials
*	Choose whether to Cut or Mark commercials (you can also change this for each download/subscription).
*	Set "Commercials>Strategy" to one of the SkipMode options.
*	Enable "Auto SkipMode" and give it the range of time each day that you're NOT going to be watching TV.
*	Note: if you want SkipMode for any pre-existing subscriptions or scheduled downloads, you'll need to enable it in the respective table rows.

### Notes on Pushover:
[Pushover (pushover.net) is a real-time notification system](https://pushover.net). Due to user requests, cTiVo will now let you know when your shows have completed. To use it, you'll have to sign up with their system, which will give you a userId. Download the attached Applescript, and save it in `~/Library/Application Scripts/com.cTiVo.cTiVo/DownloadDone.scpt `.  After the first successful download, the script will ask for your Pushover userId. (While this process is admittedly a little tedious, it only has to be done once, and Pushover reports back how many people are using the service.  if a lot do, then I'll include turning on the script in the UI.) 

More generally, you could use the same hook to do any post-processing on downloaded shows you wish.  Documentation for now consists of looking at the Pushover script.

### Bug fixes:
*    Allows drag/drop of show folders into Downloads or Subscriptions
*    No longer uses mencoder for TestPS due to occasionally inaccurate results.
*    Not using tvdb's thumbnail images for episodes, as they're not updating them.
*    Ignores all options when using Test PS (, e.g. Cut, Mark, Captions)
*    Shows folders in bold when all shows are onDisk
*    Properly uses subdirectories in cache folder
*    Picks up HD devices on Bonjour
*    Improved audio sync after crossing a commercial on Apple devices with Default Format.
*    Test PS marks both H264/MP2 channels as success.
*    Delays launching download from subscription if no RPC data yet to get episode number correct.
*    Enable RPC when mediaKey provided late*    
*    Avoid images disappearing from folders on refresh
*    Sorting shows within folders
*    Extra check for SSL block by antivirus
*    Detects High-Sierra OS freeze and recovers
*    Detects invalid HTML errors from TVDB
*    Undeleted shows matched up with pending downloads.
*    Paused label no longer interferes with selecting downloads behind it.
*    Change confusing Formats "Hide in User Interface" to "Show in"
*    Fix OnDisk problem for shows with accents
*    Better disk space testing under APFS
*    Removed experimental SubscriptionRelyOnDiskOnly option
*    Many process flow and status reporting fixes
*    Episode information was occasionally wrong when subscription immediately fires, so filename would be wrong.
*    IsQueued flag sometimes was cleared incorrectly when deleting
*    Does not allow sleeping during network download, regardless of user setting.
*    Add check for TiVo's middlemind being unavailable
*    Volume size fix if 0; should help ZFS and some NAS devices
*    Cancel commercialing when show is deleted from TiVo
*    Fix Pref window attaching to wrong place and centering
*    Fix for occasional "TiVos not found" on launch

### Many thanks to: 
moyekj of kmttg fame for leading the way on how to extract the SkipMode info
Bill Tanner for extensive testing.

# Release 3.1.2
* A small release to update the certificate used to communicate with TiVo's RPC mechanism, which otherwise would expire at the end of April.
Also, TVDB has frequently been unresponsive recently, causing cTiVo to be unstable. This fixes the latter part.

# Release 3.1.1
#### New features:
* Option for automatic deletion of show on TiVo after a successful download. (For those of you just using your TiVo as a collection device). In Adv Prefs.
* Option to control number of simultaneous encoders (prev available as Terminal option, now in Adv Prefs)

For those of you using non-default download directories or temporary folders, this release makes a number of cleanups/improvements. Please experiment with these and try to break it!
* If either Download or Temporary drive is not available (when cTiVo launches or while running), cTiVo will pause and ask for a new directory (rather than assuming default).
* However, if external drive then comes online (e.g. a slow-to-connect NAS, or mistakenly ejected external drive), cTiVo will recognize it and automatically continue on.
* Similarly, if there's an error in download directory, say write-protection, then it will ask for new directory (or correct existing problem), not assume default.
* Changed confusing behavior: Download directory is now fixed at start of download process, not creation of download entry. So if you change download directories, all future downloads go to that directory, not just for newly created downloads.
* Default is to now use system-provided user temporary folder rather than /tmp/ctivo to avoid problems with High Sierra

#### Bug Fixes:
Contextual menu `Delete from TiVo` for a folder will now delete all shows in that folder (upon confirmation).
File menu commands `Play Video` and `Show in Finder` now work for Now Playing table (main one), not just for Download table.
More accurate information about sleep prevention (when AppDelegate at Major or above).
Avoids spurious error about Drawer first responder in logs.
Antivirus warning during download as well as NowPlaying access.
Warning if no data received during NowPlaying access.
Avoids RPC crash if manual TiVo created with invalid IP address.
Plugged Memory leak on Downloads

# Release 3.1 (Finally!  Folders)

### Major changes:
* Shows can now be grouped in series folders.
* Advanced Preferences is no longer hidden behind Option key.
* Preferences has simpler directory structure choices (e.g. Plex support)
* Auto-relocation to Applications directory.

### Minor Improvements:
* File template string now reflects directory options.
* Help button on each Preference screen.
* Better warning and diagnostics on disk space (versus tmp space).
* Improved Sleep log notices.
* Allows longer TiVo names.
* Support TiVo's ShowingStartTime (if after Capture date in XML).

### Bug Fixes:
* Significantly better handling of network failures/sleep for RPC.
* Columns resizing believed to be finally fixed.
* Avoid rounding time when scheduling next TiVo checkin.
* Fix \n typo in logs.
* Avoid obscure crashes if missing episode information during RPC reference or resetting TVDB info or subscription.
* Use one keychain reference across all TiVos.

# Release 3.0.1 (Fixes)
(some table formatting issues, and a crash in an obscure RPC scenario)

# Release 3.0 (Artwork and RealTime)
3.0 is a major new release of cTiVo with comprehensive artwork support and much more accurate information due to use of real-time features from TiVo. After extensive beta testing, it is also the most reliable release yet (especially with High Sierra). Note that 3.0 requires Mac OS 10.9 or later.  Earlier systems should continue to use [2.5.1's 10.7 version](https://github.com/mackworth/cTiVo/releases/tag/2.5.1).

#### Artwork enhancements:
New Artwork column in Now Playing List.
Your choice of artwork from TiVo* or theTVDB (Series, Season, Episode, or Movie from theMovieDB).
Manual updates of artwork by drag/drop onto table.
Manual artwork updates apply to files already recorded as well.
Finder Icons now reflect artwork of file.

#### Real-time features:
TiVo now notifies cTiVo as the Now Playing list changes, so new shows are updated instantaneously.*
Ability to "Delete Show from TiVo" (in Edit menu and contextual menu).*
Ability to "Stop Recording show from TiVo"  (in Edit menu and contextual menu).*

#### Season/Episode Information:
Much better matching with TVDB; enhanced statistic information.
Episode and Genre information from TiVo is now correct.*
Manually edit season/episode information in drawer if TiVo is incorrect.

#### Usage notes:
- Thumbnails in Artwork column reflect images that will be added to the show when downloaded. You select which kind of artwork you want in Preferences. You can change the visual size of the image by changing the width of the column, which will increase the height of the row proportionately. If you would like to change it, find a better image and just drag it onto the image in the table.  If you don't want any artwork for a particular show (or to reverse the manual choice), just drag the image to the trashcan. If the show has already been downloaded, cTiVo will even change the artwork in the file on disk.
- As the Now Playing list should always be up to date, we no longer need to refresh regularly (historically every 15 minutes unless changed). For now, I've changed this to every 4 hours, just to make sure there's no sync issues. You can change this in Adv Preferences.
- The RPC capabilities will also work remotely (over a WAN). In Edit>Edit TiVos, you have to set a third port on your router to point to 1413 on your TiVo.

*Starred items require RPC, real-time functionality, only available on TiVo Premiere or later (so not Series 3, HD, or HD XL)

#### Minor changes:
New default (0) for refresh times ( 240 minutes for RPC-enabled and 15 minutes for older devices).
Extended Subscription option (no GUI, set SubscriptionExpirationDays in Console).
Doesn't record Subscriptions if recording already on disk.
"Reload TVDB" contextual menu item.
Newest version of all executables: ffmpeg, mencoder, ccextractor, comskip, Handbrake.
Detects and avoids duplicate TiVos (e.g. WAN and local).
Warning message about disk space before downloads.
Larger program status icons when Art column is showing.
Shared caches between Remote and local cTiVos (ie if you move your laptop back and forth).
Moved artwork and TiVo detail information to Cache folder, where they belong.
Remove iTiVo migration and Growl support.

#### Bug Fixes:
Resets logging of Verbose mode to Major during startup (unless Control-Option held)
High Sierra compatibility issues: during launch, tmp directory, double window, drag/drop, and artwork processing
Remove From Queue contextual menu item working again
Tivos were sometimes not getting called during startup
Allows season zero (specials); formatted as S00Exx
Sorting by episode names now sorts series that have no episode information by Original Air Date
Change to .ts for unencoded files copied over Transport Stream (for compatibility with PyTiVo)
Non-"sticky" messages in notifications should disappear
Cleaned up contextual menus.

#### MPEG-4 Transition:
For those upgrading from 2.4 and earlier, you should be aware that cable companies are migrating from MPEG-2 compressed streams to MPEG-4 (aka H.264). They do this to reduce the size and improve the quality of their signals. They seem to be rolling this out slowly, one market at a time and even one channel at a time. Although this transition required many changes to cTiVo, they should be transparent in normal operation, except that older Formats may be incompatible.

#### Older OS and processors:
If you're still using 10.7 or 10.8, you'll need to use [2.5.1's 10.7 release](https://github.com/mackworth/cTiVo/releases/tag/2.5.1). In addition, if you have an older processor, you may get an incompatibility warning which might also require that version. Due to the included binaries from other open-source efforts, it's impossible to support these older systems. The 2.5.1 release has the older binaries (such as mencoder, ffmpeg, ccextractor etc) but otherwise should run fine.

#### Older TiVos:
If you have a TiVo Series3 or older, then you may have received an offer to upgrade as it won't be compatible at all with the H.264 transition. In adddition, although TiVo HD and HD-XL do work with the MPEG-4 signals, they unfortunately will not properly transfer the files to the Mac, so they will become unusable with cTiVo for channels migrated to MP4. Furthermore, Series 3 and HDs do not support cTiVo's new real-time functionality so several features (starred above) will not operate, and the season/episode information should be retrieved from theTVDB instead.

Much thanks to Kevin Moye (of KMTTG fame) and Anthony Lieuallen for blazing the trail on the totally undocumented TiVo RPC information.


# Release 2.5 (H.254 and redesigned Formats)
2.5 is a major upgrade to cTiVo. There's been extensive beta testing, so it is even more reliable than 2.4.4, but please let us know if you have any problems at all in the [Issues area](https://github.com/mackworth/cTiVo/issues).

## MPEG-4 Transition
Comcast and other cable companies are migrating from MPEG-2 compressed streams to MPEG-4 (aka H.264). They do this to reduce the size and improve the quality of their signals. Comcast seem to be rolling this out slowly, one market at a time and changing over one channel at a time. Although this transition requires many changes to cTiVo, they are transparent in normal operation, except that older Formats may be incompatible. With this release, we've provided a whole new set of Formats, and taken the opportunity to make the Format selection process easier. 

## Major Changes in 2.5
* H.264 compatibility (new format for cable companies)
* Autodetects H.264 transition by channel
* Redesigned Formats (simpler, more compatible)
* New Channels preference screen
* Better handling for AC3 5.1 audio
* Many bug fixes

##  New Formats
*  New ffmpeg Formats
<table>
<tr><td>Higher Quality</td><td>1080p</tr>       
<tr><td>Default</td><td>iPhone/iPad</tr> 
<tr><td>Faster</td><td>Smallest </tr> 
<tr><td>Standard Def</td><td></td></tr>    
</table>    
*  New HandBrake Formats (Old ones deprecated)
<table>
<tr><td>HB SuperHQ</td><td>HB 1080p</tr>       
<tr><td>HB Default</td><td>HB Android</tr> 
<tr><td>HB Tiny</td><td>HB Roku </tr> 
<tr><td>HB XBox</td><td>HB Std Def</td></tr>    
</table> 
*  All mencoder-based Formats are now marked as "Not Recommended"; warned if used
*  Format Help command in Format menus to guide usage

## Other significant changes versus 2.4.4
1) Updated versions of all binaries. In particular, comskip should perform much better, and HandBrake has a large number of new presets
2) `ffmpeg` encoder included
3) New tivodecode-ng, as well as option for Java-based TiVoLibre
4) New Filename template keywords: Guests, StartTime, Format, and ExtraEpisode
5) Better Plex folder naming
6) Caption and commercial failures  no longer fail download, just reports failure but continues
7) New "OnDisk" column in tables to sort by whether downloaded file already exists on disk
8) New "H.264" column in tables indicates whether a channel has migrated to H.264 yet
9) New Edit Channels preferenc page for H.264 status
10) Channels page can also specify "commercial-free" channels, such as PBS, to avoid running comskip
11) New "Waiting" status for the time between downloads required to allow TiVo to rest
12) Anonymously reports via Crashlytics which Formats are used, to inform future development
13) Changes needed for Rovi data transition
14) Lower CPU priority of background tasks to avoid swamping user interface
15) New ffmpeg script, which allows use of comskip and 5.1/AC3 audio with ffmpeg (contributed by Ryan Child)
16) Assistance in creating Handbrake preset-based Formats, including custom presets
17) Hidden feature: Allows "duplicate" downloads: more than one Download accessing the same show ( Requires `defaults write AllowDups YES` in Terminal. Use at your own risk for now, let us know of any problems.
18) Misc fixes:
*  Better handling if tmp directory is not available
*  Fix for Addressbook access in Sierra
*  Detect and warn TivoHD users that they can't do Transport Streams
*  Detect and warn when antivirus may be blocking server
*  Many crashing bug fixes

## Older OS and processors
If you're still using 10.7 or 10.8, you'll need to use the cTiVo-10.7 file below; everyone else should use the cTiVo file. In addition, if you have an older processor, you may get an incompatibility warning. Due to the included binaries from other open-source efforts, it's getting much harder to support these older systems, but given the H.264 conversion, We wanted to provide at least one more release. But be aware that after this release, we may not be able to keep it up to date. It has the older binaries (such as mencoder, ffmpeg, ccextractor etc) but otherwise should run fine. The 10.9 version, on the other hand, should be both faster (especially comskip) and properly handle more video files.

## Older TiVos
If you have a TiVo Series3 or older, then you may have received an offer to upgrade as it won't be compatible at all with the H.264 transition. In adddition, although TiVo HDs do work with the MPEG-4 signals, they unfortunately will not properly transfer the files to the Mac, so they will become unusable with cTiVo for channels migrated to MP4.

 ## Transferring the file from your TiVo
 As a digression, there are some very confusing terms here. Video people talk about "Streams", the types of content inside a file or transmission such as a MPEG-2  video stream or an 5.1-channel AC3 audio stream, which are then stored in "Containers", a standardized file format, such as .AVI or .MPG .  Particularly confusing is that the MPEG-4 standard defines both a compression algorithm for a stream (MPEG-4, aka H.264) and a container file format (.MP4). If you'd like to see what's inside a file, I've also posted a new version of the open-source MediaInfo program, which shows you the different streams and their formats for all known container types.
 
 This H.264 change causes TiVo to move from Program Stream (PS) to Transport Stream (TS) transmission. After a channel converts to H.264, then accessing a show via PS no longer works. (Apparently just to be amusing, the TiVo still does send over a file on PS, but that file now only contains an audio channel.) The good news is that TS is significantly smaller than PS.  Generally, TS does work with MPEG-2 video as well, so one could switch over completely, but there may sometimes be decryption problems. Thus, cTiVo still uses Program Streams by default, but will automatically detect when a channel has migrated to H.264 and switch to use Transport Streams on that channel from then on.
 
 While this will happen automatically, there is a new Preference panel, Channels, which tells you the status of each channel. This panel will also let you ask cTiVo to test every channel that you currently have a recording for (including suggestions). These tests will run quite quickly as it only downloads enough of each show to test it. Thus, you should be able to test all your channels within a couple hours.



# Release 2.5; Beta 1 
### TL; DR:
Cable companies are migrating to H.264 video streams, requiring many changes to cTiVo. Most of these changes should now be transparent in operation, but many of the old Formats won't work with these new streams, and we'll be revamping them. There's a new Preferences screen Channels which will show if channels have converted to H.264.

## Notice: Formats expected to change
The `mencoder` program we have used for many of the original Formats (e.g. iPhone, AppleTV, iPod, H.264, DVD, QuickTime, PSP, YouTube) seems to be increasingly broken, with no active work going on to repair it. We're planning to change to `ffmpeg` as the primary converter, which means a lot of the existing Formats will change in an upcoming release. Existing subscriptions and queue items will still connect to the (renamed) older Formats, but there'll be new ones recommended for everyday use.  FYI, Some of the problems with mencoder are: Frequent incompatibility with the new H.264 formats; audio being dropped; doubling of video length, problems with commercial skipping, and other miscellaneous ones.

I really need help testing all the different combinations and Formats. Any volunteers out there who can help test and, in particular, find the best way to re-encode the interlaced MP4 content to make them compatible with iTunes and iDevices would be great!

Nonetheless, I believe 2.5 Beta1 is significantly more stable than the current release, so I encourage wide usage. Any comments/discussions here at: https://github.com/mackworth/cTiVo/issues/163

# Background
As you may have read, Comcast and other cable companies is in the process of converting from MPEG-2 compression to MPEG-4 compression (aka H.264) They do this to reduce the size and improve the quality of a channel. Comcast seem to be rolling this out slowly, one market at a time and changing over one channel at a time.  If you have an active older TiVo, then you may have received an offer to upgrade as it won't be compatible with this transition. This change has implications, choices, and limitations on each phase of cTiVo's processing. 

As a digression, there are some very confusing terms here. Video people talk about "Streams", the different types of content that are inside a file or transmission such as a video stream in MPEG-2 compression or an audio stream in 5.1 AC3 format, which are then stored in "Containers", a standardized format for a file, such as .AVI or .MPG.  Particularly confusing is that the MPEG-4 standard defines both a compression algorithm for a stream (MPEG-4, aka H.264) and a container file format (.mp4). If you'd like to see what's inside a file, I've also posted a new version of the open-source MediaInfo program, which shows you the different streams and their formats for all known container types.

## Step 1: Transferring the .tivo file
Unfortunately, this H.264 change causes TiVo to move from Program Stream (PS) to Transport Stream (TS) transmission. After a channel converts to H.264, then accessing a show via PS no longer works. (Oddly, the TiVo still sends over a file on PS, but that file now only contains an audio channel.) The good news is that TS is significantly smaller than PS.  Generally, TS does work with MPEG-2 video as well, so one could switch over completely, but there are sometimes decryption problems (see below). Thus, cTiVo still uses Program Streams by default, but will automatically detect when a channel has migrated to H.264 and switch to use Transport Streams on that channel from then on.

While this should happen automatically, there is a new Preference panel Channels, which tells you the status of each channel. This panel will also let you ask cTiVo to try every channel that you currently have a recording for (including suggestions). These will run quite quickly as it only downloads enough of each show to test it (although it then waits a minute as usual to avoid overloading the TiVo downloader). Thus, you should be able to test all your channels within a couple hours.

## Step 2: Decrypting the .tivo file to an MPG file
The .tivo files are encrypted with your Media Access Key (MAK), which is why cTiVo needs that key to download your shows. The old program "tivodecode" doesn't handle Transport Stream at all. Two new programs, `tivodecode-ng` and `TivoLibre`, do handle that as well as the H.264 compression format. So there is now a pull-down in Advance Preferences to choose which decryption to use. AFAIK, there should be no reason to continue to use `tivodecode`, so I have shifted to `tivodecode-ng` as the default case. I have left tivodecode as an option just in case, but it will be removed in the final release unless I hear otherwise. (Specifically, if `tivodecode-ng` fails on a Program Stream download but `tivodecode` works, please let me know.) There is an alternative, `TiVoLibre`, which may handle more cases, but requires Java runtime to be installed on your Mac, which Apple no longer recommends.  

The problem is that as we said, in testing, a few MPEG2 files that transmitted via Transport Stream are trashed when converted with either program, and it's unclear at this point whether this is due to a problem with the decryption software or if the original file is broken. For better or worse, the same file sent over Program Stream works fine, hence the continued use when possible.

## Step 3: Encoding the MP4 (Formats)
As said above, `mencoder` doesn't seem to work well with any of the TS files. `HandBrake` seems to be ok. I'm now bundling `ffmpeg` as well, and as mentioned above, will move to it as the default shortly.

`Decrypted TiVo Show` just decrypts the .tivo file into an .MPG file, doing as few changes as possible. As we move to H.264 streams, theoretically, this should mean that we don't need to re-encode them, which is the longest (and most CPU-intensive) part of the downloading process. We have provided an `MP4 FFMpeg`  Format, which simply copies the audio and video streams into an MP4 format with very little overhead, operating at the full download speed. `MP4 FFMpeg` will be a better choice for most people to just copy the file over without re-encoding. Few applications expect to see H.264 streams inside an MPG container, and the MP4 container also lets us add the other metadata, commercial marking and subtitle information.

However, I've seen two problems with this: first, if you do this with an MP2 channel, the resulting file will not be playable with QuickTime Player (although VLC works fine). Second, interlaced MP4 files are incompatible with iTunes and iOS devices, meaning that we have to re-encode (except for 720p shows). On the other hand, it has been reported that these files do work well with Plex; let me know if you find otherwise. I'd also like to know if they work well with pyTiVo.

I'm also pleased to report that we've also added a `FFMpeg Comskip/5.1` format which adds commercial-skipping capabilities to ffmpeg. Thanks to Ryan Child for his impressive shell programming to pull off this trick. It also will detect 5.1 AC3 audio in the TiVo file, and create both a 5.1 and stereo version in the output file for maximum compatibility. The shell script still passes through other ffmpeg options (with a few limitations), so you should be able to use this in conjunction with your own parameter choices. This will probably be the basis of many of the new Formats to come.

## Other major changes versus 2.4.4
1) Updated versions of all binaries. comskip, in particular, should perform much better.
* ccextractor 0.79
* comskip 0.81.089
* MEncoder 1.3.0-4.2.1 (C) 2000-201
* HandBrake 0.10.1 (2015030800)
* ffmpeg 3.1.3

2) Added `ffmpeg` binary
3) Filename template keywords Guests, StartTime, and ExtraEpisode
4) Better Plex folder naming
5) Caption and commercial failures will no longer fail download, just reports failure.
6) New "OnDisk" column in tables to sort by whether downloaded file already exists on disk
7) New "H.264" column in tables indicates whether a channel has migrated to H.264 yet
8) Channels page can also specify "commercial-free" channels, which then avoids running comskip
9) New "Waiting" status for the time between downloads to allow TiVo to rest
10) Anonymously reports via Crashlytics which Formats are used, to inform future development
11) Changes needed for Rovi data transition
12) Lower CPU priority of background tasks to avoid swamping user interface
13) Many fixes for multitasking, iTunes, comskip, and Subscriptions.

# Detailed changes versus Alpha 10:
* New ffmpeg Format, which allows comskip and 5.1AC3 to be used with ffmpeg (contributed by Ryan Child)
* New ffmpeg bash script can be used as a base for many interesting uses of ffmpeg
* No need to confirm delete download if in Waiting mode
* Initial changes for Rovi transition	
* avoid Rovi copyright msessages (and the *’s as well)
* Avoid using Rovi numbers with theTVDB
* Lower CPU priority of background tasks to avoid swamping user interface
* New column H.264 indicates whether a channel has mgirated
* Removed QuickTime MP1, MP2-HD, and Zune Formats (let me know if you want one of these)
* During Detail debug mode in TaskChain, prints out full config and command line invocation of helper apps
* Updated all binaries to latest version
* Allow encoding despite caption/commercial failure
* Warns of empty file after encoding

Fixes:
* Much testing and fixes around certain Format configuration flows
* Subscription information now being properly recorded for new users.
* Pause Queue and Quit will now properly complete the current show (if requested)
* Don’t crash if iTunes is Frozen
* Fixes Play-Video crash in pre-Maverick systems



====================
RELEASE 2.5 ALPHA 10
((Release 10 should fix new Channel test process problem in v9
 Bug Note: if you're not on El Capitan, don't "open video files in Finder" from cTiVo with this release. It will crash))

### Commercial:
 I really need help testing all the different combinations and Formats. I know some of the existing Formats work with the MPEG4 channels, and some don't. Any volunteers out there who can help test and, in particular, find the best way to re-encode the interlaced MP4 content to make them compatible with iTunes and iDevices would be great!
 
 Any comments/discussions here at: https://github.com/mackworth/cTiVo/issues/163
 

# Overview
 As you may have read, Comcast is in the process of converting from MPEG-2 compression to MPEG-4 compression (aka H.264) They (and I assume others soon as well) do this to reduce the size and improve the quality of a channel. Comcast seem to be rolling this out slowly, one market at a time and changing over one channel at a time.  If you have an active older TiVo, then you may have received an offer to upgrade as it won't be compatible with this transition.
 
 This change has implications, choices, and limitations on each phase of cTiVo's processing. The purpose of this alpha release is to allow more people to experiment with the different possibilities. As such, for now, you'll need to understand some of the current tradeoffs to successfully use the alpha. As I'll discuss below, if these changes work well for people, then I can hide some of the complexity while still maintaining the option for controlling the cTiVo's behavior as we traditionally have done.
 
 As a digression, there are some very confusing terms here. Video people talk about "Streams", the different types of content that are inside a file or transmission such as a video stream in MPEG-2 compression or an audio stream in 5.1 AC3 format, which are stored in "Containers", a defined overall format for a file, such as .AVI or .MPG.  The MPEG-4 standard, in particular, defines both a compression algorithm for a stream (MPEG-4, aka H.264) as well a container file format (.mp4). If you'd like to see what's inside a file, I've also posted a new version of the open-source MediaInfo program, which shows you the different streams and their formats for all known container types.
 
 In initial testing, mencoder doesn't seem to work well with any of the TS files. Handbrake seems to be ok. I'm now bundling ffmpeg as well. One of the best choices is "MP4 ffmpeg" Format, which will convert the downloaded TS files directly into MP4s, which can then have metadata, including commercial skip information included. This operates very quickly as no transcoding is performed. The only bad news is that iTunes doesn't accept interlaced files. HD files are typically delivered in either 720p or 1080i, so the first case works great, but the second fails to import into iTunes.
 
 As I said, to finish up a beta release, I'm hoping that someone will volunteer to help with the encoders. First, testing the different Formats with all the different options. Second, figuring out why mencoder fails with TS files. Third, figuring out who to use ffinfo or ffmpeg to identify 720p v 1080i files and finally, the best/fastest way to convert 1080i files to be compatible with iTunes/iDevices/Apple TV. 

## Step 1: Transferring the .tivo file
 Unfortunately, this change requires TiVo to move from Program Stream (PS) to Transport Stream (TS) transmission. After a channel converts to H.264, then accessing a show via PS no longer works. Confusingly, the TiVo still sends over a file, but that file only contains an audio channel. Generally, TS does work with MPEG-2 video as well, so one could switch over completely, but there are sometimes decryption problems (see below). The good news is that TS is significantly faster than PS on transmission; the even better news is that the files themselves can be much smaller.  The Alpha9 version will use Program Streams by default. Then cTiVo should now automatically detect when a channel has been migrated to H.264 and switch it to use Transport Streams from then on.
 
 There is a new Preference panel Channels, which tells you the status of each channel. This panel will also let you ask cTiVo to try every channel that you currently have a recording for (including suggestions). These will run quite quickly as it only downloads enough of each show to test it (although it then waits a minute as usual to avoid overloading the TiVo downloader). Thus, you should be able to test all your channels in a couple hours.

## Step 2: Decrypting the .tivo file to an MPG file
 The .tivo files are encrypted with your Media Access Key (MAK), which is why cTiVo needs that key to download your shows. The old program "tivodecode" doesn't handle Transport Stream at all. Two new programs, `tivodecode-ng` and `TivoLibre`, do handle that as well as the H.264 compression format. So there is now a pulldown in Advance Preferences to choose which decryption to use. AFAIK, there should be no reason to continue to use `tivodecode`; we know of no cases where tivodecode works but these new ones don't, so I have shifted to `tivodecode-ng` as the default case. I have left tivodecode as an option just in case. (Specifically, if the new ones fail on a Program Stream download, and you want to try shifting back. Let me know if that occurs to you; we'd really want to get copies of the .tivo files that failed with tivodecode-ng, but worked with tivodecode.) There is an alternative, `TiVoLibre`, which seems to handle more cases, but requires Java runtime to be installed on your Mac, which Apple no longer recommends.  So the plan is to make `tivodecode-ng` the default unless people run into problems with it.
 
 The problem is that in testing, a few MPEG2 files that transmitted via Transport Stream are trashed when converted with either program, and it's unclear at this point whether this is due to a problem with the decryption software or if the original file is broken. For better or worse, the same file sent over Program Stream works fine.

## Step 3: Encoding the MP4
 One exciting possibility is that the video streams are now already in H.264 format, which would mean that we don't need to re-encode them, which is the longest (and most CPU-intensive) part of the downloading process. However the .MPG container doesn't permit storing other information. Thus we have provided an `MP4 FFMpeg`  Format, which simple "re-muxes" the audio and video streams into an MP4 format with very little overhead, operating at the full download speed. I've seen two problems with this: first, if you do this with an MP2 channel, the resulting file will not be playable with QuickTime Player (although VLC works fine). Second, with MP4 files, the resulting file is incompatible with iTunes (I believe because it is interlaced.) It has been reported that these files work well with Plex; let me know if you find otherwise. I'd also like to know if they work well with pyTiVo.

## Formats:
 So, you currently have the choice of `Decrypted TiVo Show`, which decrypts the .tivo file into an .MPG file, essentially doing as few changes as possible. I believe the `MP4 FFMpeg`) will be a better choice for most people. Few applications expect to see H.264 streams inside an MPG container, and the MP4 container lets us add all the other metadata, commercial marking and subtitle information.n.

## Multitasking:
 I believe I have finally tracked down the last multitasking bug. This one leads to a crash approximatly one out of every 200 runs of the program (as reported by Crashlytics). To fix it required a signficant refactoring of the core multitasking code, so please let me know if you see any problems (especially UI freezes, or background processing that just stops). After enough usage, Crashlytics will tell me if the problem is actually fixed.

## Other changes:
 1) Updated versions of all binaries. Comskip, in particular, should perform better.
 * ccextractor 0.79
 * comskip 0.81.089
 * MEncoder SVN-r37561
 * HandBrake 0.10.1 (2015030800)
 * tivodecode w/o powerPC support
 
 2) Added `ffmpeg` binary
 3) Filename template keywords Guests, StartTime, and ExtraEpisode
 4) Choosing `comskip` will now be remembered across runs
 5) Better Plex folder naming
 6) Caption failures will no longer fail download, just reported.
 7) New "OnDisk" column in tables to sort by whether downloaded file already exists on disk
 8) Channels page can now specify "commercial-free" channels which will then avoid running comskip
 9) New "Waiting" status for the time between downloads
 
-->
