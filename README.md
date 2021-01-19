# mpv4all

My personal mpv configuration for the best quality experience.

Toggle functions is the main feature.


# Keyboard Bindings:

### Video functions

- <kbd> \ </kbd> - Activate frame interpolation.
- <kbd> CTRL+1 </kbd> - Activate FSRCNNX shader for upscaling Movie/Live Action/3D contents.
- <kbd> CTRL+2 </kbd> - Activate FSRCNNX shader for upscaling Anime contents.
- <kbd> CTRL+3 </kbd> - Activate RAVU-Zoom shader for upscaling, this is usually lighter than FSRCNNX but less effective.
- <kbd> CTRL+4 </kbd> - 1 + Film Grain.
- <kbd> CTRL+5 </kbd> - 2 + Film Grain.
- <kbd> CTRL+6 </kbd> - 3 + Film Grain.
- <kbd> CTRL+9 </kbd> - Activate Film Grain only.
- <kbd> CTRL+0 </kbd> - Deactivate all the shaders.
- <kbd> CTRL+\ </kbd> - Display actual shaders.
- <kbd> Alt+LEFT </kbd> -  Video rotate LEFT
- <kbd> Alt+RIGHT </kbd> - Video rotate RIGHT
- <kbd> CTRL+d </kbd> - Activate bwdif deinterlace.
- <kbd> b </kbd> - Activate blur edges.

______________________________________________________

### Audio functions (Only for Surround audio devices)

- <kbd> a </kbd> - Upmix audio from Stereo 2.0ch to Surround 7.1ch
- <kbd> A </kbd> - Boost rear audio channels. Very good effect when you watch anime and movies.
- <kbd> shift+c </kbd> - Auto crop function.

## Example of Boosted Upmix Surround 7.1ch

<p align="center"><img width=100% src="https://i.imgur.com/tcQtpto.jpg" alt="Boosted Upmix Surround 7.1ch"></p>

### *tested with Dolby Atmos audio driver for Windows 10. 

For HDR videos, you have to rename your file like this: `The Hobbit - HDR.mkv` 
The most important thing is the word HDR in the file name, otherwise don't work.

##Example of FSRCNNX + Film Grain + Blur Edges

To verify if the shaders are working, press <kbd> i </kbd> then <kbd> 2 </kbd>.

<p align="center"><img width=100% src="https://i.imgur.com/hVIc6bk.jpg" alt="Example of FSRCNNX + Film Grain + Blur Edges"></p>

## System Requirement
At least a quad core CPU and a discrete GPU.  
This config is for NVIDIA users.

Change `hwdec=nvdec` to `hwdec=auto` if you have an AMD or Intel GPU.

Also, change `gpu-api=vulkan` to `gpu-api=auto` if your hardware don't support Vulkan.


Tested with a GTX 1060 and an HDR10 60Hz monitor. 


All scripts and shaders are the property of their rightful owners. I have only configured mpv.conf and input.conf.
