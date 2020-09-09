**cTiVo** is a free Mac application to download shows from your TiVo and convert them to many popular formats and devices. Its goal is to be extremely simple to set up and use, taking full advantage of the MacOS, but very flexible. 

cTiVo provides complete hands-off operation: once you choose or subscribe to your shows, everything else is automated. For example, after you've set it up, every morning, you will find all your favorite shows from your TiVos loaded onto your iPhone or iPad. And although using cTiVo is very easy, you also have complete control over what it does.

cTiVo was inspired by the great work done on iTiVo, but written in Cocoa/Objective C for better performance and compatibility.

The current release is here:  https://github.com/mackworth/cTiVo/releases/

NOTE: Until recently, TiVo's new Edge product was incompatible with any PC/Mac downloads, but it appears that TiVo has finally fixed this with software release 21.9.7.v3-USM-12-D6F.
(If anyone can confirm this, that would be great.)

## Automatic Download and Conversions
* Auto-discovery of all your TiVos (using Bonjour).
* Drag/drop and contextual menus for ease of use; submit, reschedule, delete all by dragging the shows.
* Download queue for batch processing, restored on restart.
* 'Subscriptions' to your regular shows: automatically downloading shows whenever new episodes are available.
* Even subscribe to "ALL" shows, including suggestions or not.
* Removes commercials from downloaded shows, or just mark for quick skip in player.
* Uses TiVo's SkipMode when available, or analyzes content to locate commercials.
* Extracts closed caption info (adjusted for removal of commercials); adds to MPEG and creates subtitle files.
* Adds artwork to downloaded shows from TiVo or theTVDB and theMovieDB (as available).
* Copies shows to iTunes with all data about the show (metadata) transferred as well.
* Generates metadata appropriate for use by tools such as pyTivo and Plex.
* Performs an 'iTunes sync' to your device when the download is completed. 
* Maximum parallel processing, including downloading from multiple TiVos simultaneously.
* Wide selection of predefined video Formats.
* Target devices include iPhone, iPad, AppleTV, Xbox, YouTube.

## Complete Control Over Process
* Change conversion formats for each download or subscription.
* Change commercial handling/captioning/metadata/iTunes submittal for each download or subscription.
* Change download directories for each download.
* Create custom Formats with completely customizable encoder options for multiple formats.
* Show only the encoding formats you actually use.
* Specify filename formats for compatibility with Plex or other media systems.
* Support for different encoders, including HandBrake, mencoder, ffmpeg, Elgato.
* Scheduling of when the queue will be processed.
* Options to prevent sleep or quitting until processing complete.
* Access remote TiVos (requires network reconfiguration).
* Folders optionally created for each series.
* Provides a Remote Control to run your TiVo from your Mac.

## Information About Your Shows
* Customizable columns about shows, downloads and subscriptions; show exactly what you want to see and no more.
* Detailed info available for each show.
* Contextual menus to play downloaded video, show in Finder, etc.
* See which shows have already been downloaded with Spotlight tracking of shows already downloaded by cTiVo.
* Filter which shows are seen by keywords or TiVo.
* Show/Hide copy-protected shows and TiVo suggestions.
* Notifications when downloads complete.

## To install:

