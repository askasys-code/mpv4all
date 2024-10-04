function autovsr()
    display_width = mp.get_property_native("display-width")
    video_width = mp.get_property_native("width")
    display_height = mp.get_property_native("display-height")
    video_height = mp.get_property_native("height")
    pixfmt = mp.get_property_native("video-params/hw-pixelformat") or mp.get_property_native("video-params/pixelformat")
    if video_width ~= nil and display_width ~= nil then 
        scale = math.max(display_width,display_height) / math.max(video_width,video_height)
        scale = scale - scale % 0.1
        if string.match(mp.get_property("vf"),"@vsr") then
            mp.command("vf remove @vsr")
        end
        if scale > 1 then
            if pixfmt == "nv12" or pixfmt == "yuv420p" then
                mp.command("vf append @vsr:d3d11vpp:scaling-mode=nvidia:scale="..scale)
            end
        end
    end
end
mp.observe_property("video-params/pixelformat", "native", autovsr)
mp.observe_property("vf", "native", autovsr)