-- =========================================================================
-- MPV Compact Video Diagnostics Suite (Container, Stream & Color Science)
-- Real-time Reactive HUD: Dynamic Upscaled Resolution & True HDR Detection
-- =========================================================================

local mp = require("mp")
local utils = require("mp.utils")
local assdraw = require("mp.assdraw")

local is_enabled = false
local poll_timer = nil

-- Visual Configuration & Styling (Matches sound-monitor & nvidia-monitor palette)
local cfg = {
    ui_scale        = 1.35,        -- User size multiplier (1.0 = normal, 1.35 = 4K recommended, 1.6 = TV)
    poll_interval   = 0.5,         -- Refresh interval while visible (seconds)
    font_face       = "Segoe UI",
    color_green     = "00E676",    -- NVIDIA Green (Headers & Active Enhancements)
    color_cyan      = "00E5FF",    -- RivaTuner Cyan (Codecs, Resolutions & Formats)
    color_yellow    = "00C8FF",    -- Amber Warning (Bitrates & Color Gamut)
    color_red       = "3B3BFF",    -- Critical Red
    color_white     = "FFFFFF",
    color_gray      = "9E9E9E",
    bg_alpha        = "35",        -- Box transparency (Hex: 00-FF, 35 = ~80% dark)
}

local overlay = mp.create_osd_overlay("ass-events")

-- Format seconds into clean HH:MM:SS
local function format_time(seconds)
    if not seconds or seconds < 0 then return "00:00:00" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Truncate long strings with ellipsis for compact display
local function truncate_string(str, max_len)
    if not str then return "" end
    if #str > max_len then
        return str:sub(1, max_len - 3) .. "..."
    end
    return str
end

-- Clean container / demuxer format representation
local function format_clean_container(raw_fmt)
    if not raw_fmt or raw_fmt == "" then return "N/A" end
    local f = raw_fmt:lower()
    if f:find("jpegxl") or f:find("jxl") then return "JPEG XL" end
    if f:find("image2") or f:find("png") then return "PNG" end
    if f:find("jpeg") or f:find("mjpeg") then return "JPG" end
    if f:find("webp") then return "WEBP" end
    if f:find("avif") then return "AVIF" end
    if f:find("mp4") or f:find("mov") or f:find("m4a") then return "MP4" end
    if f:find("matroska") or f:find("mkv") then return "MKV" end
    if f:find("webm") then return "WEBM" end
    if f:find("flac") then return "FLAC" end
    if f:find("ogg") then return "OGG" end
    if f:find("avi") then return "AVI" end
    
    local first = raw_fmt:match("^([^,]+)")
    return first and first:upper() or raw_fmt:upper()
end

-- Clean long and redundant video codec descriptions
local function format_clean_codec(c)
    if not c or c == "" or c == "NONE" then return "NONE" end
    local lower = c:lower()
    if lower:find("h264") or lower:find("avc") then return "H.264 / AVC"
    elseif lower:find("hevc") or lower:find("h265") then return "H.265 / HEVC"
    elseif lower:find("av1") then return "AV1"
    elseif lower:find("vp9") then return "VP9"
    elseif lower:find("vp8") then return "VP8"
    elseif lower:find("jpegxl") or lower:find("jxl") then return "JPEG XL"
    elseif lower:find("mjpeg") or lower:find("jpeg") then return "JPEG"
    elseif lower:find("png") then return "PNG"
    elseif lower:find("webp") then return "WEBP"
    elseif lower:find("avif") then return "AVIF"
    elseif lower:find("mpeg2") then return "MPEG-2"
    elseif lower:find("mpeg4") then return "MPEG-4"
    elseif lower:find("vc1") then return "VC-1"
    end

    local first = c:match("^([^/]+)")
    return first and first:match("^%s*(.-)%s*$"):upper() or c:upper()
end

-- Clean and standardize gamma transfer curves
local function format_clean_gamma(g)
    if not g or g == "" then return "Unknown" end
    local lower = g:lower()
    if lower:find("bt.1886") or lower:find("1886") then return "BT.1886" end
    if lower == "pq" or lower:find("smpte2084") then return "HDR10 (PQ)" end
    if lower == "hlg" or lower:find("arib") then return "HLG" end
    if lower:find("709") then return "Rec.709" end
    if lower:find("srgb") then return "sRGB" end
    if lower:find("gamma28") or lower:find("2.8") then return "Gamma 2.8" end
    if lower:find("gamma22") or lower:find("2.2") then return "Gamma 2.2" end
    return g:upper()
