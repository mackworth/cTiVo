#Subscriptions
## How to set up and configure subscriptions in cTiVo

One of the main features of cTiVo is the ability to subscribe to a series. Subscribing means that all episode of that series will be automatically downloaded for your convenience, even copied onto your phone for later viewing.

## Creating a subscription

The simplest way to create a subscription, just set cTivo's options the way you like them, and then just drag any episode of the series from either the show table or download table into the subscription table. cTiVo will create a subscription, and look for any episodes of that series in the show list after the one you dragged. More importantly, whenever cTiVo is running, it will download any further episodes using those options. Although cTiVo will obviously not download any shows when it is not running, when it next runs, it will find any shows it has not previously downloaded.

Note that video files are enormous (HD files are about 5-7GB per hour), and you will need to be careful about not running out of disk space. You'll need at least twice the space of the largest individual file. On the other hand, after downloading and converting, they might only be 1GB per hour.

With 2.1, subscriptions now operate correctly across multiple TiVos. We use the Episode ID and ensure one and only one copy of each show is downloaded. 

## Manual subscriptions

You can also enter the name of a series without having a sample episode. Just go to Edit>New Manual Subscription (Cmd-N) and type the name of the series. This also allows you to match multiple series. So if you like House Hunters International as well as House Hunters, you can just put in House Hunters and any show with that exact text in its series name will be recorded. As an interesting option, you can simply enter ALL here to subscribe to all shows recorded by your TiVo. Finally, if you know what "regular expressions" means, and wish to control your subscriptions beyond this simple description, see [Advanced Subscriptions](Advanced-Topics.md#advanced-subscriptions)

## Limiting subscriptions

If you want a subscription to apply to only one TiVo, then right-click on the header of the table to show the "TTiVo" column, and pick which TiVo should be used. Only shows recorded on that TiVo will be downloaded.

Similarly, if you want to restrict shows to Standard Definition (SD) or High Definition(HD) or avoid TiVos Suggestions, there are columns to restrict them as well.

## Modifying a subscription

You can change the various subscription options at any time, using the fields displayed. This allows you to control how the download is done. You can specify Format, Add to iTunes, Commercial Skip or Mark and whether to generate subtitles or pyTiVo information. We should note that many more fields are available than are normally displayed; just right-click on the column header to add the ones you care about.

## Re-applying a subscription

Subscriptions created with a show or a download apply to that show and all ones later in the current list and that arrive later. Manual subscriptions apply to all shows currently in the list and that arrive later. If for some reason, you wish to regenerate download jobs for all shows currently in the list for an existing subscription, you can right-click on that subscription and "Re-apply".

## Working with iTunes

One important scenario is to have cTiVo running at night, downloading and converting the shows recorded the previous evening, then handing those files to iTunes to add to its library, and then finally synching the iDevices so that those files are copied over automatically and available in the morning. This requires a certain amount of configuration to make sure the two programs are doing exactly what you want, but will then operate without any further intervention.

Be sure to choose a format that is iTunes-compatible, such as iPhone, iPad, AppleTV, etc. If a format is not iTunes-compatible, then the "Add to iTunes" option will be disabled. Then check that the default setting of "Add to iTunes when Complete" is on. (You can also change this per download or subscription.)  Then check the global setting of "Synch iTunes Devices"; if this is on, after a video has been handed over, cTiVo will ask iTunes to auto-sync its devices. 

In iTunes, there is an option: "Preferences>Advanced>Copy file to iTunes Media folder when adding to Library". If set, iTunes copies all media over to its own folder. This would also leave a copy sitting in cTiVo's download folder, so we provide a preference option to "Delete file after copying into iTunes". This will only happen if iTunes actually copies the file over.  Note that this will leave any metadata you create behind in the cTiVo folder.

In iTunes, you will need to go the "Movie" or "TV Shows" tab for your device and set up the transfer under "Automatically include". You might, for example, tell it to copy the 5 most recent episodes of "All TV Shows".

Note that cTiVo adds all shows it transfers over to a playlist called "TiVo Shows", so another option would be to iPad>TV Shows>"Include Episodes from PlayLists>TiVo Shows". Over time, this play list may get quite large unless you delete shows you've seen. Alternatively, you could create a Smart Playlist that references the TiVo Show playlist, but adds filters for, say last 10 most recently added, or specific shows.

To avoid over-loading your Mac during the evening, you might choose to turn on Preferences>Scheduling and specify that cTiVo should only run during certain hours in the morning. That way, you can keep cTiVo open all the time, but it will only actually process anything during the specified hours.
