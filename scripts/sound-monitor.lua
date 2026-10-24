-- =========================================================================
-- MPV Studio Audio Suite & Hi-Fi Telemetry Controller
-- Dynamic 7.1 Speaker Matrix, Channel Soloing, Full Hz & Spatial Audio HUD
-- =========================================================================

local mp = require("mp")
local utils = require("mp.utils")
local assdraw = require("mp.assdraw")

local is_enabled = false
local is_internal_af = false
local poll_timer = nil

-- Visual Configuration & Styling (Matches video-monitor & nvidia-monitor palette)
local cfg = {
    ui_scale        = 1.35,        -- User size multiplier (1.0 = normal, 1.35 = 4K recommended, 1.6 = TV)
    poll_interval   = 0.5,         -- Refresh interval in seconds
    font_face       = "Segoe UI",
    color_green     = "00E676",    -- NVIDIA Green (Headers, Active Upmix & Sync)
    color_cyan      = "00E5FF",    -- RivaTuner Cyan (Native Active Channels & Formats)
    color_yellow    = "00C8FF",    -- Amber Warning (Bitrates, Output device & Buffer)
    color_red       = "3B3BFF",    -- Critical Red / Mute
    color_white     = "FFFFFF",
    color_gray      = "9E9E9E",
    color_dark_box  = "1C1C1C",    -- Inactive Speaker Slot Background
    bg_alpha        = "35",        -- Glass backdrop opacity (Hex: 00-FF, 35 = ~80% dark)
}

local overlay = mp.create_osd_overlay("ass-events")

-- =========================================================================
-- Curated Studio Headphone DSP Presets Suite (Default: Bypass / OFF)
-- Preset 2: 7.1 Spatial Audio Expander (Immediate 1st press of 'A')
-- =========================================================================

local dsp_presets = {
    {
        id     = "direct",
        label  = "Direct / Bypass (OFF)",
        filter = "",
        engine = nil
    },
    {
        id     = "spatial_expander",
        label  = "7.1 Spatial Audio Expander",
        filter = "surround=chl_out=7.1",
        engine = "7.1 SPATIAL EXPANDER"
    },
    {
        id     = "bs2b",
        label  = "Bauer BS2B Headphone Crossfeed",
        filter = "bs2b=profile=default",
        engine = "BS2B CROSSFEED"
    },
    {
        id     = "stereowiden",
        label  = "Stereo Soundstage Expander",
        filter = "stereowiden",
        engine = "STEREO WIDENER"
    },
    {
        id     = "dynaudnorm",
        label  = "Dynamic Normalizer (Night Mode)",
        filter = "dynaudnorm",
        engine = "DYNAUDNORM"
    }
}

-- =========================================================================
-- Professional Zero-Clipping Audiophile Bass Boost Presets
-- Utilizes negative pre-attenuation headroom to eliminate digital clipping
-- =========================================================================

local bass_presets = {
    {
        id       = "off",
        label    = "Off (Direct)",
        filter   = "",
        gain_tag = nil
    },
    {
        id       = "warmth",
        label    = "Clean Warmth (+4 dB)",
        filter   = "lavfi=[bass=f=80:g=4:w=0.6,volume=-4dB]",
        gain_tag = "+4dB"
    },
    {
        id       = "punch",
        label    = "Deep Punch (+7 dB)",
        filter   = "lavfi=[bass=f=65:g=7:w=0.7,volume=-7dB]",
        gain_tag = "+7dB"
    },
    {
        id       = "sub",
        label    = "Sub-Bass Club (+10 dB)",
        filter   = "lavfi=[bass=f=50:g=10:w=0.8,volume=-10dB]",
        gain_tag = "+10dB"
    }
}

-- =========================================================================
-- Channel Soloing Definitions (Adapts dynamically to 2.0 / 5.1 / 7.1)
-- =========================================================================