end

-- Format bitrates into clean Mbps / kbps
local function format_bitrate(bps)
    if not bps or bps <= 0 then return "N/A" end
    if bps >= 1000000 then
        return string.format("%.2f Mbps", bps / 1000000)
    else
        return string.format("%d kbps", math.floor(bps / 1000 + 0.5))
    end
end

-- Resolve dynamic effective resolution (Detects active RTX VSR & GLSL upscalers in real-time)
local function get_resolution_info()
    local src_w = mp.get_property_number("width", 0)
    local src_h = mp.get_property_number("height", 0)
    if src_w <= 0 or src_h <= 0 then return "N/A", cfg.color_white end

    local out_w = src_w
    local out_h = src_h

    -- Check hardware RTX VSR / d3d11vpp video filters
    local vf_str = mp.get_property("vf") or ""
    local has_vsr = vf_str:find("@vsr") or vf_str:find("scaling%-mode=nvidia")

    local vop = mp.get_property_native("video-out-params")
    local vop_w = (vop and vop.w) and vop.w or src_w
    local vop_h = (vop and vop.h) and vop.h or src_h

    -- Check neural & spatial GLSL upscalers (NIS, FSR, SGSR, CAS)
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local has_shaders = #shaders > 0

    if has_vsr and vop_h > src_h then
        out_w = vop_w
        out_h = vop_h
    elseif has_shaders then
        local dims = mp.get_property_native("osd-dimensions")
        if dims and dims.w and dims.w > 0 and src_w > 0 then
            local vid_w = dims.w - (dims.ml or 0) - (dims.mr or 0)
            local scale_factor = vid_w / src_w
            if scale_factor > 1.05 then
                out_w = math.floor(src_w * scale_factor + 0.5)
                out_h = math.floor(src_h * scale_factor + 0.5)
            end
        end
    end

    -- Normalize common 4K / 1440p / 1080p targets
    if out_h > (src_h + 10) then
        if math.abs(out_h - 2160) <= 25 then
            out_h = 2160
            out_w = math.floor(2160 * (src_w / src_h) + 0.5)
        elseif math.abs(out_h - 1440) <= 20 then
            out_h = 1440
            out_w = math.floor(1440 * (src_w / src_h) + 0.5)
        elseif math.abs(out_h - 1080) <= 15 then
            out_h = 1080
            out_w = math.floor(1080 * (src_w / src_h) + 0.5)
        end
        return string.format("%dx%d -> %dx%d", src_w, src_h, out_w, out_h), cfg.color_green
    else
        return string.format("%dx%d", src_w, src_h), cfg.color_white
    end
end

