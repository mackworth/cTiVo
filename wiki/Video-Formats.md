## Video Formats
Video can be stored in many different ways in a file. Many factors such as resolution (the number of horizontal and vertical pixels), the encoder used, the amount of compression, all affect both the amount of space used and the quality of the resulting video. The video formats used by broadcasters are not very compatible with those used by computer industry so cTiVo needs to convert the vido files that you bring over from your TiVo. 

In order to maximize flexibilty while keeping it simple, cTiVo gives you a choices of "Formats". A Format stores the information needed to convert to a specific video format. We provide a wide range, in addition, you can use the Format Editor to build your own. 

## Selecting a Format for cTiVo
As the name suggests, the "Default" Format should work well for most uses, but we've provided many alternatives to handle different situations. 

Generally speaking, there are tradeoffs between:
a) the size of the converted video file (usually significantly smaller than the original)
b) the resolution and the quality of the video when displayed
c) the time it takes to convert (aka encode) the video (ranging from 20% to 300% of the length of the video)
d) the compatibility of the video with different devices.

HD TiVo shows will normally be recorded in either 720p or 1080i. ("p" stands for Progressive; "i" stands for Interlaced. For historic reasons, the TV industry frequently uses Interlaced video, wherein the odd lines are sent in one group, followed by all the even lines. The computer industry generally thinks this is crazy; notably, iTunes will not accept interlaced videos). 

Now, 1080i is technically higher resolution, but at half the frame rate of 720p (30 versus 60).  The Default Format encodes to a maximum resolution of 720p. Given the reality of the compression that most cable sources do, this seems a reasonable compromise, but if you'd like to have cTiVo convert 1080i to 1080p for you, we've provided a 1080P Format to do just that; however, it will take about twice as long to convert each video and generate almost double the size of the file as a result. Some people will feel that's a good tradeoff; some won't.

Fortunately, the compatability issue is much less of a problem than it used to be, except for older devices. The computer industry has mostly standardized on .MP4 files with H.264 encoding, and most of the Formats we recommend use this container/codec combination.

So...if Default doesn't work well for you, your built-in alternatives are:

* <b>1080p:</b> Upscales 1080i to 1080p. Lower resolutions are not affected.

* <b>Audio Only:</b> This format will strip the video entirely, leaving just the audio as an MP3. Maybe you want to listen to your soap operas while exercising?

* <b>Faster:</b> This one will give up some quality in order to convert significantly faster.

* <b>Higher Quality:</b> This one will not only convert to 1080p, but will spend much more compute time and file space to get a better quality picture. Whether you will be able to tell the difference is entirely up to you!

* <b>iPhone/iPad:</b> While the Default format is compatible with most devices, this one will create slightly smaller files, and will not copy over the 5.1-channel surround sound. 

* <b>Smaller:</b> This Format will spend more compute time and lower the quality somewhat to get a significantly smaller file; still 720p, but no surround sound.

* <b>Standard Def:</b> Designed for older devices (e.g. Pod Touch 1-3; iPhone 3G/3GS; SD TV), this has a maximum resolution of 480p, and removes surround sound. 

Certain other formats are built-in, but hidden to keep thing simple. To enable, go to `Edit>Edit Formats`, select the Format you want to use, and clear its `Hide in User Interface` checkbox 

* <b>Decrypt MP4:</b> This is a Format for experts. It's very fast, and will copy the video and audio through without re-encoding, so (especially if interlaced) it may be incompatible with iTunes and other systems. Unlike Decrypted TiVo Show below, it converts the file format to MP4, so you can add subtitles, commercial skipping information, and other metadata inside the file.

* <b>Decrypted TiVo Show:</b> This is also a Format for experts. It copies the show from the TiVo and does no conversion on it whatsoever.

* <b>DVD Ready:</b> This Format converts to MP2 video ready to be loaded into a DVD creation program such as Toast or Burn.

* <b>ProRes LT:</b> Used for editing the resulting file in Final Cut Pro. Much larger files. 