local solo_modes = {
    {
        id         = "all",
        label      = "All Channels (Full)",
        active_spk = { FL = true, FR = true, C = true, LFE = true, SL = true, SR = true, BL = true, BR = true }
    },
    {
        id         = "center",
        label      = "Solo Center (Voice / Dialogue)",
        active_spk = { C = true }
    },
    {
        id         = "front",
        label      = "Solo Front L/R (Stereo Music)",
        active_spk = { FL = true, FR = true }
    },
    {
        id         = "surround",
        label      = "Solo Surrounds (Side + Rear FX)",
        active_spk = { SL = true, SR = true, BL = true, BR = true }
    },
    {
        id         = "rear",
        label      = "Solo Rear Back (BL / BR)",
        active_spk = { BL = true, BR = true }
    },
    {
        id         = "side",
        label      = "Solo Side Surrounds (SL / SR)",
        active_spk = { SL = true, SR = true }
    },
    {
        id         = "lfe",
        label      = "Solo Subwoofer (LFE / Bass)",
        active_spk = { LFE = true }
    }
}

local current_dsp_idx  = 1 -- Default: Direct / Bypass (OFF)
local current_solo_idx = 1 -- Default: All Channels
local current_bass_idx = 1 -- Default: Bass Boost Off
local draw_hud             -- Forward declaration

-- Format clean short channel notation
local function format_channels_clean(ch)
    if not ch or ch == "" then return "" end
    ch = tostring(ch):lower()
    if ch:find("7.1") then return "7.1" end
    if ch:find("5.1") then return "5.1" end
    if ch == "stereo" or ch == "2" or ch == "2ch" then return "2.0" end
    if ch == "mono" or ch == "1" or ch == "1ch" then return "1.0" end
    if ch == "quad" or ch == "4" then return "4.0" end
    local num = ch:match("(%d+%.?%d*)")
    return num or ch
end

-- Resolve the true native stream channel layout
local function get_native_layout()
    local ch = mp.get_property("audio-params/channels") or ""
    local clean = format_channels_clean(ch)
    return clean ~= "" and clean or "2.0"
end

-- Format Sample Rate to FULL Hertz number with thousands separator (e.g. 48.000 Hz)
local function format_sample_rate_full(sr)
    if not sr or sr <= 0 then return "N/A" end
    local formatted = tostring(math.floor(sr))
    while true do
        local k
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
        if k == 0 then break end
    end
    return formatted .. " Hz"
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

-- Build layout-adaptive FFmpeg isolation filter
local function get_adaptive_solo_filter(mode_id, layout)
    if mode_id == "all" then return "" end

    if layout == "7.1" or current_dsp_idx == 2 then
        if mode_id == "center"   then return "lavfi=[pan=7.1|c2=c2]" end
        if mode_id == "front"    then return "lavfi=[pan=7.1|c0=c0|c1=c1]" end
        if mode_id == "surround" then return "lavfi=[pan=7.1|c4=c4|c5=c5|c6=c6|c7=c7]" end
        if mode_id == "rear"     then return "lavfi=[pan=7.1|c4=c4|c5=c5]" end
        if mode_id == "side"     then return "lavfi=[pan=7.1|c6=c6|c7=c7]" end
        if mode_id == "lfe"      then return "lavfi=[pan=7.1|c3=c3]" end

    elseif layout == "5.1" then
        if mode_id == "center"   then return "lavfi=[pan=5.1|c2=c2]" end
        if mode_id == "front"    then return "lavfi=[pan=5.1|c0=c0|c1=c1]" end
        if mode_id == "surround" then return "lavfi=[pan=5.1|c4=c4|c5=c5]" end
        if mode_id == "rear"     then return "lavfi=[pan=5.1|c4=c4|c5=c5]" end
        if mode_id == "side"     then return "lavfi=[pan=5.1|c4=c4|c5=c5]" end
        if mode_id == "lfe"      then return "lavfi=[pan=5.1|c3=c3]" end

    else -- 2.0 Stereo
        if mode_id == "center"   then return "lavfi=[pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1]" end
        if mode_id == "front"    then return "lavfi=[pan=stereo|c0=c0|c1=c1]" end
        if mode_id == "surround" then return "lavfi=[pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0]" end
        if mode_id == "rear"     then return "lavfi=[pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0]" end
        if mode_id == "side"     then return "lavfi=[pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0]" end
        if mode_id == "lfe"      then return "lavfi=[lowpass=f=120]" end
    end
    return ""
