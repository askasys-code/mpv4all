-- =========================================================================
-- MPV Modern Bottom Bar & Interactive Controller (V3.2 Guaranteed Autohide)
-- NVIDIA Dark Glass Aesthetic, Live Badges & Real Autohide Lifecycle
-- Fully Standalone Engine (Zero Overlap & Zero Lingering Overlays)
-- =========================================================================

local mp = require("mp")
local utils = require("mp.utils")
local assdraw = require("mp.assdraw")

-- Visual Configuration & Styling (Matches suite monitors 1:1)
local cfg = {
    ui_scale        = 1.35,        -- User size multiplier (1.0 = normal, 1.35 = 4K, 1.6 = TV)
    font_face       = "Segoe UI",
    color_green     = "00E676",    -- NVIDIA Green (Headers, Progress, Active items)
    color_cyan      = "00E5FF",    -- RivaTuner Cyan (Timestamps & Badges)
    color_yellow    = "00C8FF",    -- Amber Warning (Volume & Durations)
    color_red       = "3B3BFF",    -- Critical Red / Mute
    color_white     = "FFFFFF",
    color_gray      = "9E9E9E",    -- Inactive labels & descriptions
    color_dark_box  = "1C1C1C",    -- Track & Selection highlights
    bg_alpha        = "35",        -- Box transparency (Hex: 00-FF, 35 = ~80% dark)
    autohide_delay  = 2.0,         -- Seconds of mouse inactivity before hiding
}

local overlay = mp.create_osd_overlay("ass-events")
local is_visible = false
local hide_timer = nil

-- Decoupled Render Engine State
local render_pending = false
local is_dragging_seek = false
local is_dragging_vol = false
local is_hover_bar = false
local drag_ratio = 0.0
local last_seek_ratio = -1
local last_seek_time = 0
local mouse_x, mouse_y = -1, -1

-- Popup Menu State ("audio" | "sub" | nil)
local active_menu = nil

-- Geometry Hitbox Tracking
local bar_layout = {
    x1 = 0, y1 = 0, x2 = 0, y2 = 0,
    sb_x1 = 0, sb_y1 = 0, sb_x2 = 0, sb_y2 = 0,
    btn_play = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 },
    btn_audio = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 },
    btn_sub = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 },
    btn_vol = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 },
    vol_slider = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 }
}

local menu_layout = {
    x1 = 0, y1 = 0, x2 = 0, y2 = 0,
    items = {}
}

-- Forward declarations
local draw_bar, enable_bar_clicks, disable_bar_clicks

-- Direct & Guaranteed Overlay Removal
local function hide_bar()
    if not is_visible then return end
    is_visible = false
    is_hover_bar = false
    is_dragging_seek = false
    is_dragging_vol = false
    active_menu = nil
    if hide_timer then
        hide_timer:kill()
        hide_timer = nil
    end
    disable_bar_clicks()
    overlay:remove()
end

-- Decoupled 60fps Render Dispatcher
local function request_render()
    if not is_visible then
        overlay:remove()
        return
    end
    if render_pending then return end
    render_pending = true
    mp.add_timeout(0.016, function()
        render_pending = false
        if is_visible then
            draw_bar()
        else
            overlay:remove()
        end
    end)
end

-- Format seconds into clean HH:MM:SS or MM:SS
local function format_time(seconds)
    if not seconds or seconds < 0 then return "00:00" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

local function truncate_string(str, max_len)
    if not str then return "" end
    if #str > max_len then return str:sub(1, max_len - 3) .. "..." end
    return str
end

-- Resolve active dynamic range state
local function get_dynamic_range_badge()
    local vf_str = mp.get_property("vf") or ""
    if vf_str:find("@truehdr") or vf_str:find("nvidia%-true%-hdr") then
        return "RTX TRUE HDR", cfg.color_green
    end

    local gamma = mp.get_property("video-params/gamma") or ""
    local sig_peak = mp.get_property_number("video-params/sig-peak", 1.0)
    local colormatrix = mp.get_property("video-params/colormatrix") or ""

    if gamma == "pq" then return "HDR10 (PQ)", cfg.color_cyan
    elseif gamma == "hlg" then return "HDR (HLG)", cfg.color_cyan
    elseif sig_peak > 1.05 or colormatrix:find("bt.2020") then return "BT.2020", cfg.color_cyan end

    return "SDR", cfg.color_gray
end

