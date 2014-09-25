# Frequently Asked Questions

### How do I get "The Daily Show" onto my iPhone automatically?  
See [Subscriptions]()
### I have questions about my TiVo.  
Well, cTiVo is designed to get shows from your TiVo to your Mac. If you have questions about your TiVo that TiVo Support can't handle, we highly recommend the [TiVo Community forum](http://TiVocommunity.com/TiVo-vb/index.php).
###I have shows on my TiVo that are not listed on cTiVo!
Certain shows and certain channels can be marked by your cable provider as 'copy-protected'. Your TiVo will not let any show marked as copy-protected be downloaded. Premium Channels (like HBO) are always marked this way. Some regular cable channels also do this. The only ones that are not allowed to be marked copy-protected are the over-the-air networks. cTiVo lets you either show or hide copy-protected programs (Options>Show Protected Shows), but you still can't download the show. If you think too many of your shows are marked, complain to your cable company.
###cTiVo says "Paused" in big red letters, and nothing is happening.
You have the option to pause the queue, either automatically in Preferences or manually with File>Pause Queue (Cmd-U). To resume manually, just hit File>Resume Queue (or Cmd-U).
###I managed to hide the Show Description drawer.
To show the show description drawer, double-click on any show.
###I chose video format XYZ, and Quicktime will not play my video.
Some formats are not intended for playing on your computer, and Quicktime is unable to play them. See the [Video Formats](Video-Formats.md) page for more information.
###I want a different option on the encoding.
   See Edit Video Formats in [Advanced Topics](Advanced-Topics.md) 
###What does the column "Tivo Status" mean?
These are the icons displayed by TiVo on its NowPlaying status along with a couple we've added for clarity. 
<table>
    <tr> <td><img src="Images/in-progress-recording.png"></td><td>Recording Now</td></tr>
    <tr> <td><img src="Images/save-until-i-delete-recording.png"></td><td>Save until Deleted</td></tr>
    <tr> <td><img src="Images/recent-recording.png"></td><td>Recently recorded `*`</td></tr>
    <tr> <td><img src="Images/expires-soon-recording.png"></td><td>Expires Soon</td></tr>
    <tr> <td><img src="Images/expired-recording.png"></td><td>Expired</td></tr>
    <tr> <td><img src="Images/deleted.png"></td><td>Deleted at TiVo `*`</td></tr>
    <tr> <td><img src="Images/suggestion-recording.png"></td><td>TiVo Suggestion</td></tr>
    <tr> <td><img src="Images/copyright.png"></td><td>Copying prevented `*`</td></tr>
    <tr> <td><img src="Images/status-unknown.png"></td><td>Status Not Loaded Yet `*` </td></tr>
</table>

`*` = Ones we've added 

###Is it supposed to be this slow?
 First, yes. Video files are huge, especially HD.
 
Several things affect the speed of the download:

- Model of Tivo; the more recent the model, the faster it transmits.
- Size of the original program on the TiVo (the more there is to transfer, the slower it will be).
- The quality of your TiVo-to-computer network. Wired 100Mbps will not be fully utilized, but is your best connection. Wireless will slow it down somewhat.
- The processing speed of your computer. Your CPU is used to convert the movies once they get to the computer.
- Format you are converting to. Higher-resolution, higher-quality formats take more processing power from your computer.

To give you an estimate over a wired connection, from a TiVo HD (aka Series3), converting to iPhone simultaneous encode, you might see a 1.8MBps connection and get a 3.0-gigabyte 30-minute show in about 30  mins. Use those settings as a starting point. If you're seeing MUCH worse times, then something is wrong. You can see the speed of your network connection by running Activity Monitor (Applications>Utilities>Activity Monitor>Network tab). If you have a Roamio, then you might see more like 10MBps, so get a 3.0GB show in 5 minutes
###What should I do if I need it to download faster?
   With today's processors and older TiVos, you'll probably be encoding as fast as you can download. If not, if you're ok with using up a lot more hard drive space, you might select the 'Decrypted TiVo Show' format. Then install [http://www.mplayerosx.ch MPlayer OSX Extended](https://ctivo.googlecode.com/svn/trunk/cTiVo/questionmark.png])  or [VLC](http://www.videolan.org/vlc/index.html) to view the downloaded movie. It will download as fast as the TiVo will allow, and do no conversion whatsoever. Otherwise, try out different Formats in cTiVo; many have vastly different performance.
###What are the different stages that cTiVo goes through?
   Depending on the options that you've set, cTiVo goes through many different steps to prepare your video.  Note that there are resource constraints that will prevent the program from attempting all in parallel. For example, we only download one show at a time from each TiVo as trying to do more will be counterproductive. Thus a show might pause mid-way through processing until further resources are available.
  Download => Decrypt => Ads Detect => Subtitle Extraction => Video Encoding => Adding Metadata => Adding to iTunes ==> Complete 
   We optimize to do as many of these as possible in parallel, so several of these steps may be combined into one; for example, the download might say "Downloading" until the download is complete, then say "Encoding", even though much of the file may already be decrypted/encoded. Shows can also be marked as "Failed" or "TiVo Deleted", meaning that the show is no longer available on the TiVo. A blank entry means that it's not been started yet (or has failed and is scheduled for automatic retry).
###My shows aren't downloading; although I can see the list and can request a download, every show tries several times, then gives up.
This symptom may mean that your TiVo's internal file server has crashed. It's quite delicate, and certain combinations of operations (which we try to avoid) can cause problems. Try restarting your TiVo (TiVo Central > Messages & Settings > Restart or Reset System > Restart the TiVo; doing this while recording will cancel recording) and see if the problem is fixed. If it does and yet reoccurs later, let us know.
###My program crashes / I get mencoder or tivodecode errors, etc.
 The short version: sorry; let us know, and we'll try to fix it.
The long version: cTiVo is actually a front-end for several programs written by multiple people. See the About cTiVo menu item for more details. Many of these programs are not perfect, and cTiVo may have its own bugs. If you report bugs in the *Issues* tab above, we will get around to checking it out. However, the bug may be related to underlying programs which we have no control over.  One thing to always try is a different download format, or a different encoder (for example, HandBrake iPhone instead of iPhone). Comskip in particular, is very prone to crashing or failing. When this happens, we put up an error message, but we continue with the processing, simply not marking/skipping commercials.
###This program has bugs!
   We appreciate bug reports, and will do our best to fix them. But please keep in mind that we're working on this in our spare time, and we are not charging you anything...

Note: as cTiVo is based on the original iTivo project, we have reused and updated many of these questions from there.