-- Collect strictly video & file parameters (No audio redundancy)
local function get_diagnostics_data()
    -- ======================== 1. FILE & CONTAINER ========================
    local filename = mp.get_property("filename") or mp.get_property("media-title") or "Unknown Media"
    local raw_format = mp.get_property("file-format") or ""
    local file_format = format_clean_container(raw_format)
    
    local file_size_num = mp.get_property_number("file-size", 0)
    local file_size_str = (file_size_num > 0) and string.format("%.1f MB", file_size_num / (1024 * 1024)) or "N/A"

    local pos = mp.get_property_number("time-pos", 0)
    local dur = mp.get_property_number("duration", 0)
    local playback_str = string.format("%s / %s", format_time(pos), format_time(dur))

    -- Chapters metadata
    local chap = mp.get_property_number("chapter", -1)
    local total_chaps = mp.get_property_number("chapters", 0)
    local chap_str = "None"
    if total_chaps > 0 then
        local chap_title = mp.get_property("chapter-metadata/by-key/title")
        if chap_title and chap_title ~= "" then
            chap_str = string.format("%02d/%02d (%s)", chap + 1, total_chaps, truncate_string(chap_title, 14))
        else
            chap_str = string.format("%02d / %02d", chap + 1, total_chaps)
        end
    end

    local cache_secs = mp.get_property_number("demuxer-cache-duration", 0)
    local cache_state = mp.get_property_native("demuxer-cache-state") or {}
    local cache_bytes = type(cache_state) == "table" and (cache_state["total-bytes"] or 0) or 0
    local cache_str = "0.0s (0 MB)"
    if cache_secs > 0 or cache_bytes > 0 then
        cache_str = string.format("%.1fs (%.0f MB)", cache_secs, cache_bytes / (1024 * 1024))
    end

    -- ======================== 2. VIDEO STREAM ========================
    local raw_vc = mp.get_property("video-codec") or mp.get_property("video-format") or "NONE"
    local clean_codec = format_clean_codec(raw_vc)

    local hwdec = mp.get_property("hwdec-current") or "no"
    local hw_tag, hw_col
    if hwdec ~= "" and hwdec ~= "no" then
        hw_tag = string.format("%s (HW)", hwdec)
        hw_col = cfg.color_green
    else
        hw_tag = "Software (SW)"
        hw_col = cfg.color_gray
    end

    local v_bitrate = mp.get_property_number("video-bitrate", 0)
    local v_bitrate_str = format_bitrate(v_bitrate)

    local res_str, res_col = get_resolution_info()

    -- Aspect Ratio (SAR / DAR)
    local w = mp.get_property_number("width", 0)
    local h = mp.get_property_number("height", 0)
    local ar_str = "N/A"
    if w > 0 and h > 0 then
        local ar = w / h
        if math.abs(ar - 16/9) < 0.02 then ar_str = "16:9 (1.78:1)"
        elseif math.abs(ar - 4/3) < 0.02 then ar_str = "4:3 (1.33:1)"
        elseif math.abs(ar - 2.35) < 0.03 then ar_str = "21:9 (2.35:1)"
        elseif math.abs(ar - 2.39) < 0.03 or math.abs(ar - 2.40) < 0.03 then ar_str = "2.39:1 (Scope)"
        elseif math.abs(ar - 1.85) < 0.02 then ar_str = "1.85:1 (Flat)"
        else ar_str = string.format("%.2f:1", ar) end
    end

    -- Color bit depth and pixel format
    local pixfmt = mp.get_property("video-params/pixelformat") or ""
    local hw_pix = mp.get_property("video-params/hw-pixelformat") or ""
    local depth_tag = "8-bit"
    if pixfmt:find("10") or hw_pix:find("10") or pixfmt:find("p010") then
        depth_tag = "10-bit"
    elseif pixfmt:find("12") then
        depth_tag = "12-bit"
    end
    local depth_str = (pixfmt ~= "") and string.format("%s (%s)", depth_tag, pixfmt) or "N/A"

    -- Color Primaries / Gamut
    local prim = mp.get_property("video-params/primaries") or ""
    local matrix = mp.get_property("video-params/colormatrix") or ""
    local gamut_str = "BT.709"
    if prim:find("2020") or matrix:find("2020") then
        gamut_str = "BT.2020 (WCG)"
    elseif prim:find("dci-p3") or prim:find("p3") then
        gamut_str = "DCI-P3"
    elseif prim:find("601") or matrix:find("601") then
        gamut_str = "BT.601"
    elseif prim ~= "" then
        gamut_str = prim:upper()
    end

    local gamma = mp.get_property("video-params/gamma") or "sdr"
    local clean_gamma = format_clean_gamma(gamma)

    -- Dynamic RTX True HDR Detection (Color space & transfer curve progression)
    local vf_str = mp.get_property("vf") or ""
    local has_truehdr = vf_str:find("@truehdr") or vf_str:find("nvidia%-true%-hdr")

    local gamut_col = cfg.color_yellow
    local gamma_col = cfg.color_yellow

    if has_truehdr and not (prim:find("2020") or gamma == "pq" or gamma == "hlg") then
        gamut_str = string.format("%s -> BT.2020 (WCG)", gamut_str)
        gamut_col = cfg.color_green
        clean_gamma = string.format("%s -> HDR10 (PQ)", clean_gamma)
        gamma_col = cfg.color_green
    end

    return {
        filename = filename,
        file_items = {
            { "Container", file_format, cfg.color_cyan },
            { "File Size", file_size_str, cfg.color_white },
            { "Timeline", playback_str, cfg.color_white },
            { "Chapters", chap_str, cfg.color_white },
            { "Cache Ahead", cache_str, cfg.color_cyan }
        },
        video_items = {
            { "Video Codec", clean_codec, cfg.color_cyan },
            { "Hardware Dec", hw_tag, hw_col },
            { "Video Bitrate", v_bitrate_str, cfg.color_yellow },
            { "Resolution", res_str, res_col },
            { "Aspect Ratio", ar_str, cfg.color_white },
            { "Pixel Depth", depth_str, cfg.color_cyan },
            { "Color Gamut", gamut_str, gamut_col },
            { "Gamma Curve", clean_gamma, gamma_col }
        }
    }
