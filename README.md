# mpv4all

So many mpv configs but still not satisfied? Try this, and you won't regret it.

This is my personal mpv configuration for the best quality experience.

Toggle functions are the main features.

### This config is for NVIDIA users, 4K and 2K monitor resolution and Surround Audio enthusiasts.

Change `hwdec=nvdec` to `hwdec=auto-copy` if you have an AMD or Intel GPU. 

Also, change `gpu-api=vulkan` to `gpu-api=auto` if your hardware don't support Vulkan.


## Software Requirements
- mpv https://github.com/mpv-player/mpv | Download: https://www.videohelp.com/software/mpv-media-player
- Windows (I haven't tested the Linux version of mpv.)

## System Requirements
- At least a quad core CPU and a discrete GPU.  

# Keyboard Bindings:

### Video functions

- <kbd> \ </kbd> - Activate frame interpolation.
- <kbd> CTRL+1 </kbd> - Enhance video.
- <kbd> CTRL+2 </kbd> - Enhance more! Very GPU intensive. Not recommended for 1080p videos, in that case 1 is better.
- <kbd> CTRL+3 </kbd> - For anime only, use it if you don't like 1 or 2. 
- <kbd> CTRL+8 </kbd> - Activate a function to thin the contour lines of the Anime, you can use this multiple times and in combination of other shaders.
- <kbd> CTRL+9 </kbd> - Add Film Grain, you can also combine this with other shaders.
- <kbd> CTRL+0 </kbd> - Deactivate all the shaders.
- <kbd> CTRL+\ </kbd> - Display actual shaders.
- <kbd> Alt+LEFT </kbd> -  Video rotate LEFT
- <kbd> Alt+RIGHT </kbd> - Video rotate RIGHT
- <kbd> CTRL+d </kbd> - Activate bwdif deinterlace.
- <kbd> b </kbd> - Activate blur edges.
- <kbd> shift+c </kbd> - Auto crop function.
- <kbd> shift+w </kbd> - Webm Maker. # instructions here: https://github.com/ekisu/mpv-webm
______________________________________________________

### Audio functions (Only for Surround audio devices/drivers)

- <kbd> a </kbd> - Upmix audio from Stereo 2.0ch to Surround 7.1ch
- <kbd> Alt+a </kbd> - Downmix audio from Surround to Stereo 2.0ch
- <kbd> A </kbd> - Boost rear audio channels. Very good effect when you watch anime and movies.
- <kbd> CTRL+a </kbd> - Listen only rear channels, just for fun. This works even for native 5.1 and 7.1 audio tracks.

## Example of Boosted Upmix Surround 7.1ch

<p align="center"><img width=100% src="https://i.imgur.com/tcQtpto.jpg" alt="Boosted Upmix Surround 7.1ch"></p>

### *tested with Dolby Atmos audio driver for Windows 10. 

For HDR videos, you have to rename your file like this: `The Hobbit - HDR.mkv` 
The most important thing is the word HDR in the file name, otherwise don't work.

## Example of FSRCNNX + Film Grain + Blur Edges

To verify if the shaders are working, press <kbd> i </kbd> then <kbd> 2 </kbd>.

<p align="center"><img width=100% src="https://i.imgur.com/hVIc6bk.jpg" alt="Example of FSRCNNX + Film Grain + Blur Edges"></p>



Tested with mpv v0.33.0, a GTX 1060 and a 4K HDR10 60Hz monitor. 


All the scripts and shaders are the property of their rightful owners. I have only configured mpv.conf and input.conf.
