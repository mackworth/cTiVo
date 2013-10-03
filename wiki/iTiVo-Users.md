# Quick overview of cTiVo for iTiVo users

cTiVo is inspired by the great work done on iTiVo, but completely rewritten in Cocoa/Objective-C for better performance and compatability. 

cTiVo is meant to be an easy replacement for iTiVo. The user interface is very similiar; the options are quite parallel. In fact, when you first run cTiVo, it will pick up most of your preferences from iTiVo, such as your Media Access Key, your iTunes preferences, your preferred format choice, even your subscriptions.

So, just [download the cTiVo application](https://code.google.com/p/ctivo/downloads/list), drag it to your Applications folder, and run it. If you've been running iTiVo, you shouldn't even need to do any setup. 

- - -

# Major differences from iTiVo

### Multiple TiVos
- Support for multiple TiVos (with same or different Media Access Keys), all programs on all TiVos displayed and available simultaneously. Subscriptions handled across multiple TiVos

### User Interface Improvements
- Complete drag-and-drop for ease of use: submit, reschedule, delete, all by just dragging the shows.
- Contextual menus to make operation faster.
- Show only the encoding formats you actually use.
- Double-click on a downloaded video to instantly watch it.
- Show or hide TiVo's suggestions (and include, or not, in subscriptions)
- Customizable columns; show exactly whch information you want to see.
- Options to prevent sleep (or delay quit) until processing complete.
- In scheduled use, avoids starting new operations when end-time reached.
- Sorting of all tables.
- No distinction between Download Now vs Add to Queue. Queuing occurs automatically, as does loading the initial TiVo list.

### Better performance

- Simultaneous downloading from multiple TiVos.
- Much more parallel processing, such as downloading next show while encoding current one.
- User-definable ports for TiVos; allows advanced users to access TiVo shows remotely (requires network reconfiguration).
- Fully compatible with OS X Mountain Lion (10.8) and Lion(10.7).

### More control over downloads

- Change conversion formats for each download or subscription.
- Mark commercials (rather than deleting) to avoid losing parts of shows
- Subtitles embedded in MP4 files
- Change download directories per submittal.
- Turn on or off iTunes / simultaneous download encoding / metadata for each download or subscription.
- Completely customizable encoder options for multiple formats.

### iTivo features not implemented

- Reporting on TiVo's disk usage.
- Not compatible with OS X Snow Leopard (10.6)

# Some things to try

- Right-click on the column headers to see all the columns of information you can show or hide.
- Drag a show from the program list to the download queue.
- After a show is in the queue, change formats or other options (unless conversion has already started).
- Double-click on a downloaded show to view it.