* <b>Test PS:</b> This is used solely to test a channel to see if it has transitioned to H.264. You can test one manually by using this Format, or all of them in the `Edit>Edit Channels` panel. (Note that you don't need to do this normally, as any show that fails due to H.264 transition should be automatically retried with Transport Stream.)

Finally, we also have a full set of Formats using two other encoders: Handbrake and Elgato's Turbo.264HD. While Elgato is relatively uncommon, Handbrake is also highly recommended, and has a large number of predefined settings. To keep things simple, these are hidden in the default settings, but if the ffmpeg-based ones don't work for you, feel free to give Handbrake a try. Note that Handbrake does not support Commercial skipping (actually cutting the commercials out the videO), only marking (which makes it easy to skip commercials during playback).

## Relative Performance
To give you an indication of relative performance of these encoders, we ran 8 different files with each Format. As the performance varies widely, particularly depending on output resolution, the results are separated for 1080i source shows as well as shows smaller than that.

|  Name           | AC3 | Max Res | Small Size |Small Time| 1080i Size | 1080i Time|
|-----------------|:---:|:-------:|-----------:|---------:|-----------:|----------:|
| Higher Quality  | Yes |  1080p  |    67%     |   1.2x   |     78%    |   3.0x    |
| 1080p           | Yes |  1080p  |    45%     |    .4x   |     53%    |   1.3x    |
| Default         | Yes |  720p   |    44%     |    .4x   |     27%    |    .6x    |
| iPhone/iPad     | No  |  720p   |    40%     |    .4x   |     21%    |    .6x    |
| Faster          | Yes |  720p   |    29%     |    .2x   |     17%    |    .4x    |
| Smallest        | No  |  720p   |    23%     |    .8x   |     11%    |   1.1x    |
| Standard Def    | No  |  480p   |    31%     |    .2x   |     11%    |    .2x    |
|                 |     |         |            |          |            |           |
| DVD Ready       | Yes |  480p   |   176%     |    .2x   |     69%    |    .4x    |
| Decrypt Tivo/MP4| NA  |   NA    |   100%     |   0.0x   |    100%    |   0.0x    |
|                 |     |         |            |          |            |           |
| HB SuperHQ      | Yes |  1080p  |    60%     |   1.2x   |     59%    |   4.1x    |
| HP 1080p        | Yes |  1080p  |    43%     |    .5x   |     39%    |   1.9x    |
| HB Default      | Yes |  720p   |    48%     |    .5x   |     22%    |   1.3x    |
| HB Android      | No  |  720p   |    39%     |    .5x   |     18%    |   1.0x    |
| HB Std Def      | Yes |  540p   |    48%     |   1.0x   |     19%    |    .9x    |

Notes:
AC3 = Includes Surround sound in output file (vs just stereo), which will add 5-15% to the file size.
Size and Time ratios are versus the original TiVo file, so 50% and .7x for a 1GB, 1hr show would mean that the resulting file was 500MB and took 42 minutes to convert.
Time values given are run on a 2014 MacBook Pro; 2.5 GHz Intel Core i7. Only one conversion occuring at a time, with no other work going on in the same machine. Does not include download time. Your mileage may vary.

## Building your Own Format
If none of these work for you, and you're somewhat technical, feel free to create your own Format. The [detailed instructions are here](Advanced-Topics#edit-formats), but the general idea is to (a) select an existing one that's close to what you want, (b) Duplicate it in the Format Editor, and (c) modify however you choose. If it doesn't do what you expect, look in the logs to see messages from the encoders. Due to the wide range of Handbrake presets, there's an easy mechanism to create a new Handbrake Format: just select an existing Handbrake Format in the Editor, and select a new Preset including user-defined ones.

If you'd like more information on these topics, here's a couple of good resources:
[Guide to Common Video Formats, Containers, Compression, and-Codecs](http://www.fallenempiredigital.com/blog/2013/02/08/a-guide-to-common-video-formats-containers-compression-and-codecs/)
[Adobe H.264 primer](http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/video/articles/h264_primer/h264_primer.pdf)
[FFMpeg on H.264] (https://trac.ffmpeg.org/wiki/Encode/H.264)

The last describes how to create your own ffmpeg presets. Here are the choices made for cTiVo's default presets:

|  Name           | AC3 | Max Res | MP4 Profile |  ffmpeg  | CRF  |
|-----------------|:---:|:-------:|:-----------:|:--------:|:----:|
| Higher Quality  | Yes |  1080p  |   High4.2   | slower   |  19  |
| 1080p           | Yes |  1080p  |   High4.2   | medium   |  23  |
| Default         | Yes |  720p   |   Main3.1   | medium   |  23  |
| iPhone/iPad     | No  |  720p   |   High4.1   | medium   |  23  |
| Faster          | Yes |  720p   |   Main3.1   | veryfast |  25  |
| Smallest        | No  |  720p   |   High4.1   | slower   |  28  |
| Standard Def    | No  |  480p   |   Base3.0   | medium   |  23  |
| DVD Ready       | Yes |  480p   |   MP2       | ntsc-dvd |  23  |
|                 |     |         |             |          |      |
| HB SuperHQ      | Yes |  1080p  |   High4.0   | veryslow |  18  |
| HP 1080p        | Yes |  1080p  |   High4.0   | medium   |  22  |
| HB Default      | Yes |  720p   |   High3.1   | medium   |  21  |
| HB Android      | No  |  720p   |   Main3.1   | medium   |  21  |
| HB Std Def      | Yes |  540p   |   High3.1   | medium   |  20  |
