# mpv4all v3.0 【2022 Edition】

So many mpv configs but still not satisfied? Try this, and you won't regret it.

This is my personal mpv configuration for the best quality experience.

You can use this configuration to have a universal video, image and audio player with many convenient functions.
The main functions are the toggle keys for upscaling.
I have also included a script for saving small video clips and a script for displaying images correctly.

The default values of the config are <kbd>gpu-api=d3d11</kbd> and <kbd>hwdec=d3d11va</kbd> to have the best compatibility and a good performance.
Well, if you have an ancient video card, this config is not for you.
I didn't put any default pre-scalers so that there are no issues with HDR videos.

## Software Requirements
- mpv https://github.com/mpv-player/mpv | Download: https://www.videohelp.com/software/mpv-media-player
- Windows OS (I haven't tested the Linux version of mpv, my config could not work as intended.)

## System Requirements
- Minimum: At least a quad core CPU and a discrete GPU (GTX 750, RX 550 for example. I tried a GT 440, and it's not powerful enough for upscaling.)
- Recommanded: GTX 1060 or RX 580 equivalent for 4K upscaling.

<p align="left"><img width=30% src="https://i.imgur.com/Lq26vjI.png" alt=""></p>

# Keyboard Bindings:

### Video functions

- <kbd> 1 </kbd> - Upscale with SSimSuperRes (Enhance mpv internal upscaler)
- <kbd> 2 </kbd> - Upscale with SSimSuperRes + FSRCNNX
- <kbd> 3 </kbd> - Upscale with NVIDIA Image Scaling (NIS)
- <kbd> 4 </kbd> - Upscale with AMD FidelityFX™ Super Resolution (FSR)
- <kbd> 5 </kbd> - Upscale with AMD FidelityFX™ Contrast Adaptive Sharpening (CAS) 
- <kbd> 6 </kbd> - Function to thin the Anime lines
- <kbd> 7 </kbd> - Add Static Film Grain
- <kbd> 8 </kbd> - Add Film Grain #Type 1
- <kbd> 9 </kbd> - Add Film Grain #Type 2
- <kbd> 0 </kbd> - Disable everything and return to the default values
- <kbd> CTRL+\ </kbd> - Display actual shaders
- <kbd> r </kbd> - Rotate video
- <kbd> CTRL+d </kbd> - Activate bwdif deinterlace
- <kbd> d </kbd> - Activate yadif deinterlace
- <kbd> b </kbd> - Activate blur edges
- <kbd> CTRL+c </kbd> - Switch between Full RGB and Limited RGB color space
- <kbd> shift+c </kbd> - Auto crop function
- <kbd> shift+w </kbd> - Video Cutter function # instructions here: https://github.com/ekisu/mpv-webm
- <kbd> \ </kbd> - Frame interpolation
- <kbd> h </kbd> - Switch between hardware and software decoding whenever possible
______________________________________________________

### Audio functions (Only for Surround audio devices/drivers)

- <kbd> a </kbd> - Upmix audio from Stereo 2.0ch to Surround 7.1ch
- <kbd> Alt+a </kbd> - Downmix audio from Surround to Stereo 2.0ch
- <kbd> A </kbd> - Boost rear audio channels. Very good effect when you watch anime and movies
- <kbd> CTRL+a </kbd> - Listen only rear channels, just for fun. This works even for native 5.1 and 7.1 audio tracks
______________________________________________________

### Other controls

- <kbd> UP </kbd> <kbd> DOWN </kbd> - Pan & Scan function
- Mouse <kbd> WHEEL_UP </kbd> <kbd> WHEEL_DOWN </kbd> - Zoom-in and Zoom-out
- Mouse <kbd> LEFT_CLICK </kbd> - Click and hold to move the image after the zoom
- Mouse <kbd> RIGHT_CLICK </kbd> - Pause
- <kbd>CTRL+LEFT</kbd> Previous file
- <kbd>CTRL+RIGHT</kbd> Next file

______________________________________________________

### EXPERIMENTAL
If you have a VRR display and you want to use FreeSync or G-Sync to 24fps movies, you have to deactivate the hardware decoding first and set <kbd>vf=fps=fps=48</kbd> or <kbd>vf=fps=fps=40</kbd> according to your monitor.

By default my config is using DirectX 11 hardware decoding. To deactivate it just remove <kbd>gpu-api=d3d11</kbd> and <kbd>hwdec=d3d11va</kbd> from the config.

Note: Do not press <kbd>h</kbd> to deactivate the hardware decoding, because there is bug and VRR could not recognize mpv.
______________________________________________________


## Example of Boosted Upmix Surround 7.1ch

<p align="center"><img width=100% src="https://i.imgur.com/tcQtpto.jpg" alt="Boosted Upmix Surround 7.1ch"></p>

### *tested with Dolby Atmos audio driver for Windows 11. 

## Example of FSRCNNX + Film Grain + Blur Edges

To verify if the shaders are working, press <kbd> i </kbd> then <kbd> 2 </kbd>.

<p align="center"><img width=100% src="https://i.imgur.com/hVIc6bk.jpg" alt="Example of FSRCNNX + Film Grain + Blur Edges"></p>

## Example of SSimSuperRes + FSRCNNX

1080p to 4K upscale, final result

<p align="center"><img width=100% src="https://i.imgur.com/ptCcaV6.png" alt="Example of SSimSuperRes + FSRCNNX"></p>

No upscale

<p align="center"><img width=100% src="https://i.imgur.com/y2pmpka.png" alt="Example of SSimSuperRes + FSRCNNX"></p>

<kbd> 2 </kbd> SSimSuperRes + FSRCNNX

<p align="center"><img width=100% src="https://i.imgur.com/IC53pnv.png" alt="Example of SSimSuperRes + FSRCNNX"></p>

Tested with mpv v0.34.0, a GTX 1060 and a 4K HDR 60Hz monitor. 

Note: I prefer not to use Anime4K shader for a simple reason, it's too GPU intensive and too artificial.
FSRCNNX instead preserve the original image quality, in combination with SSimSuperRes.

All the shaders are property of their rightful owners. I have only edited mpv.conf, input.conf and some LUA scripts to fits better with my configuration.
