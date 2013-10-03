**cTiVo** is a free Mac application to download shows from your TiVo (Premiere, HD, S3 or S2 devices) and convert them to many popular formats and devices. Its goal is to be extremely simple to set up and use, but very flexible. 

cTiVo provides complete hands-off operation: once you choose or subscribe to your shows, everything else is automated. For example, after you've set it up, every morning, you will find all your favorite shows from your TiVos loaded onto your iPhone or iPad. And although using cTiVo is very easy, you also have complete control over what it does.

cTiVo is inspired by the great work done on iTiVo, but written in Cocoa/Objective C for better performance and  compatibility. Current or former users of iTiVo will find a detailed comparison and upgrade path described in [iTivo Users](wiki/iTiVoUsers.md).

##Automatic Download and Conversions
  * Auto-discovery of all your TiVos using Bonjour.
  * Drag/drop and contextual menus for ease of use; submit, reschedule, delete all by dragging the shows.
  * Download queue for batch processing, restored on restart.
  * 'Subscriptions' to your regular shows: automatically downloading shows whenever new episodes are available.
  * Removes commercials from downloaded shows, or mark for quick skip in player.
  * Extracts closed caption info, adjusted for removal of commercials; adds to MPEG and creates subtitle files.
  * Generate metadata appropriate for use by tools such as pyTivo.
  * Adds episode-specific artwork from theTVDB (if available).
  * Copies shows to iTunes with all data about the show (metadata) transferred as well.
  * Performs an 'iTunes sync' to your device when the download is completed. 
  * Maximum parallel processing, including downloading from multiple TiVos simultaneously.
  * Wide selection of predefined video Formats.
  * Target devices include iPhone, iPad, AppleTV, Xbox 360, PlayStation 3, PSP, YouTube.
  * Imports iTiVo preferences, including subscriptions and Media Access Key.

##Complete Control Over Process
  * Change conversion formats for each download or subscription.
  * Change commercial handling/captioning/metadata/iTunes submittal for each download or subscription.
  * Change download directories for each download.
  * Create custom Formats with completely customizable encoder options for multiple formats.
  * Show only the encoding formats you actually use.
  * Support for different encoders, including HandBrake, mencoder, ffmpeg, Elgato Turbo.264.
  * Scheduling of when the queue will be processed.
  * Options to prevent sleep or quitting until processing complete.
  * Access remote TiVos (requires network reconfiguration).
  * Folders optionally created for each series.

##Information About Your Shows
  * Customizable columns about shows, downloads and subscriptions; show exactly what you want to see and no more.
  * Detailed info available for each show.
  * Contextual menus to play downloaded video, show in Finder, etc.
  * See which shows have already been downloaded with Spotlight tracking of shows already downloaded by cTiVo.
  * Filter which shows are seen by keywords or TiVo.
  * Show/Hide copy-protected shows and TiVo suggestions.
  * Growl or Apple notifications when downloads complete.

##Major New Features in Version 2.1
  * cTiVo now automatically configures an optimum workflow so that simultaneous-encoding decision is no longer necessary.
  * Commercials can now be marked as chapters on MPEG files, regardless of the capability of the encoder.
  * Subtitles are now embedded in the video file for MPEG (including advanced formatting and glyphs).
  * Update to HandbrakeCLI 0.99.
  * Greatly improved subscriptions, including handling multiple TiVos.  
  * Subscribe to ALL to download all shows recorded.
  * Improved support for artwork.
  * cTiVo now accesses TheTVDB.com to try to find missing episode/season information and artwork.
  * cTiVo is now code-signed for additional security.
  * Many other bug fixes and UI enhancements (see Wiki for updated documentation).

##To install:

Download the [cTiVo application](https://code.google.com/p/ctivo/downloads/detail?name=cTiVo_2.1_439.zip&can=2&q=), and drag it to your Applications Folder.

cTiVo is fully compatible with OS X Mountain Lion (10.8) and Lion (10.7); not compatible with Snow Leopard or earlier.

*cTiVo* is free to use, and the source is available for anyone to browse and contribute to. Please let us know of any problems/suggestions at https://code.google.com/p/ctivo/issues/list.