-- Resolve active upscaler engine
local function get_active_upscaler_badge()
    local vf_str = mp.get_property("vf") or ""
    if vf_str:find("@vsr") or vf_str:find("scaling%-mode=nvidia") then
        return "RTX VSR", cfg.color_green
    end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    if #shaders > 0 then
        for _, s in ipairs(shaders) do
            if s:find("NVScaler") then return "NIS", cfg.color_cyan end
            if s:find("FSR") then return "FSR 1.0", cfg.color_cyan end
            if s:find("SGSR") then return "SGSR", cfg.color_cyan end
            if s:find("CAS") then return "CAS", cfg.color_cyan end
        end
        return "GLSL", cfg.color_cyan
    end
    return "LANCZOS", cfg.color_gray
end

-- Find chapter name at given timestamp
local function get_chapter_title_at(time_sec)
    local chapters = mp.get_property_native("chapter-list") or {}
    if #chapters == 0 then return nil end
    local current_title = nil
    for _, ch in ipairs(chapters) do
        if ch.time and ch.time <= time_sec then
            current_title = ch.title
        else
            break
        end
    end
    return current_title
end

-- Format audio channels cleanly
local function format_channels(ch)
    if not ch then return "Stereo 2.0" end
    local s = tostring(ch):lower()
    if ch == 8 or s:find("7.1") or s:find("8ch") or s:find("octagonal") then
        return "7.1"
    elseif ch == 6 or s:find("5.1") or s:find("6ch") or s:find("hexagonal") then
        return "5.1"
    elseif ch == 2 or s:find("stereo") or s:find("2ch") then
        return "Stereo 2.0"
    elseif ch == 1 or s:find("mono") or s:find("1ch") then
        return "Mono 1.0"
    end
    return s
end

-- Clean Audio label
local function get_clean_audio_label()
    local atrack = mp.get_property_native("current-tracks/audio")
    if not atrack then return "No Audio" end

    local ch = atrack["audio-channels"] or atrack.demux_channel_count or mp.get_property("audio-params/channels")
    local ch_str = format_channels(ch)

    local lang = atrack.lang or ""
    lang = lang:match("^%s*(.-)%s*$"):upper()
    if lang == "UND" or lang == "UNK" or lang == "UNKNOWN" then
        lang = ""
    end

    if lang ~= "" then
        return lang .. " • " .. ch_str
    else
        return ch_str
    end
end

-- Clean Subtitle label
local function get_clean_sub_label()
    local subtrack = mp.get_property_native("current-tracks/sub")
    local sid = mp.get_property("sid")
    if not subtrack or sid == "no" or sid == nil then
        return "Sub Off"
    end

    local lang = subtrack.lang or ""
    lang = lang:match("^%s*(.-)%s*$"):upper()
    if lang == "UND" or lang == "UNK" or lang == "UNKNOWN" then
        lang = ""
    end

    local title = subtrack.title or ""
    title = title:match("^%s*(.-)%s*$")
    if subtrack.forced and not title:lower():find("forced") then
        title = (title ~= "") and (title .. " (Forced)") or "Forced"
    end

    if lang ~= "" then
        if title ~= "" then
            return lang .. " • " .. title
        else
            return lang
        end
    else
        if title ~= "" then
            return title
        else
            return "Sub " .. tostring(subtrack.id or 1)
        end
    end
end

-- =========================================================================
-- Render Loop Engine
-- =========================================================================

