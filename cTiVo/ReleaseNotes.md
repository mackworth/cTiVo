# Release 2.5; Beta 1 

### TL; DR:
Cable companies are migrating to H.264 video streams, requiring many changes to cTiVo. Most of these changes should now be transparent in operation, but many of the old Formats won't work with these new streams, and we'll be revamping them. There's a new Preferences screen Channels which will show if channels have converted to H.264.

##Notice: Formats expected to change
The `mencoder` program we have used for many of the original Formats (e.g. iPhone, AppleTV, iPod, H.264, DVD, QuickTime, PSP, YouTube) seems to be increasingly broken, with no active work going on to repair it. We're planning to change to `ffmpeg` as the primary converter, which means a lot of the existing Formats will change in an upcoming release. Existing subscriptions and queue items will still connect to the (renamed) older Formats, but there'll be new ones recommended for everyday use.  FYI, Some of the problems with mencoder are: Frequent incompatibility with the new H.264 formats; audio being dropped; doubling of video length, problems with commercial skipping, and other miscellaneous ones.

I really need help testing all the different combinations and Formats. Any volunteers out there who can help test and, in particular, find the best way to re-encode the interlaced MP4 content to make them compatible with iTunes and iDevices would be great!

Nonetheless, I believe 2.5 Beta1 is significantly more stable than the current release, so I encourage wide usage. Any comments/discussions here at: https://github.com/dscottbuch/cTiVo/issues/163

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
As said above, `mencoder` doesn't seem to work well with any of the TS files. `Handbrake` seems to be ok. I'm now bundling `ffmpeg` as well, and as mentioned above, will move to it as the default shortly.

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
o New ffmpeg Format, which allows comskip and 5.1AC3 to be used with ffmpeg (contributed by Ryan Child)
o New ffmpeg bash script can be used as a base for many interesting uses of ffmpeg
o No need to confirm delete download if in Waiting mode
o Initial changes for Rovi transition	
o avoid Rovi copyright msessages (and the *’s as well)
o Avoid using Rovi numbers with theTVDB
o Lower CPU priority of background tasks to avoid swamping user interface
o New column H.264 indicates whether a channel has mgirated
o Removed QuickTime MP1, MP2-HD, and Zune Formats (let me know if you want one of these)
o During Detail debug mode in TaskChain, prints out full config and command line invocation of helper apps
o Updated all binaries to latest version
o Allow encoding despite caption/commercial failure
o Warns of empty file after encoding

Fixes:
o Much testing and fixes around certain Format configuration flows
o Subscription information now being properly recorded for new users.
o Pause Queue and Quit will now properly complete the current show (if requested)
o Don’t crash if iTunes is Frozen
o Fixes Play-Video crash in pre-Maverick systems


<!---
====================
RELEASE 2.5 ALPHA 10
((Release 10 should fix new Channel test process problem in v9
 Bug Note: if you're not on El Capitan, don't "open video files in Finder" from cTiVo with this release. It will crash))

### Commercial:
 I really need help testing all the different combinations and Formats. I know some of the existing Formats work with the MPEG4 channels, and some don't. Any volunteers out there who can help test and, in particular, find the best way to re-encode the interlaced MP4 content to make them compatible with iTunes and iDevices would be great!
 
 Any comments/discussions here at: https://github.com/dscottbuch/cTiVo/issues/163
 

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