end

-- Render ASS Video Diagnostics Box
local function draw_hud()
    if not is_enabled then
        overlay:remove()
        return
    end

    local d = mp.get_property_native("osd-dimensions")
    if not d or d.w == 0 or d.h == 0 then return end

    overlay.res_x = d.w
    overlay.res_y = d.h

    -- Base DPI scaling combined with user multiplier
    local base_scale = math.max(1.0, d.h / 1080)
    local scale = base_scale * (cfg.ui_scale or 1.0)

    local data = get_diagnostics_data()

    local sections = {
        { title = "FILE",  items = data.file_items },
        { title = "VIDEO", items = data.video_items }
    }

    -- Font Sizes & Geometric Spacing
    local title_size    = math.floor(13 * scale)
    local subtitle_size = math.floor(11.5 * scale)
    local section_size  = math.floor(10.5 * scale)
    local row_size      = math.floor(11.5 * scale)

    local row_step      = math.floor(19.5 * scale)
    local section_step  = math.floor(18 * scale)
    local section_gap   = math.floor(10 * scale)

    local top_pad       = math.floor(16 * scale)
    local header_gap    = math.floor(12 * scale)
    local bottom_pad    = math.floor(22 * scale)
    local pad_x         = math.floor(18 * scale)
    local indent_x      = math.floor(8 * scale)

    -- Dynamic Auto-Fit Height Calculation
    local total_rows = 0
    for _, sec in ipairs(sections) do
        total_rows = total_rows + #sec.items
    end

    local header_h = title_size + subtitle_size + math.floor(8 * scale)
    local sections_h = (#sections * section_step) + ((#sections - 1) * section_gap) + (total_rows * row_step)
    local box_h = top_pad + header_h + header_gap + sections_h + bottom_pad
    local box_w = math.floor(400 * scale) -- Symmetrical 400px width

    -- Coordinate placement: Top-Left
    local margin_x = math.floor(24 * scale)
    local margin_y = math.floor(24 * scale)
    local x1 = margin_x
    local x2 = x1 + box_w
    local y1 = margin_y
    local y2 = y1 + box_h

    local ass = assdraw.ass_new()

    -- 1. Outer Translucent Rounded Glass Container
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H0A0A0A&\\alpha&H%s&}", cfg.bg_alpha))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(x1, y1, x2, y2, 8 * scale)
    ass:draw_stop()

    -- 2. Top Accent Border (NVIDIA Green)
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H10&}", cfg.color_green))
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(x1, y1, x2, y1 + math.floor(3 * scale))
    ass:draw_stop()

    -- 3. Header Title & Truncated Media Name Subtitle
    local cur_y = y1 + top_pad
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}VIDEO MONITOR", 
        x1 + pad_x, cur_y, cfg.font_face, title_size, cfg.color_green))

    cur_y = cur_y + title_size + math.floor(4 * scale)
    local clean_title = truncate_string(data.filename, 38)
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        x1 + pad_x, cur_y, cfg.font_face, subtitle_size, cfg.color_white, clean_title))

    -- Subtle Horizontal Divider under Header
    cur_y = cur_y + subtitle_size + math.floor(8 * scale)
    ass:new_event()
    ass:append("{\\an7\\bord0\\shad0\\c&HFFFFFF&\\alpha&HD0&}")
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(x1 + pad_x, cur_y, x2 - pad_x, cur_y + 1)
    ass:draw_stop()

    cur_y = cur_y + math.floor(8 * scale)

    -- 4. Render Categorized Sections (Unified Green Headers with Vector Diamond)
    local d_rad = math.max(3, math.floor(3.5 * scale))
    for s_idx, sec in ipairs(sections) do
        local d_cx = x1 + pad_x + d_rad
        local d_cy = cur_y + math.floor(section_size * 0.52)
        local text_x = x1 + pad_x + (d_rad * 2) + math.floor(6 * scale)

        -- Section Header Vector Diamond Icon
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:move_to(d_cx, d_cy - d_rad)
        ass:line_to(d_cx + d_rad, d_cy)
        ass:line_to(d_cx, d_cy + d_rad)
        ass:line_to(d_cx - d_rad, d_cy)
        ass:draw_stop()

        -- Section Header Title Tag
        ass:new_event()
        ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
            text_x, cur_y, cfg.font_face, section_size, cfg.color_green, sec.title))

        cur_y = cur_y + section_step

        -- Section Item Rows (Indented for visual hierarchy)
        for _, item in ipairs(sec.items) do
            local label, val_text, val_color = item[1], item[2], item[3]

            -- Label (Left-aligned + Indented: \an7)
            ass:new_event()
            ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b0\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x1 + pad_x + indent_x, cur_y, cfg.font_face, row_size, cfg.color_gray, label))

            -- Value (Right-aligned: \an9)
            ass:new_event()
            ass:append(string.format("{\\an9\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x2 - pad_x, cur_y, cfg.font_face, row_size, val_color, val_text))

            cur_y = cur_y + row_step
        end

        -- Spacing between sections
        if s_idx < #sections then
            cur_y = cur_y + section_gap
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- Periodic refresh loop while visible
local function update_loop()
    if is_enabled then
        draw_hud()
    end
end

-- Explicit state setter with inter-script tracking
local function set_enabled(state)
    is_enabled = state
    mp.set_property_native("user-data/video-monitor-active", is_enabled)
    mp.set_property_native("user-data/media-monitor-active", is_enabled) -- Backwards compatibility
    if is_enabled then
        draw_hud()
        if not poll_timer then
            poll_timer = mp.add_periodic_timer(cfg.poll_interval, update_loop)
        end
    else
        if poll_timer then
            poll_timer:kill()
            poll_timer = nil
        end
        overlay:remove()
    end
end

-- Toggle overlay on/off individually
local function toggle_stats()
    set_enabled(not is_enabled)
end

-- Master toggle to open/close both overlays synchronously without desync
local function toggle_both()
    local video_active = mp.get_property_native("user-data/video-monitor-active") or false
    local gpu_active = mp.get_property_native("user-data/gpu-monitor-active") or false

    local target_state = not (video_active or gpu_active)
    set_enabled(target_state)
    mp.commandv("script-message", "set-gpu-monitor", target_state and "yes" or "no")
end

-- Keybindings and script messages
mp.add_forced_key_binding("i", "toggle-video-monitor-forced", toggle_stats)
mp.add_forced_key_binding("I", "toggle-video-monitor-I-forced", toggle_stats)
mp.add_forced_key_binding("TAB", "toggle-both-monitors-forced", toggle_both)

mp.register_script_message("toggle-both-monitors", toggle_both)
mp.register_script_message("toggle-both-overlays", toggle_both)
mp.register_script_message("toggle-video-monitor", toggle_stats)
mp.register_script_message("toggle-media-monitor", toggle_stats)
mp.register_script_message("toggle-media-stats", toggle_stats)

mp.register_script_message("set-video-monitor", function(val)
    if val == "yes" or val == "true" or val == "on" or val == "1" then
        set_enabled(true)
    elseif val == "no" or val == "false" or val == "off" or val == "0" then
        set_enabled(false)
    else
        toggle_stats()
    end
end)

mp.observe_property("osd-dimensions", "native", draw_hud)
mp.observe_property("pause", "bool", draw_hud)
mp.observe_property("vf", "native", draw_hud)
mp.observe_property("glsl-shaders", "native", draw_hud)
mp.observe_property("video-out-params", "native", draw_hud)
mp.observe_property("video-bitrate", "number", draw_hud)