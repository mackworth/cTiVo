**cTiVo** is a free Mac application to download shows from your TiVo and convert them to many popular formats and devices. Its goal is to be extremely simple to set up and use, taking full advantage of the MacOS, but very flexible. 

cTiVo provides complete hands-off operation: once you choose or subscribe to your shows, everything else is automated. For example, after you've set it up, every morning, you will find all your favorite shows from your TiVos loaded onto your iPhone or iPad. And although using cTiVo is very easy, you also have complete control over what it does.

cTiVo was inspired by the great work done on iTiVo, but written in Cocoa/Objective C for better performance and  compatibility.

## Automatic Download and Conversions
  * Auto-discovery of all your TiVos (using Bonjour).
  * Drag/drop and contextual menus for ease of use; submit, reschedule, delete all by dragging the shows.
  * Download queue for batch processing, restored on restart.
  * 'Subscriptions' to your regular shows: automatically downloading shows whenever new episodes are available.
  * Even subscribe to "ALL" shows, including suggestions or not
  * Removes commercials from downloaded shows, or just mark for quick skip in player.
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
  * Specify filename formats for compatability with Plex or other media systems.
  * Support for different encoders, including HandBrake, mencoder, ffmpeg, Elgato.
  * Scheduling of when the queue will be processed.
  * Options to prevent sleep or quitting until processing complete.
  * Access remote TiVos (requires network reconfiguration).
  * Folders optionally created for each series.

## Information About Your Shows
  * Customizable columns about shows, downloads and subscriptions; show exactly what you want to see and no more.
  * Detailed info available for each show.
  * Contextual menus to play downloaded video, show in Finder, etc.
  * See which shows have already been downloaded with Spotlight tracking of shows already downloaded by cTiVo.
  * Filter which shows are seen by keywords or TiVo.
  * Show/Hide copy-protected shows and TiVo suggestions.
  * Notifications when downloads complete.

## 3.0 features
#### Artwork enhancements:
New Artwork column in Now Playing List.
Your choice of artwork from TiVo* or theTVDB (Series, Season, Episode, or Movie from theMovieDB).
Manual updates of artwork by drag/drop onto table.
Manual artwork updates apply to files already recorded as well.
Finder Icons now reflect artwork of file.

#### Real-time features:
TiVo now notifies cTiVo as the Now Playing list changes, so new shows are updated instantaneously.*
Ability to "Delete Show from TiVo" (in Edit menu and contextual menu).*
Ability to "Stop Recording show from TiVo" (in Edit menu and contextual menu).*

*Starred items require RPC, real-time functionality, only available on TiVo Premiere or later (so not Series 2, 3, HD, or HD XL)

## 2.5.0 features

* H.264 compatibility (new format for cable companies)
* Autodetects H.264 transition by channel
* Redesigned Formats (simpler, more compatible)
* New Channels preference screen
* Better handling for AC3 5.1 audio
* Many bug fixes

## To install:

Download the [cTiVo application](https://github.com/dscottbuch/cTiVo/releases), and drag it to your Applications Folder.

## Documentation:

[How to get cTiVo running quickly](Quick-Start)
[Quick overview of cTiVo for iTiVo users](iTiVo-Users)
[Overview of Using cTivo](Overview)
[How to install cTiVo](Installation)
[How to configure cTiVo ](Configuration)
[How to set up and configure subscriptions in cTiVo](Subscriptions)
[Frequently Asked Questions](FAQ)
[User-contributed alternative video formats](Alternative-Formats)
[Q and A on different video formats](Video-Formats)
[Other Advanced Topics](Advanced-Topics)

cTiVo is fully compatible with OS X High Sierra (10.13) back through Mavericks (10.9); not compatible with Snow Leopard (10.6) or earlier. In addition, we provide a special version (cTiVo-10.7) for use with 10.7 and 10.8, but support is limited.

*cTiVo* is free to use, and the source is available for anyone to browse and contribute to. Please let us know of any problems/suggestions at [Issues](https://github.com/dscottbuch/cTiVo/issues).