Download the [cTiVo application](https://github.com/mackworth/cTiVo/releases), and run it. It will ask if OK to move to Applications folder. It will automatically find your TiVos, and show you what's available.

## Documentation:

* [How to get cTiVo running quickly](../../wiki/Quick-Start)
* [Overview of Using cTivo](../../wiki/Overview)
* [How to install cTiVo](../../wiki/Installation)
* [How to configure cTiVo ](../../wiki/Configuration)
* [How to set up and configure subscriptions in cTiVo](../../wiki/Subscriptions)
* [Frequently Asked Questions](../../wiki/FAQ)
* [Commercials and cTiVo](../../wiki/Commercials)
* [User-contributed alternative video formats](../../wiki/Alternative-Formats)
* [Q and A on different video formats](../../wiki/Video-Formats)
* [Other Advanced Topics](../../wiki/Advanced-Topics)

cTiVo is fully compatible with MacOS Catalina (10.15) back through Mavericks (10.9).

**cTiVo** is free to use, and the source is available for anyone to browse and contribute to. Please let us know of any problems/suggestions at [Issues](https://github.com/mackworth/cTiVo/issues).


## Recent features

#### SkipMode use *
*    Use TiVo's SkipMode info when available for Marking/Cutting commercials.
*    Hold off processing until SkipMode arrives (or doesn't).
* Fallback to Comskip if SkipMode unavailable or fails.
* There are some issues to be aware of, so please see [Commercial wiki page](Commercials).

#### MPEG2 streams only download over a Transport Stream connection.
*  New Download column "Use TS". Set by channel's TS status initially, but changes automatically after bad download.
*  New Advanced Preference: Allow MPEG2 in Transport Streams (Regardless, will retry with Program Stream if MPEG2 fails encoding).
*  Each show now has a column for whether it is MPEG2 or H264 (measured by either actual download attempt OR by the channel).

#### Remote Control Window
*    TiVo remote control emulation.
*    Keystroke alternatives.
*    Directly select streaming services.
*    Information about current status of TiVo (disk space, activity, network etc).

#### TiVo menu *
*    Play / Delete / Stop Recording on TiVo.
*    Reload Information.
*    Reboot TiVo.

#### Catalina Mojave Support
*    Dark Mode.
*    Works with TV app in Catalina as well as iTunes in prior releases.
*    Permissions check and warnings.
*   "Hardened" Apple-notarized binary for increased security.

###  Minor features:
*    Mark chapters even when cutting commercials.
*    Duplicate downloads now fully supported (e.g. high-res/low-res Format subscriptions)
*    Encrypted TiVo Format to download without decrypting.
*    Time before download starts now tracked with progress bar.
*    Contextual menus selection now behaves like Mail.
*    Ability to limit subscriptions to a specific channel.
*    Optional user script upon completion.
*    Pushover integration via Applescript ([see Pushover note below](#Notes-On-Pushover)).
* Delete after Download is now an option per Subscription/Download.
* Remote reboot of TiVo.
* New  -noStereo flag on Default, and now copy AC3 over rather than regenerate.
* Moved "Export Metadata to pyTiVo"  to Advanced Prefs.
* Added "Allow Duplicate Downloads/Subscriptions" to Advanced Prefs.
* Removed "Prefer TVDB's episode Info" option as TiVo's data is now accurate through RPC.
* First-use defaults changed to enable more features; handles dual TiVos better.
* All helper apps updated (ffmpeg, ccextractor, comskip, mencoder, HandBrakeCLI).

## 3.1 features
* Improved handling of Download and Temporary directories
- If either drive is not available, cTiVo will pause and ask for a new directory (rather than assuming default).
* Option for automatic deletion of shows after successful download

## 3.0 features
#### Artwork enhancements:

* New Artwork column in Now Playing List.
* Your choice of artwork from TiVo* or theTVDB (Series, Season, Episode, or Movie from theMovieDB).
* Manual updates of artwork by drag/drop onto table.
* Manual artwork updates apply to files already recorded as well.
* Finder Icons now reflect artwork of file.

#### Real-time features:

* TiVo now notifies cTiVo as the Now Playing list changes, so new shows are updated instantaneously.*
* Ability to "Delete Show from TiVo" (in Edit menu and contextual menu).*
* Ability to "Stop Recording show from TiVo" (in Edit menu and contextual menu).*

\*Starred items require RPC, real-time functionality, only available on TiVo Premiere or later (so not Series 2, 3, HD, or HD XL)

## 2.5.0 features

* H.264 compatibility (new format for cable companies)
* Autodetects H.264 transition by channel
* Redesigned Formats (simpler, more compatible)
* New Channels preference screen
* Better handling for AC3 5.1 audio
* Many bug fixes

