# Q&A on different video Formats

Note that cTiVo lets you show/hide individual video formats. We have hidden some of the formats described below as they are not commonly used. To show them again, simply go to the Edit>Edit Formats menu item, select the format from the pull-down list and change the hidden field. Note also that you can edit any individual built-in format by duplicating it in the Edit>Edit Formats menu. See [Advanced Topics](Advanced-Topics.md) for more information.

1. I want the original file from the TiVo.  
    The TiVo encrypts your show with your MAK, making it unreadable. If you want to simply copy and decrypt, choose the 'Decrypted TiVo Show' format. However, Quicktime from Lion (10.7) on will play these files but iTunes won't store it. You can also use [MPlayer OSX Extended](http://www.mplayerosx.ch)  or [VLC](http:/www.videolan.org/vlc/index.html) to view it. Media managers like Boxee or Plex can also read it. Note that TiVo's MPEG2 format is much bigger than the more compressed H.264. If you later decide you prefer H.264, you can always re-encode your movie with a tool like [HandBrake](http://handbrake.fr).
1. Why doesn't the DVD format making a burnable DVD image?  
    The DVD format simply creates an MPEG2 file with specifications appropriate for DVD burning software. It will not make a DVD image, nor burn one for you. If you plan on making a DVD, you should then load up the resulting movie into another program like Burn.
1. What is iPhone super-res?  
    The iPhone can play movies up to 720x480, although its display is only 480x320. You can hook up a video cable to hook up your iphone to a TV, and that's the main reason for super-res. It also uses a much higher bitrate for people who think the iphone setting isn't of a high enough quality.
1. Audio-only?  
    The "audio only" option re-encodes the audio stream, throwing away **all** the video, and just keeping the soundtrack. Useful for people who plan on listening but not viewing, as it takes up a **lot** less memory, and uses less battery life to play back.
1. PSP?  
    Aimed at the Sony PSP handheld: Connect your PSP via USB or insert the memory stick into a reader. Create a folder named "VIDEO" at the top level, and copy the movie into it. Your PSP will now play your movie for you.
1. I want to keep my movies as a high-quality library on my hard drive... What settings?  
    We would recommend Quicktime (H.264 5mbps). If you want to get the best quality **and** the fastest download, you can simply keep the original TiVo file as discussed above. 
1. What is [HandBrake](http://handbrake.fr)?  
    A popular Mac encoding tool that is an alternative to mencoder. Some people prefer the speed or the quality of Handbrake, even though a lot of code is shared between the two encoders. 
1. I use HandBrake, but I want to use different options from what you chose.  
    See the [Advanced Topics](Advanced-Topics.md) page. You can read up on all the Handbrake options on the [HandbrakeCLI config page](https://trac.handbrake.fr/wiki/CLIGuide). 
     On the other hand, if all you want is a different HandBrake preset, say iPad:

    - Go to Edit>Edit Formats
    - From the Formats pulldown, select HandBrake IPhone
    - Duplicate
    - Make sure Hide in User Interface is off
    - Change name to HandBrake iPad
    - Change Video Options for Encoder to -Z"iPad"
    - Hit Save and then Done at bottom of page
1. What is Elgato Turbo.264?  
    It's a commercial encoder available from [Elgato](http://elgato.com), which comes in both a software and a hardware version. If you own an old Mac, or just want to keep your Mac from using a lot of processing power to encode, you can buy the ElGato hardware accelerator, which is a USB stick, and use that to encode shows instead. 
1. I want to change an option / make a custom download format.  
    See the [Advanced Topics](Advanced-Topics.md) page. You can then export it and share with others on the [Alternative Formats](Alternative-Formats) page. 
1. I chose the right download format but it's not working or a different default option is better.  
    Submit a bug report under 'Issues' above.  Keep in mind we don't have have all these devices, nor are we the world's experts on video formats, so we appreciate any encoder suggestions you may have. Also keep in mind that if it's because 'mencoder' or a similar subtool crashes, there is really not much we can do, other than work with that community.
    
Note: cTiVo is based on the great work done by iTiVo. In particular, the video formats are directly inherited. As such, these Q&A are also derived from the original documentation...