end

-- Composite multi-layered audio filter chain cleanly without collisions
local function apply_audio_filters()
    local filters = {}
    local layout = get_native_layout()

    -- Layer 1: Base DSP Preset
    local dsp = dsp_presets[current_dsp_idx]
    if dsp and dsp.filter ~= "" then
        table.insert(filters, dsp.filter)
    end

    -- Layer 2: Native-Aware Channel Solo Isolation
    if current_solo_idx > 1 then
        local solo = solo_modes[current_solo_idx]
        local solo_filter = get_adaptive_solo_filter(solo.id, layout)
        if solo_filter ~= "" then
            table.insert(filters, solo_filter)
        end
    end

    -- Layer 3: Audiophile Zero-Clipping Bass Boost
    if current_bass_idx > 1 then
        local bass = bass_presets[current_bass_idx]
        if bass and bass.filter ~= "" then
            table.insert(filters, bass.filter)
        end
    end

    local combined = table.concat(filters, ",")
    is_internal_af = true
    mp.set_property("af", combined)
    is_internal_af = false

    if draw_hud then draw_hud() end
end

-- Toggleable Channel Solo Controller
local function set_channel_solo(mode_id)
    if current_solo_idx > 1 and solo_modes[current_solo_idx].id == mode_id then
        current_solo_idx = 1
        apply_audio_filters()
        mp.osd_message("Audio Channel: All Channels (Full)", 2.5)
        return
    end

    for idx, mode in ipairs(solo_modes) do
        if mode.id == mode_id then
            current_solo_idx = idx
            apply_audio_filters()
            mp.osd_message("Audio Channel: " .. mode.label, 2.5)
            return
        end
    end
end

