# mpv4all v4.0 x Dracula theme

<p align="left"><img width=50% src="https://i.imgur.com/Qf2ah95.png" alt=""></p>

So many mpv configs but still not satisfied? Try this, and you won't regret it.

This is my personal mpv configuration for the best quality experience with NVIDIA GPU.

You can use this configuration to have an universal video, image and audio player with many convenient functions.
The main functions are the toggle keys for upscaling.

The default values of the config are <kbd>gpu-api=auto</kbd> and <kbd>hwdec=nvdec-copy</kbd>. 
If you ha have a Radeon or Intel Arc GPU, please set <kbd>hwdec=auto-copy</kbd>.

<p align="left"><img width=50% src="https://i.imgur.com/R9OoxI2.png" alt=""></p>

## Software Requirements
- mpv https://github.com/mpv-player/mpv | Download: https://github.com/zhongfly/mpv-winbuild/releases
- Windows OS (I haven't tested on Linux.)

## System Requirements
- Minimum: At least a quad core CPU and a discrete GPU (GTX 750, RX 550 for example. I tried a GT 440, and it's not powerful enough for upscaling.)
- Recommanded: GTX 1060 or RX 580 equivalent for 4K upscaling.

# Keyboard Bindings:

### Video functions

- <kbd> 1 </kbd> - Upscale with SSimSuperRes (Enhance mpv internal upscaler)
- <kbd> 2 </kbd> - Upscale with AMD FidelityFX™ Super Resolution (FSR)
- <kbd> 3 </kbd> - Upscale with NVIDIA Image Scaling (NIS)
- <kbd> 4 </kbd> - Pixel Perfect (Nearest neighbor scale)
- <kbd> 5 </kbd> - Upscale with Anime4K High Quality (very GPU intensive)
- <kbd> 6 </kbd> - Upscale with Anime4K Ultra Quality (extremely GPU intensive, it's like running Crysis)
- <kbd> 7 </kbd> - Upscale with SSimSuperRes + FSRCNNX (Very recommanded for DVD content)
- <kbd> 8 </kbd> - Add Film Grain #Type 1
- <kbd> 9 </kbd> - Add Film Grain #Type 2
- <kbd> 0 </kbd> - Disable everything and return to the default values
- <kbd> CTRL+\ </kbd> - Display actual shaders
- <kbd> r </kbd> - Rotate video
- <kbd> CTRL+d </kbd> - Activate bwdif deinterlace
- <kbd> d </kbd> - Activate yadif deinterlace
- <kbd> D </kbd> - Activate deband
- <kbd> CTRL+c </kbd> - Switch between Full RGB and Limited RGB color space
- <kbd> shift+c </kbd> - Auto crop function
- <kbd> shift+w </kbd> - Video Cutter function # instructions here: https://github.com/ekisu/mpv-webm
- <kbd> \ </kbd> - Frame interpolation
- <kbd> h </kbd> - Convert SDR to HDR
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


## Example of Boosted Upmix Surround 7.1ch

<p align="center"><img width=100% src="https://i.imgur.com/3wANjgW.png" alt="Boosted Upmix Surround 7.1ch"></p>

### *tested with Dolby Atmos audio driver for Windows 11. 

All the shaders are property of their rightful owners. I have only edited mpv.conf, input.conf and some LUA scripts to fits better with my configuration.