draw_bar = function()
    local is_clip_maker = mp.get_property_native("user-data/clip-maker-active") or false
    if not is_visible or is_clip_maker then
        overlay:remove()
        return
    end

    local d = mp.get_property_native("osd-dimensions")
    if not d or d.w == 0 or d.h == 0 then return end

    overlay.res_x = d.w
    overlay.res_y = d.h

    local base_scale = math.max(1.0, d.h / 1080)
    local scale = base_scale * (cfg.ui_scale or 1.0)

    -- Bar Geometry (Floating at bottom center)
    local pad_x = math.floor(20 * scale)
    local margin_x = math.floor(24 * scale)
    local margin_bottom = math.floor(18 * scale)

    local bar_w = d.w - (margin_x * 2)
    local bar_h = math.floor(74 * scale)

    local x1 = margin_x
    local x2 = x1 + bar_w
    local y2 = d.h - margin_bottom
    local y1 = y2 - bar_h

    bar_layout.x1, bar_layout.y1 = x1, y1
    bar_layout.x2, bar_layout.y2 = x2, y2

    local ass = assdraw.ass_new()

    -- 1. Outer Translucent Glass Container
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
    ass:rect_cw(x1, y1, x2, y1 + math.max(2, math.floor(2.5 * scale)))
    ass:draw_stop()

    -- Media Title & Telemetry Header Row
    local media_title = mp.get_property("media-title") or mp.get_property("filename/no-ext") or "No Media"
    local title_fs = math.floor(11.5 * scale)
    local info_y = y1 + math.floor(10 * scale)

    -- Vector Diamond Header
    local d_rad = math.max(3, math.floor(3 * scale))
    local d_cx = x1 + pad_x + d_rad
    local d_cy = info_y + math.floor(title_fs * 0.55)

    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_green))
    ass:pos(0, 0)
    ass:draw_start()
    ass:move_to(d_cx, d_cy - d_rad)
    ass:line_to(d_cx + d_rad, d_cy)
    ass:line_to(d_cx, d_cy + d_rad)
    ass:line_to(d_cx - d_rad, d_cy)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
        d_cx + d_rad + math.floor(6 * scale), info_y, cfg.font_face, title_fs, cfg.color_white, truncate_string(media_title, 48)))

    -- Right Telemetry Badges
    local upscaler_tag, upscaler_col = get_active_upscaler_badge()
    local hdr_tag, hdr_col = get_dynamic_range_badge()
    local badge_fs = math.floor(10 * scale)

    local hwdec = mp.get_property("hwdec-current") or "no"
    local hw_tag = (hwdec ~= "" and hwdec ~= "no") and "HW" or "SW"
    local hw_col = (hwdec ~= "" and hwdec ~= "no") and cfg.color_green or cfg.color_gray

    local badge_str = string.format("{\\c&H%s&}[%s]   {\\c&H%s&}[%s]   {\\c&H%s&}[%s]", 
        hw_col, hw_tag, upscaler_col, upscaler_tag, hdr_col, hdr_tag)

    ass:new_event()
    ass:append(string.format("{\\an9\\pos(%d,%d)\\fn%s\\b1\\fs%d\\bord1\\3c&H000000&\\shad1}%s",
        x2 - pad_x, info_y, cfg.font_face, badge_fs, badge_str))

    -- 3. Interactive Seekbar Geometry
    local sb_x1 = x1 + pad_x
    local sb_x2 = x2 - pad_x
    local sb_h = math.max(4, math.floor(5 * scale))
    local sb_y1 = y1 + math.floor(32 * scale)
    local sb_y2 = sb_y1 + sb_h

    bar_layout.sb_x1, bar_layout.sb_y1 = sb_x1, sb_y1
    bar_layout.sb_x2, bar_layout.sb_y2 = sb_x2, sb_y2

    local pos = mp.get_property_number("time-pos", 0)
    local dur = mp.get_property_number("duration", 0)
    local effective_ratio = is_dragging_seek and drag_ratio or ((dur > 0) and math.min(1.0, math.max(0.0, pos / dur)) or 0)

    -- Background Track
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H80&}", cfg.color_dark_box))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(sb_x1, sb_y1, sb_x2, sb_y2, 2 * scale)
    ass:draw_stop()

    -- Cache Ahead Buffer Line (Cyan)
    local cache_secs = mp.get_property_number("demuxer-cache-duration", 0)
    if dur > 0 and cache_secs > 0 and not is_dragging_seek then
        local cache_prog = math.min(1.0, (pos + cache_secs) / dur)
        local cache_x = sb_x1 + math.floor((sb_x2 - sb_x1) * cache_prog)
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&HB0&}", cfg.color_cyan))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(sb_x1, sb_y1, cache_x, sb_y2, 2 * scale)
        ass:draw_stop()
    end

    -- Active Progress Line (NVIDIA Green)
    local cur_prog_x = sb_x1 + math.floor((sb_x2 - sb_x1) * effective_ratio)
    if cur_prog_x > sb_x1 then
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(sb_x1, sb_y1, cur_prog_x, sb_y2, 2 * scale)
        ass:draw_stop()
    end

    -- Seek Handle Knob
    local handle_r = math.floor(4.5 * scale)
    local handle_cy = math.floor((sb_y1 + sb_y2) / 2)
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_white))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cur_prog_x - handle_r, handle_cy - handle_r, cur_prog_x + handle_r, handle_cy + handle_r, handle_r)
    ass:draw_stop()

    -- Chapter Markers
    local chapters = mp.get_property_native("chapter-list") or {}
    if dur > 0 and #chapters > 0 then
        for _, ch in ipairs(chapters) do
            if ch.time and ch.time > 0 and ch.time < dur then
                local ch_x = sb_x1 + math.floor((sb_x2 - sb_x1) * (ch.time / dur))
                ass:new_event()
                ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H30&}", cfg.color_white))
                ass:pos(0, 0)
                ass:draw_start()
                ass:rect_cw(ch_x - 1, sb_y1 - 1, ch_x + 1, sb_y2 + 1)
                ass:draw_stop()
            end
        end
    end

    -- 4. Playback Controls & Status Row
    local ctrl_y = y1 + math.floor(46 * scale)
    local is_paused = mp.get_property_bool("pause", false)
    local play_symbol = is_paused and "▶" or "❚❚"
    local play_col = is_paused and cfg.color_yellow or cfg.color_green

    -- Play/Pause Button Hitbox
    bar_layout.btn_play.x1 = sb_x1
    bar_layout.btn_play.y1 = ctrl_y
    bar_layout.btn_play.x2 = sb_x1 + math.floor(25 * scale)
    bar_layout.btn_play.y2 = ctrl_y + math.floor(20 * scale)

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
        sb_x1, ctrl_y, cfg.font_face, math.floor(13 * scale), play_col, play_symbol))

    -- Real-time Timestamps
    local display_time = is_dragging_seek and (effective_ratio * dur) or pos
    local time_str = string.format("%s / %s", format_time(display_time), format_time(dur))
    if dur > 0 then
        time_str = time_str .. string.format("  {\\c&H%s&}[-%s]{\\c&H%s&}", cfg.color_gray, format_time(dur - display_time), cfg.color_cyan)
    end

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
        sb_x1 + math.floor(30 * scale), ctrl_y + math.floor(1 * scale), cfg.font_face, math.floor(11.5 * scale), cfg.color_cyan, time_str))

    -- Right Controls: Clickable Volume Slider & Dynamic Track Buttons
    local vol = mp.get_property_number("volume", 100)
    local is_mute = mp.get_property_bool("mute", false)
    local vol_col = is_mute and cfg.color_red or cfg.color_yellow
    local vol_str = is_mute and "[MUTED]" or string.format("VOL %d%%", math.floor(vol + 0.5))

    -- Volume Slider Dimensions (Clickable & Draggable)
    local vs_w = math.floor(62 * scale)
    local vs_h = math.max(3, math.floor(4.5 * scale))
    local vs_x2 = sb_x2
    local vs_x1 = vs_x2 - vs_w
    local vs_y1 = ctrl_y + math.floor(8 * scale)
    local vs_y2 = vs_y1 + vs_h

    bar_layout.vol_slider.x1 = vs_x1
    bar_layout.vol_slider.x2 = vs_x2
    bar_layout.vol_slider.y1 = vs_y1 - math.floor(8 * scale)
    bar_layout.vol_slider.y2 = vs_y2 + math.floor(8 * scale)

    -- Volume Text Button (Mute Toggle)
    local vt_w = math.floor(64 * scale)
    local vt_x2 = vs_x1 - math.floor(6 * scale)
    local vt_x1 = vt_x2 - vt_w
    bar_layout.btn_vol.x1 = vt_x1
    bar_layout.btn_vol.x2 = vt_x2
    bar_layout.btn_vol.y1 = ctrl_y
    bar_layout.btn_vol.y2 = ctrl_y + math.floor(22 * scale)

    -- Render Volume Text
    ass:new_event()
    ass:append(string.format("{\\an5\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
        vt_x1 + math.floor(vt_w / 2), ctrl_y + math.floor(10 * scale), cfg.font_face, math.floor(10.5 * scale), vol_col, vol_str))

    -- Render Volume Slider Background
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H80&}", cfg.color_dark_box))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(vs_x1, vs_y1, vs_x2, vs_y2, 2 * scale)
    ass:draw_stop()

    -- Render Volume Slider Level
    local vol_ratio = math.max(0.0, math.min(1.0, (is_mute and 0 or vol) / 100))
    local cur_vol_x = vs_x1 + math.floor((vs_x2 - vs_x1) * vol_ratio)
    if cur_vol_x > vs_x1 then
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", is_mute and cfg.color_red or cfg.color_yellow))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(vs_x1, vs_y1, cur_vol_x, vs_y2, 2 * scale)
        ass:draw_stop()
    end

    -- Volume Slider Knob
    local v_knob_r = math.floor(3.5 * scale)
    local v_knob_cy = math.floor((vs_y1 + vs_y2) / 2)
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_white))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cur_vol_x - v_knob_r, v_knob_cy - v_knob_r, cur_vol_x + v_knob_r, v_knob_cy + v_knob_r, v_knob_r)
    ass:draw_stop()

    -- Dynamic Track Labels
    local audio_label = get_clean_audio_label()
    local sub_label = get_clean_sub_label()

    local audio_btn_col = (active_menu == "audio") and cfg.color_green or cfg.color_white
    local sub_btn_col = (active_menu == "sub") and cfg.color_green or cfg.color_white

    -- Adaptive button widths
    local sub_btn_w = math.max(math.floor(70 * scale), math.floor((#sub_label * 6.5 + 18) * scale))
    bar_layout.btn_sub.x2 = vt_x1 - math.floor(10 * scale)
    bar_layout.btn_sub.x1 = bar_layout.btn_sub.x2 - sub_btn_w
    bar_layout.btn_sub.y1 = ctrl_y
    bar_layout.btn_sub.y2 = ctrl_y + math.floor(22 * scale)

    local audio_btn_w = math.max(math.floor(75 * scale), math.floor((#audio_label * 6.5 + 18) * scale))
    bar_layout.btn_audio.x2 = bar_layout.btn_sub.x1 - math.floor(8 * scale)
    bar_layout.btn_audio.x1 = bar_layout.btn_audio.x2 - audio_btn_w
    bar_layout.btn_audio.y1 = ctrl_y
    bar_layout.btn_audio.y2 = ctrl_y + math.floor(22 * scale)

    -- Render Subtitle Button
    ass:new_event()
    ass:append(string.format("{\\an5\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}[%s]",
        bar_layout.btn_sub.x1 + math.floor(sub_btn_w / 2), ctrl_y + math.floor(10 * scale), cfg.font_face, math.floor(10 * scale), sub_btn_col, truncate_string(sub_label, 26)))

    -- Render Audio Button
    ass:new_event()
    ass:append(string.format("{\\an5\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
        bar_layout.btn_audio.x1 + math.floor(audio_btn_w / 2), ctrl_y + math.floor(10 * scale), cfg.font_face, math.floor(10 * scale), audio_btn_col, truncate_string(audio_label, 26)))

    -- 5. Floating Tooltip Tag above Seekbar
    local is_hover_sb = (mouse_x >= sb_x1 and mouse_x <= sb_x2 and mouse_y >= (sb_y1 - math.floor(14 * scale)) and mouse_y <= (sb_y2 + math.floor(14 * scale)))
    if (is_hover_sb or is_dragging_seek) and dur > 0 and not active_menu then
        local target_ratio = is_dragging_seek and drag_ratio or math.max(0.0, math.min(1.0, (mouse_x - sb_x1) / (sb_x2 - sb_x1)))
        local hover_time = target_ratio * dur
        local tip_str = format_time(hover_time)

        local chapter_title = get_chapter_title_at(hover_time)
        if chapter_title and chapter_title ~= "" then
            tip_str = tip_str .. " • " .. truncate_string(chapter_title, 22)
        end

        local tip_w = math.floor((#tip_str * 6.5 + 20) * scale)
        local tip_h = math.floor(20 * scale)
        local tip_x1 = math.max(sb_x1, math.min(sb_x2 - tip_w, (sb_x1 + math.floor((sb_x2 - sb_x1) * target_ratio)) - math.floor(tip_w / 2)))
        local tip_x2 = tip_x1 + tip_w
        local tip_y2 = sb_y1 - math.floor(8 * scale)
        local tip_y1 = tip_y2 - tip_h

        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H0A0A0A&\\alpha&H%s&}", cfg.bg_alpha))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(tip_x1, tip_y1, tip_x2, tip_y2, 4 * scale)
        ass:draw_stop()

        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H20&}", cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:rect_cw(tip_x1, tip_y1, tip_x2, tip_y1 + 1)
        ass:draw_stop()

        ass:new_event()
        ass:append(string.format("{\\an5\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord0\\shad0}%s",
            tip_x1 + math.floor(tip_w / 2), tip_y1 + math.floor(tip_h / 2), cfg.font_face, math.floor(9.5 * scale), cfg.color_green, tip_str))
    end

    -- 6. Interactive Popup Menu (Audio / Subtitles Track Selector)
    menu_layout.items = {}
    if active_menu then
        local track_type = active_menu
        local menu_title = (track_type == "audio") and "SELECT AUDIO TRACK" or "SELECT SUBTITLE TRACK"
        local current_track = mp.get_property_native("current-tracks/" .. track_type)
        local current_id = current_track and current_track.id or "no"

        local raw_tracks = mp.get_property_native("track-list") or {}
        local track_items = {}

        if track_type == "sub" then
            table.insert(track_items, {
                id = "no",
                label = "Off / Disabled",
                is_active = (current_id == "no" or current_id == nil)
            })
        end

        for _, t in ipairs(raw_tracks) do
            if t.type == track_type then
                local lang = (t.lang and t.lang ~= "") and t.lang:upper() or ""
                if lang == "UND" or lang == "UNK" then lang = "" end

                local title = t.title or ""
                local codec = (t.codec and t.codec ~= "") and t.codec:upper() or ""
                local details = {}

                if track_type == "audio" then
                    local ch = format_channels(t["audio-channels"] or t.demux_channel_count)
                    if ch ~= "" then table.insert(details, ch) end
                    if codec ~= "" then table.insert(details, codec) end
                elseif track_type == "sub" then
                    if t.forced then table.insert(details, "Forced") end
                    if codec ~= "" then table.insert(details, codec) end
                end

                local detail_str = (#details > 0) and (" (" .. table.concat(details, " • ") .. ")") or ""
                local full_label
                if lang ~= "" then
                    full_label = (title ~= "") and (lang .. " • " .. title .. detail_str) or (lang .. detail_str)
                else
                    full_label = (title ~= "") and (title .. detail_str) or ((#details > 0) and table.concat(details, " • ") or ("Track " .. tostring(t.id)))
                end

                table.insert(track_items, {
                    id = t.id,
                    label = full_label,
                    is_active = (current_id == t.id)
                })
            end
        end

        local item_h = math.floor(22 * scale)
        local header_h = math.floor(30 * scale)
        local menu_pad = math.floor(12 * scale)
        local menu_w = math.floor(340 * scale)
        local menu_h = header_h + (#track_items * item_h) + (menu_pad * 2)

        local anchor_btn = (track_type == "audio") and bar_layout.btn_audio or bar_layout.btn_sub
        local mx2 = math.min(d.w - margin_x, anchor_btn.x2 + math.floor(110 * scale))
        local mx1 = mx2 - menu_w
        local my2 = y1 - math.floor(8 * scale)
        local my1 = my2 - menu_h

        menu_layout.x1, menu_layout.y1 = mx1, my1
        menu_layout.x2, menu_layout.y2 = mx2, my2

        -- Menu Container Background
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H0A0A0A&\\alpha&H%s&}", cfg.bg_alpha))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(mx1, my1, mx2, my2, 6 * scale)
        ass:draw_stop()

        -- Top Green Accent
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H10&}", cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:rect_cw(mx1, my1, mx2, my1 + math.max(2, math.floor(2.5 * scale)))
        ass:draw_stop()

        -- Menu Title Header
        local m_cur_y = my1 + menu_pad
        ass:new_event()
        ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s",
            mx1 + menu_pad, m_cur_y, cfg.font_face, math.floor(11 * scale), cfg.color_green, menu_title))

        -- Divider
        m_cur_y = m_cur_y + math.floor(16 * scale)
        ass:new_event()
        ass:append("{\\an7\\bord0\\shad0\\c&HFFFFFF&\\alpha&HD0&}")
        ass:pos(0, 0)
        ass:draw_start()
        ass:rect_cw(mx1 + menu_pad, m_cur_y, mx2 - menu_pad, m_cur_y + 1)
        ass:draw_stop()

        m_cur_y = m_cur_y + math.floor(6 * scale)

        -- Render Track List Items
        for _, item in ipairs(track_items) do
            local iy1 = m_cur_y
            local iy2 = iy1 + item_h
            local is_hover = (mouse_x >= mx1 and mouse_x <= mx2 and mouse_y >= iy1 and mouse_y <= iy2)

            table.insert(menu_layout.items, {
                id = item.id,
                x1 = mx1, y1 = iy1, x2 = mx2, y2 = iy2
            })

            if is_hover then
                ass:new_event()
                ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H60&}", cfg.color_dark_box))
                ass:pos(0, 0)
                ass:draw_start()
                ass:round_rect_cw(mx1 + math.floor(4 * scale), iy1, mx2 - math.floor(4 * scale), iy2, 3 * scale)
                ass:draw_stop()
            end

            local bullet = item.is_active and "● " or "○ "
            local bullet_col = item.is_active and cfg.color_green or cfg.color_gray
            local text_col = item.is_active and cfg.color_white or (is_hover and cfg.color_cyan or cfg.color_gray)
            local item_str = truncate_string(item.label, 36)

            ass:new_event()
            ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s{\\c&H%s&}%s",
                mx1 + menu_pad + math.floor(4 * scale), iy1 + math.floor(3 * scale), cfg.font_face, math.floor(10 * scale), bullet_col, bullet, text_col, item_str))

            m_cur_y = m_cur_y + item_h
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- =========================================================================
-- Visibility & Input Handlers
-- =========================================================================

local function show_bar()
    if mp.get_property_native("user-data/clip-maker-active") then
        hide_bar()
        return
    end

    is_visible = true
    request_render()

    -- Guaranteed Autohide Timer: Disappears after 2s of inactivity
    if hide_timer then hide_timer:kill() end
    if not is_dragging_seek and not is_dragging_vol and not active_menu then
        hide_timer = mp.add_timeout(cfg.autohide_delay, function()
            if not is_dragging_seek and not is_dragging_vol and not active_menu then
                hide_bar()
            end
        end)
    end
end

-- Non-blocking mouse movement handler
local function on_mouse_move()
    local x, y = mp.get_mouse_pos()
    mouse_x, mouse_y = x, y

    local d = mp.get_property_native("osd-dimensions")
    if not d or d.h == 0 then return end

    if mp.get_property_native("user-data/clip-maker-active") then
        hide_bar()
        return
    end

    local in_bar = is_visible and (x >= bar_layout.x1 and x <= bar_layout.x2 and y >= bar_layout.y1 and y <= bar_layout.y2)
    local in_menu = active_menu and (x >= menu_layout.x1 and x <= menu_layout.x2 and y >= menu_layout.y1 and y <= menu_layout.y2)
    is_hover_bar = (in_bar or in_menu)

    local in_trigger_zone = (y >= (d.h * 0.82))

    if in_trigger_zone or is_dragging_seek or is_dragging_vol or active_menu then
        show_bar()
    elseif is_visible then
        -- Refresh autohide countdown if moving in upper screen area
        if not hide_timer or not hide_timer:is_enabled() then
            hide_timer = mp.add_timeout(cfg.autohide_delay, function()
                if not is_dragging_seek and not is_dragging_vol and not active_menu then
                    hide_bar()
                end
            end)
        end
    end

    if is_hover_bar or is_dragging_seek or is_dragging_vol or active_menu then
        enable_bar_clicks()
    else
        disable_bar_clicks()
    end

    -- High-Performance Scrubbing
    if is_dragging_seek and bar_layout.sb_x2 > bar_layout.sb_x1 then
        drag_ratio = math.max(0.0, math.min(1.0, (x - bar_layout.sb_x1) / (bar_layout.sb_x2 - bar_layout.sb_x1)))
        local now = mp.get_time()
        if (now - last_seek_time >= 0.04) and (math.abs(drag_ratio - last_seek_ratio) >= 0.002) then
            last_seek_time = now
            last_seek_ratio = drag_ratio
            mp.commandv("seek", drag_ratio * 100, "absolute-percent", "keyframes")
        end
    end

    -- Volume Slider Dragging
    if is_dragging_vol and bar_layout.vol_slider.x2 > bar_layout.vol_slider.x1 then
        local vs_x1 = bar_layout.vol_slider.x1
        local vs_x2 = bar_layout.vol_slider.x2
        local v_ratio = math.max(0.0, math.min(1.0, (x - vs_x1) / (vs_x2 - vs_x1)))
        mp.commandv("set", "volume", math.floor(v_ratio * 100 + 0.5))
        if mp.get_property_bool("mute", false) then
            mp.set_property_bool("mute", false)
        end
    end

    request_render()
end

-- Mouse Click Handler
local function on_mouse_press()
    if not is_visible then return end

    -- 1. Check Popup Menu Item Selection
    if active_menu then
        for _, item in ipairs(menu_layout.items) do
            if mouse_x >= item.x1 and mouse_x <= item.x2 and mouse_y >= item.y1 and mouse_y <= item.y2 then
                if active_menu == "audio" then
                    mp.set_property("aid", item.id)
                elseif active_menu == "sub" then
                    mp.set_property("sid", item.id)
                end
                active_menu = nil
                show_bar()
                return
            end
        end

        if mouse_x < menu_layout.x1 or mouse_x > menu_layout.x2 or mouse_y < menu_layout.y1 or mouse_y > menu_layout.y2 then
            active_menu = nil
            show_bar()
        end
    end

    -- 2. Play/Pause Button
    local bp = bar_layout.btn_play
    if mouse_x >= bp.x1 and mouse_x <= bp.x2 and mouse_y >= bp.y1 and mouse_y <= bp.y2 then
        mp.commandv("cycle", "pause")
        show_bar()
        return
    end

    -- 3. Volume Mute Toggle Button
    local bv = bar_layout.btn_vol
    if mouse_x >= bv.x1 and mouse_x <= bv.x2 and mouse_y >= bv.y1 and mouse_y <= bv.y2 then
        mp.commandv("cycle", "mute")
        show_bar()
        return
    end

    -- 4. Volume Slider Bar Click/Drag
    local vs = bar_layout.vol_slider
    if mouse_x >= vs.x1 and mouse_x <= vs.x2 and mouse_y >= vs.y1 and mouse_y <= vs.y2 then
        is_dragging_vol = true
        local v_ratio = math.max(0.0, math.min(1.0, (mouse_x - vs.x1) / (vs.x2 - vs.x1)))
        mp.commandv("set", "volume", math.floor(v_ratio * 100 + 0.5))
        if mp.get_property_bool("mute", false) then
            mp.set_property_bool("mute", false)
        end
        show_bar()
        return
    end

    -- 5. Audio Menu Toggle
    local ba = bar_layout.btn_audio
    if mouse_x >= ba.x1 and mouse_x <= ba.x2 and mouse_y >= ba.y1 and mouse_y <= ba.y2 then
        active_menu = (active_menu == "audio") and nil or "audio"
        show_bar()
        return
    end

    -- 6. Subtitle Menu Toggle
    local bs = bar_layout.btn_sub
    if mouse_x >= bs.x1 and mouse_x <= bs.x2 and mouse_y >= bs.y1 and mouse_y <= bs.y2 then
        active_menu = (active_menu == "sub") and nil or "sub"
        show_bar()
        return
    end

    -- 7. Seekbar Scrubbing Trigger
    local sb = bar_layout
    if mouse_x >= sb.sb_x1 and mouse_x <= sb.sb_x2 and mouse_y >= (sb.sb_y1 - 14) and mouse_y <= (sb.sb_y2 + 14) then
        active_menu = nil
        is_dragging_seek = true
        drag_ratio = math.max(0.0, math.min(1.0, (mouse_x - sb.sb_x1) / (sb.sb_x2 - sb.sb_x1)))
        last_seek_ratio = drag_ratio
        last_seek_time = mp.get_time()

        mp.commandv("seek", drag_ratio * 100, "absolute-percent", "keyframes")
        show_bar()
    end
end

-- Immediate Release Handler
local function on_mouse_release()
    if is_dragging_seek then
        is_dragging_seek = false
        last_seek_ratio = -1
        mp.commandv("seek", drag_ratio * 100, "absolute-percent", "keyframes")
        show_bar()
    end

    if is_dragging_vol then
        is_dragging_vol = false
        show_bar()
    end

    if not is_hover_bar and not active_menu then
        disable_bar_clicks()
    end
end

-- Dynamic click binding manager
local clicks_bound = false

enable_bar_clicks = function()
    if clicks_bound then return end
    clicks_bound = true

    mp.add_forced_key_binding("MBTN_LEFT", "mbb_mouse_left", function(e)
        if e.event == "down" or e.event == "press" then
            on_mouse_press()
        elseif e.event == "up" then
            on_mouse_release()
        end
    end, { complex = true })

    mp.add_forced_key_binding("WHEEL_UP", "mbb_wheel_up", function()
        if is_visible and is_hover_bar then mp.commandv("add", "volume", 2) end
    end)

    mp.add_forced_key_binding("WHEEL_DOWN", "mbb_wheel_down", function()
        if is_visible and is_hover_bar then mp.commandv("add", "volume", -2) end
    end)
end

disable_bar_clicks = function()
    if not clicks_bound or is_dragging_seek or is_dragging_vol or active_menu then return end
    clicks_bound = false
    mp.remove_key_binding("mbb_mouse_left")
    mp.remove_key_binding("mbb_wheel_up")
    mp.remove_key_binding("mbb_wheel_down")
end

-- =========================================================================
-- Observers & Events
-- =========================================================================

mp.observe_property("time-pos", "number", function()
    if is_visible and not is_dragging_seek then request_render() end
end)
mp.observe_property("pause", "bool", function() if is_visible then request_render() end end)
mp.observe_property("volume", "number", function() if is_visible then request_render() end end)
mp.observe_property("mute", "bool", function() if is_visible then request_render() end end)
mp.observe_property("demuxer-cache-duration", "number", function() if is_visible then request_render() end end)
mp.observe_property("osd-dimensions", "native", function() if is_visible then request_render() end end)
mp.observe_property("track-list", "native", function() if is_visible then request_render() end end)
mp.observe_property("current-tracks/audio", "native", function() if is_visible then request_render() end end)
mp.observe_property("current-tracks/sub", "native", function() if is_visible then request_render() end end)

-- Observe clip maker activity to immediately hide bar
mp.observe_property("user-data/clip-maker-active", "bool", function(_, active)
    if active then
        hide_bar()
    end
end)

mp.register_event("end-file", hide_bar)

-- Track mouse motion across the window
mp.add_forced_key_binding("MOUSE_MOVE", "mbb_mouse_move", on_mouse_move)

-- Direct Script Messages
mp.register_script_message("toggle-bottom-bar", function()
    if is_visible then
        hide_bar()
    else
        show_bar()
    end
end)