local function cycle_channel_solo()
    current_solo_idx = (current_solo_idx % #solo_modes) + 1
    apply_audio_filters()
    local mode = solo_modes[current_solo_idx]
    mp.osd_message("Audio Channel: " .. mode.label, 2.5)
end

-- Professional Zero-Clipping Bass Boost Cycler
local function cycle_bass_boost()
    current_bass_idx = (current_bass_idx % #bass_presets) + 1
    apply_audio_filters()
    local b = bass_presets[current_bass_idx]
    mp.osd_message("Audiophile Bass Boost: " .. b.label, 2.5)
end

local function cycle_audio_dsp()
    current_dsp_idx = (current_dsp_idx % #dsp_presets) + 1
    apply_audio_filters()
    local selected = dsp_presets[current_dsp_idx]
    mp.osd_message("Audio DSP: " .. selected.label, 2.5)
end

local function reset_audio_dsp()
    current_dsp_idx  = 1 -- Direct / Bypass (OFF)
    current_solo_idx = 1 -- All Channels
    current_bass_idx = 1 -- Bass Boost Off
    is_internal_af = true
    mp.set_property("af", "")
    is_internal_af = false
    mp.osd_message("Audio DSP: Direct / Bit-Perfect (OFF)", 2)
    if draw_hud then draw_hud() end
end

-- =========================================================================
-- Helper Utilities & Audio Telemetry Resolvers
-- =========================================================================

local function truncate_string(str, max_len)
    if not str then return "" end
    if #str > max_len then return str:sub(1, max_len - 3) .. "..." end
    return str
end

local function format_time(seconds)
    if not seconds or seconds < 0 then return "00:00" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function get_meta_tag(keys)
    local meta = mp.get_property_native("metadata")
    if not meta then return "" end
    for _, key in ipairs(keys) do
        local val = meta[key] or meta[key:lower()] or meta[key:upper()]
        if val and val ~= "" then return tostring(val) end
    end
    return ""
end

local function format_clean_audio_codec(c)
    if not c or c == "" or c == "NONE" then return "NONE" end
    local lower = c:lower()
    if lower:find("opus") then return "OPUS"
    elseif lower:find("flac") then return "FLAC"
    elseif lower:find("mp3") then return "MP3"
    elseif lower:find("aac") then return "AAC"
    elseif lower:find("truehd") then return "TrueHD"
    elseif lower:find("dts-hd") then return "DTS-HD"
    elseif lower:find("dts") then return "DTS"
    elseif lower:find("eac3") then return "E-AC3"
    elseif lower:find("ac3") then return "AC3"
    elseif lower:find("vorbis") then return "Vorbis"
    elseif lower:find("alac") then return "ALAC"
    elseif lower:find("pcm") then return "PCM" end
    return c:upper()
end

local function get_bit_depth(fmt)
    if not fmt or fmt == "" then return "N/A" end
    if fmt:find("s16") or fmt:find("u16") then return "16-bit" end
    if fmt:find("s24") or fmt:find("u24") then return "24-bit" end
    if fmt:find("s32") or fmt:find("u32") then return "32-bit" end
    if fmt:find("float") or fmt:find("f32") or fmt:find("flt") then return "32-bit Float" end
    return fmt:upper()
end

local function get_audio_track_layout_string(has_audio)
    if not has_audio then return "None", cfg.color_gray end

    local atrack = mp.get_property_native("current-tracks/audio")
    local raw_codec = atrack and (atrack.codec or mp.get_property("audio-codec-name") or "") or ""
    local clean_c = format_clean_audio_codec(raw_codec)

    if current_solo_idx > 1 then
        return string.format("%s (%s)", clean_c, solo_modes[current_solo_idx].label), cfg.color_yellow
    end

    local layout = get_native_layout()
    local out_ch = mp.get_property("audio-out-params/channels") or ""
    local out_clean = format_channels_clean(out_ch)

    if out_clean ~= "" and out_clean ~= layout then
        return string.format("%s (%s -> %s)", clean_c, layout, out_clean), cfg.color_green
    else
        return string.format("%s (%s)", clean_c, layout), cfg.color_yellow
    end
end

-- =========================================================================
-- Render Centered Studio Audio Suite
-- =========================================================================

draw_hud = function()
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

    -- Check if actual audio stream exists
    local atrack = mp.get_property_native("current-tracks/audio")
    local vtrack = mp.get_property_native("current-tracks/video")
    local is_pure_image = (vtrack and vtrack.image == true and vtrack.albumart ~= true)
    local has_audio = (atrack ~= nil and not is_pure_image)

    -- ---------------- Metadata & Playback Metrics ----------------
    local title = get_meta_tag({"title", "TIT2"})
    if title == "" then
        title = mp.get_property("media-title") or mp.get_property("filename/no-ext") or "Unknown Track"
    end
    local artist = get_meta_tag({"artist", "album_artist", "TPE1", "aART"})
    if artist == "" then artist = "Unknown Artist" end
    local album = get_meta_tag({"album", "TALB"})
    local year = get_meta_tag({"date", "year", "originalyear", "TYER"})
    if year and #year > 4 then year = year:sub(1, 4) end

    local track_num = get_meta_tag({"track", "tracknumber", "TRCK"})
    local disc_num = get_meta_tag({"disc", "discnumber", "TPOS"})
    local pl_pos = mp.get_property_number("playlist-pos-1", 1)
    local pl_count = mp.get_property_number("playlist-count", 1)

    local pos = mp.get_property_number("time-pos", 0)
    local dur = mp.get_property_number("duration", 0)
    local progress_pct = dur > 0 and math.floor((pos / dur) * 100) or 0
    local timeline_str = string.format("%s / %s (%d%%)", format_time(pos), format_time(dur), progress_pct)

    -- Telemetry: Signal & Hardware Processing (Non-redundant)
    local dsp_engine_name = dsp_presets[current_dsp_idx].label
    local dsp_engine_col = cfg.color_cyan
    if not has_audio or current_dsp_idx == 1 then
        dsp_engine_col = cfg.color_gray
    end
    if current_solo_idx > 1 then
        dsp_engine_name = "Channel Isolation (" .. solo_modes[current_solo_idx].id:upper() .. ")"
        dsp_engine_col = cfg.color_yellow
    end

    -- Determine real Spatial Audio state accurately
    local layout = get_native_layout()
    local is_spatial_active = has_audio and (current_dsp_idx == 2 or layout == "7.1" or layout == "5.1")
    local spatial_text = "N/A"
    local spatial_col = cfg.color_gray
    if has_audio then
        if is_spatial_active then
            spatial_text = "Spatial Audio"
            spatial_col = cfg.color_yellow
        else
            spatial_text = "Off"
            spatial_col = cfg.color_gray
        end
    end

    local vol = mp.get_property_number("volume", 100)
    local is_mute = mp.get_property_bool("mute", false)
    local replaygain = get_meta_tag({"replaygain_track_gain", "REPLAYGAIN_TRACK_GAIN"})
    local vol_str = has_audio and string.format("%d%% %s", math.floor(vol + 0.5), is_mute and "[MUTED]" or "") or "N/A"
    if has_audio and replaygain ~= "" then vol_str = vol_str .. " (RG: " .. replaygain .. ")" end

    local signal_items = {
        { "DSP Engine", dsp_engine_name, dsp_engine_col },
        { "Bass Boost", bass_presets[current_bass_idx].label, (current_bass_idx > 1) and cfg.color_yellow or cfg.color_gray },
        { "Spatial Audio", spatial_text, spatial_col },
        { "Volume / RG", vol_str, (not has_audio) and cfg.color_gray or (is_mute and cfg.color_red or cfg.color_white) }
    }

    -- Telemetry: Audio Stream
    local audio_track_str, audio_track_col = get_audio_track_layout_string(has_audio)

    local abr = mp.get_property_number("audio-bitrate", 0)
    local abr_str = (has_audio and abr > 0) and format_bitrate(abr) or "N/A"

    local in_sr = mp.get_property_number("audio-params/samplerate", 0)
    local sr_full_str = (has_audio and in_sr > 0) and format_sample_rate_full(in_sr) or "N/A"

    local in_fmt = mp.get_property("audio-params/format") or ""
    local bitdepth_str = has_audio and get_bit_depth(in_fmt) or "N/A"

    local av_sync_str = "N/A"
    local av_sync_col = cfg.color_gray
    if has_audio then
        local av_sync = mp.get_property_number("avsync", 0)
        av_sync_str = string.format("%+.2f ms", av_sync * 1000)
        av_sync_col = (math.abs(av_sync) < 0.02) and cfg.color_green or cfg.color_yellow
    end

    local ao_dev = "N/A"
    local ao_col = cfg.color_gray
    if has_audio then
        ao_dev = (mp.get_property("current-ao") or "AUDIO"):upper()
        ao_col = cfg.color_yellow
    end

    local audio_items = {
        { "Audio Track", audio_track_str, audio_track_col },
        { "Bitrate", abr_str, has_audio and cfg.color_yellow or cfg.color_gray },
        { "Sample Rate", sr_full_str, has_audio and cfg.color_white or cfg.color_gray },
        { "Audio Depth", bitdepth_str, has_audio and cfg.color_yellow or cfg.color_gray },
        { "A/V Sync", av_sync_str, av_sync_col },
        { "Audio Output", ao_dev, ao_col }
    }

    -- Telemetry: Metadata
    local cache_secs = mp.get_property_number("demuxer-cache-duration", 0)
    local cache_state = mp.get_property_native("demuxer-cache-state") or {}
    local cache_bytes = type(cache_state) == "table" and (cache_state["total-bytes"] or 0) or 0
    local cache_str = string.format("%.1fs (%.1f MB)", cache_secs, cache_bytes / (1024 * 1024))

    local track_info_str = track_num ~= "" and ("Track " .. track_num) or string.format("Track %02d/%02d", pl_pos, pl_count)
    if disc_num ~= "" then track_info_str = track_info_str .. " (Disc " .. disc_num .. ")" end

    local album_full = album ~= "" and album or "Unknown Album"
    if year and year ~= "" then album_full = album_full .. " (" .. year .. ")" end

    local meta_items = {
        { "Album", album_full, cfg.color_white },
        { "Index", track_info_str, cfg.color_cyan },
        { "Timeline", timeline_str, cfg.color_white },
        { "Cache Ahead", cache_str, cfg.color_cyan }
    }

    local sections = {
        { title = "SIGNAL",   items = signal_items },
        { title = "AUDIO",    items = audio_items },
        { title = "METADATA", items = meta_items }
    }

    -- ---------------- Spacing & Geometric Dimensions ----------------
    local title_size    = math.floor(13 * scale)
    local subtitle_size = math.floor(11.5 * scale)
    local section_size  = math.floor(10.5 * scale)
    local row_size      = math.floor(11.5 * scale)

    local row_step      = math.floor(19.5 * scale)
    local section_step  = math.floor(18 * scale)
    local section_gap   = math.floor(10 * scale)

    local top_pad       = math.floor(16 * scale)
    local header_gap    = math.floor(10 * scale)
    local bottom_pad    = math.floor(20 * scale)
    local pad_x         = math.floor(20 * scale)
    local indent_x      = math.floor(8 * scale)

    -- 3-Row Surround Matrix Geometry (Strictly 3 Columns)
    local spk_h         = math.floor(19 * scale)
    local spk_gap_y     = math.floor(5 * scale)
    local matrix_h      = (3 * spk_h) + (2 * spk_gap_y)
    local matrix_gap    = math.floor(12 * scale)

    -- Dynamic Height Calculation
    local total_rows = 0
    for _, sec in ipairs(sections) do total_rows = total_rows + #sec.items end

    local header_h = title_size + subtitle_size + math.floor(8 * scale)
    local matrix_total_h = section_step + matrix_h + matrix_gap
    local sections_h = (#sections * section_step) + ((#sections - 1) * section_gap) + (total_rows * row_step)
    local box_h = top_pad + header_h + header_gap + matrix_total_h + sections_h + bottom_pad
    
    -- Symmetrical 400px width (Matches video-monitor & nvidia-monitor)
    local box_w = math.floor(400 * scale)

    local margin_y = math.floor(24 * scale)
    local x1 = math.floor((d.w - box_w) / 2)
    local x2 = x1 + box_w
    local y1 = margin_y
    local y2 = y1 + box_h

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
    ass:rect_cw(x1, y1, x2, y1 + math.floor(3 * scale))
    ass:draw_stop()

    -- 3. Header Title & Active Track Name Subtitle
    local cur_y = y1 + top_pad
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}AUDIO MONITOR", 
        x1 + pad_x, cur_y, cfg.font_face, title_size, cfg.color_green))

    cur_y = cur_y + title_size + math.floor(4 * scale)
    local clean_track_title = truncate_string(artist .. " — " .. title, 42)
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        x1 + pad_x, cur_y, cfg.font_face, subtitle_size, cfg.color_white, clean_track_title))

    -- Subtle Horizontal Divider under Header
    cur_y = cur_y + subtitle_size + math.floor(8 * scale)
    ass:new_event()
    ass:append("{\\an7\\bord0\\shad0\\c&HFFFFFF&\\alpha&HD0&}")
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(x1 + pad_x, cur_y, x2 - pad_x, cur_y + 1)
    ass:draw_stop()

    cur_y = cur_y + math.floor(10 * scale)

    -- 4. Speaker Section Header (Vector Diamond Icon)
    local d_rad = math.max(3, math.floor(3.5 * scale))
    local d_cx = x1 + pad_x + d_rad
    local d_cy = cur_y + math.floor(section_size * 0.52)
    local text_x = x1 + pad_x + (d_rad * 2) + math.floor(6 * scale)

    local matrix_title = has_audio and (current_solo_idx > 1 and "SPEAKER [SOLO]" or "SPEAKER") or "SPEAKER [STANDBY]"
    local matrix_color = has_audio and (current_solo_idx > 1 and cfg.color_yellow or cfg.color_green) or cfg.color_gray

    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", matrix_color))
    ass:pos(0, 0)
    ass:draw_start()
    ass:move_to(d_cx, d_cy - d_rad)
    ass:line_to(d_cx + d_rad, d_cy)
    ass:line_to(d_cx, d_cy + d_rad)
    ass:line_to(d_cx - d_rad, d_cy)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        text_x, cur_y, cfg.font_face, section_size, matrix_color, matrix_title))

    cur_y = cur_y + section_step

    -- 5. Draw Real-time Speaker Matrix (Max 3 Columns, Physical Layout)
    local spk_grid = {
        { { id = "FL", label = "FL" }, { id = "C", label = "C" },     { id = "FR", label = "FR" } },
        { { id = "SL", label = "SL" }, { id = "LFE", label = "LFE" }, { id = "SR", label = "SR" } },
        { { id = "BL", label = "BL" }, nil,                           { id = "BR", label = "BR" } }
    }

    local function is_spk_active(spk_id)
        if not has_audio then return false end

        if current_solo_idx > 1 then
            return solo_modes[current_solo_idx].active_spk[spk_id] == true
        end

        if current_dsp_idx == 2 then
            return true
        end

        local layout = get_native_layout()
        local out_ch = mp.get_property("audio-out-params/channels") or ""
        local effective = format_channels_clean(out_ch)
        if effective == "" then effective = layout end

        if effective == "7.1" then
            return true
        elseif effective == "5.1" then
            return (spk_id == "FL" or spk_id == "FR" or spk_id == "C" or spk_id == "LFE" or spk_id == "SL" or spk_id == "SR")
        elseif effective == "2.0" or effective == "2" then
            return (spk_id == "FL" or spk_id == "FR")
        elseif effective == "1.0" or effective == "1" then
            return (spk_id == "C" or spk_id == "FL")
        end
        return (spk_id == "FL" or spk_id == "FR")
    end

    local avail_w = (x2 - pad_x) - (x1 + pad_x)
    local spk_gap_x = math.floor(10 * scale)
    local spk_w = math.floor((avail_w - (spk_gap_x * 2)) / 3)

    for r_idx, row in ipairs(spk_grid) do
        local ry = cur_y + (r_idx - 1) * (spk_h + spk_gap_y)
        for c_idx = 1, 3 do
            local spk = row[c_idx]
            if spk then
                local rx = (x1 + pad_x) + (c_idx - 1) * (spk_w + spk_gap_x)
                local active = is_spk_active(spk.id)

                ass:new_event()
                ass:pos(0, 0)
                ass:draw_start()
                if active then
                    local bg_col = (current_solo_idx > 1) and cfg.color_yellow or ((current_dsp_idx == 2) and cfg.color_green or cfg.color_cyan)
                    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H40&}", bg_col))
                    ass:round_rect_cw(rx, ry, rx + spk_w, ry + spk_h, 4 * scale)
                else
                    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H90&}", cfg.color_dark_box))
                    ass:round_rect_cw(rx, ry, rx + spk_w, ry + spk_h, 4 * scale)
                end
                ass:draw_stop()

                local text_color = active and cfg.color_white or cfg.color_gray
                local font_weight = active and "\\b1" or "\\b0"
                local lbl_fs = math.floor(9.5 * scale)
                ass:new_event()
                ass:append(string.format("{\\an5\\pos(%d,%d)\\fn%s%s\\fs%d\\c&H%s&\\bord0\\shad0}%s", 
                    rx + math.floor(spk_w / 2), ry + math.floor(spk_h / 2), cfg.font_face, font_weight, lbl_fs, text_color, spk.label))
            end
        end
    end

    cur_y = cur_y + matrix_h + matrix_gap

    -- 6. Render Categorized Telemetry Sections (Unified Green Vector Headers)
    for s_idx, sec in ipairs(sections) do
        local scx = x1 + pad_x + d_rad
        local scy = cur_y + math.floor(section_size * 0.52)
        local stx = x1 + pad_x + (d_rad * 2) + math.floor(6 * scale)

        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:move_to(scx, scy - d_rad)
        ass:line_to(scx + d_rad, scy)
        ass:line_to(scx, scy + d_rad)
        ass:line_to(scx - d_rad, scy)
        ass:draw_stop()

        ass:new_event()
        ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
            stx, cur_y, cfg.font_face, section_size, cfg.color_green, sec.title))

        cur_y = cur_y + section_step

        for _, item in ipairs(sec.items) do
            local label, val_text, val_color = item[1], item[2], item[3]

            ass:new_event()
            ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b0\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x1 + pad_x + indent_x, cur_y, cfg.font_face, row_size, cfg.color_gray, label))

            ass:new_event()
            ass:append(string.format("{\\an9\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x2 - pad_x, cur_y, cfg.font_face, row_size, val_color, val_text))

            cur_y = cur_y + row_step
        end

        if s_idx < #sections then
            cur_y = cur_y + section_gap
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- Refresh loop
local function update_loop()
    if is_enabled then
        draw_hud()
    end
end

-- State management
local function set_enabled(state)
    is_enabled = state
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

local function toggle_hud()
    set_enabled(not is_enabled)
end

-- =========================================================================
-- Script Messages & Handlers
-- =========================================================================

mp.register_script_message("toggle-audio-hud", toggle_hud)
mp.register_script_message("cycle-audio-dsp", cycle_audio_dsp)
mp.register_script_message("reset-audio-dsp", reset_audio_dsp)

-- Channel Soloing Messages (Toggle on/off natively supported)
mp.register_script_message("cycle-channel-solo", cycle_channel_solo)
mp.register_script_message("set-channel-solo", set_channel_solo)

-- Zero-Clipping Audiophile Bass Boost
mp.register_script_message("cycle-bass-boost", cycle_bass_boost)

-- Automatically open Studio HUD when starting pure audio / music files & clear filters
local function on_file_loaded()
    current_dsp_idx  = 1 -- Default: Direct / Bypass (OFF)
    current_solo_idx = 1 -- Default: All Channels
    current_bass_idx = 1 -- Default: Bass Boost Off

    -- Clean mpv audio filter property to match internal state reset
    is_internal_af = true
    mp.set_property("af", "")
    is_internal_af = false

    local vtrack = mp.get_property_native("current-tracks/video")
    local is_image = vtrack and vtrack.image == true
    local is_albumart = vtrack and vtrack.albumart == true
    local is_pure_audio = (vtrack == nil) or is_albumart

    if is_pure_audio and not is_image then
        set_enabled(true)
    else
        set_enabled(false)
    end
end

mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", function() set_enabled(false) end)

-- Observe mpv filter property for external resets (e.g. key '0' in input.conf)
mp.observe_property("af", "string", function(_, val)
    if is_internal_af then return end
    if not val or val == "" then
        current_dsp_idx  = 1
        current_solo_idx = 1
        current_bass_idx = 1
    end
    if draw_hud then draw_hud() end
end)

-- Reactive property observers
mp.observe_property("osd-dimensions", "native", draw_hud)
mp.observe_property("pause", "bool", draw_hud)
mp.observe_property("volume", "number", draw_hud)
mp.observe_property("mute", "bool", draw_hud)
mp.observe_property("audio-params", "native", draw_hud)
mp.observe_property("audio-out-params", "native", draw_hud)
mp.observe_property("audio-bitrate", "number", draw_hud)