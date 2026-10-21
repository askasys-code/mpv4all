-- =========================================================================
-- MPV High-End Audiophile & Studio Audio HUD
-- Pixel-Perfect Floating Capsule Aligned to Artwork & Permanent Hi-Fi Rack
-- =========================================================================

local mp = require("mp")
local assdraw = require("mp.assdraw")
local mpopts = require("mp.options")

-- Default configuration options
local opts = {
    enable_hud = true,
    font_face = "sans-serif",
    
    -- Album Art Floating Capsule Layout
    capsule_margin_top = 14,        -- Top offset from artwork edge (scaled)
    capsule_height = 54,            -- Slim container height in pixels (scaled)
    capsule_padding_x = 16,         -- Horizontal inner padding (scaled)
    capsule_max_width = 960,        -- Maximum width limit for the capsule
    bg_opacity = "40",              -- Backdrop opacity (Hex: 00-FF, 40 = ~75% dark)
    
    -- Color Palette (ASS Hex format: BBGGRR)
    color_lossless = "78C850",     -- Emerald Green (True Lossless / Bit-Perfect)
    color_lossy    = "3BB0FF",     -- Warm Amber (Lossy: Opus, MP3, AAC)
    color_cyan     = "D7C800",     -- Studio Cyan (Direct PCM pipeline / Exclusive mode)
    color_gold     = "00A5FF",     -- Gold / Orange (Track, Disc & Container info)
    color_white    = "FFFFFF",     -- Pure White (Main Track Title)
    color_silver   = "D0D0D0",     -- Light Silver (Artist & Album)
    color_muted    = "888888",     -- Muted Slate (Labels, ReplayGain & Secondary Details)
    
    force_osc_always = true         -- Keep MPV's native OSC bar visible during audio
}

mpopts.read_options(opts, "audio_player")

local is_audio_active = false
local hud_visible = true

-- Sanitize strings to avoid ASS parser collisions
local function escape_ass(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("{", "\\{")
    str = str:gsub("}", "\\}")
    str = str:gsub("\n", " ")
    return str
end

-- Retrieve metadata tag checking standard casing and alternative keys
local function get_meta_tag(keys)
    local meta = mp.get_property_native("metadata")
    if not meta then return "" end
    for _, key in ipairs(keys) do
        local val = meta[key] or meta[key:lower()] or meta[key:upper()]
        if val and val ~= "" then
            return tostring(val)
        end
    end
    return ""
end

-- Format seconds into standard MM:SS
local function format_time(seconds)
    if not seconds or seconds <= 0 then return "" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

-- Determine if current playback is audio-focused
local function is_audio_stream()
    local has_video = mp.get_property("current-tracks/video") ~= nil
    local is_albumart = mp.get_property_bool("current-tracks/video/albumart", false)
    return (not has_video) or is_albumart
end

-- Translate FFmpeg sample format into human-readable bit depth
local function get_bit_depth(fmt)
    if not fmt or fmt == "" then return "" end
    if fmt:find("s16") or fmt:find("u16") then return "16-bit" end
    if fmt:find("s24") or fmt:find("u24") then return "24-bit" end
    if fmt:find("s32") or fmt:find("u32") then return "32-bit" end
    if fmt:find("float") or fmt:find("double") or fmt:find("flt") or fmt:find("dbl") then
        return "32-bit Float"
    end
    return ""
end

-- Format sample rate (including high-resolution PCM, DXD, and native DSD rates)
local function format_sample_rate(sr)
    if not sr or sr <= 0 then return "" end
    if sr == 2822400 then return "DSD64 (2.82 MHz)" end
    if sr == 5644800 then return "DSD128 (5.64 MHz)" end
    if sr == 11289600 then return "DSD256 (11.28 MHz)" end
    if sr == 22579200 then return "DSD512 (22.58 MHz)" end
    if sr == 352800 then return "352.8 kHz DXD" end
    if sr == 384000 then return "384.0 kHz" end

    if sr % 1000 == 0 then
        return string.format("%d kHz", sr / 1000)
    else
        return string.format("%.1f kHz", sr / 1000)
    end
end

-- Map audio channel topology
local function format_channels(ch)
    if not ch or ch == "" then return "" end
    if ch == "stereo" or ch == "2" then return "2.0 Stereo" end
    if ch == "mono" or ch == "1" then return "1.0 Mono" end
    if ch == "5.1" or ch == "5.1(side)" then return "5.1 Surround" end
    if ch == "7.1" then return "7.1 Surround" end
    return ch .. " ch"
end

-- Clean container / demuxer format representation
local function format_container(raw_codec)
    local fmt = mp.get_property("file-format") or ""
    if fmt == "" then return "" end
    fmt = fmt:lower()
    local c = (raw_codec or ""):lower()

    -- Suppress redundant native standard containers
    -- 1. Standalone .opus files are natively wrapped in an Ogg container (RFC 7845)
    if c:find("opus") and fmt:find("ogg") then return "" end
    -- 2. Native FLAC
    if c:find("flac") and fmt:find("flac") then return "" end
    -- 3. Native MP3
    if c:find("mp3") and fmt:find("mp3") then return "" end
    -- 4. Native WAV / PCM
    if c:find("pcm") and fmt:find("wav") then return "" end

    if fmt:find("ogg") then return "OGG" end
    if fmt:find("matroska") or fmt:find("mkv") or fmt:find("mka") then return "MKA" end
    if fmt:find("mp4") or fmt:find("m4a") or fmt:find("mov") then return "M4A" end
    if fmt:find("webm") then return "WEBM" end
    if fmt:find("flac") then return "FLAC" end
    if fmt:find("mp3") then return "MP3" end
    if fmt:find("wav") then return "WAV" end
    return fmt:upper()
end

-- Codec mapping and Lossless vs Lossy classification
local function analyze_codec(raw_codec)
    if not raw_codec or raw_codec == "" then
        return "AUDIO", false
    end

    local c = raw_codec:lower()
    local lossless_table = {
        ["flac"] = "FLAC", ["alac"] = "ALAC", ["wavpack"] = "WavPack",
        ["ape"] = "Monkey's Audio", ["pcm_s16le"] = "WAV / PCM",
        ["pcm_s24le"] = "WAV / PCM", ["pcm_s32le"] = "WAV / PCM",
        ["pcm_f32le"] = "WAV / Float", ["truehd"] = "Dolby TrueHD",
        ["dts-hd ma"] = "DTS-HD MA"
    }

    local lossy_table = {
        ["opus"] = "Opus", ["mp3"] = "MP3", ["aac"] = "AAC",
        ["vorbis"] = "Ogg Vorbis", ["ac3"] = "Dolby Digital",
        ["eac3"] = "Dolby Digital Plus", ["dts"] = "DTS Core"
    }

    if lossless_table[c] then return lossless_table[c], true end
    if lossy_table[c] then return lossy_table[c], false end
    if c:find("dsd") then return "DSD", true end
    if c:find("pcm") then return "PCM", true end

    return raw_codec:upper(), false
end

-- Format byte sizes into readable MB values
local function format_file_size()
    local size = mp.get_property_number("file-size", 0)
    if size <= 0 then return "" end
    return string.format("%.1f MB", size / (1024 * 1024))
end

-- Hardware Signal Path Evaluation including Shared vs Exclusive WASAPI detection
local function get_signal_path_status(is_lossless, in_sr, out_sr)
    local af_list = mp.get_property_native("af") or {}
    local active_filters = {}

    for _, filter in ipairs(af_list) do
        if filter.enabled ~= false then
            table.insert(active_filters, filter.name or "dsp")
        end
    end

    -- 1. Active DSP takes visual precedence
    if #active_filters > 0 then
        local filter_name = table.concat(active_filters, ", ")
        return "DSP ACTIVE (" .. filter_name:upper() .. ")", opts.color_gold
    end

    -- 2. Resampling detected
    if in_sr > 0 and out_sr > 0 and in_sr ~= out_sr then
        return string.format("RESAMPLED (%s -> %s)", format_sample_rate(in_sr), format_sample_rate(out_sr)), opts.color_lossy
    end

    -- 3. Check WASAPI Exclusive vs Shared status
    local is_exclusive = mp.get_property_bool("audio-exclusive", false)
    local mode_tag = is_exclusive and "EXCLUSIVE" or "SHARED"

    if is_lossless then
        if is_exclusive then
            return "BIT-PERFECT DIRECT (" .. mode_tag .. ")", opts.color_lossless
        else
            return "DIRECT STREAM (" .. mode_tag .. ")", opts.color_cyan
        end
    else
        return "DIRECT PCM (" .. mode_tag .. ")", opts.color_cyan
    end
end

-- Clear active OSD canvas
local function clear_osd()
    local screen_w, screen_h = mp.get_osd_size()
    if screen_w and screen_h then
        mp.set_osd_ass(screen_w, screen_h, "")
    end
end

-- Main OSD Rendering Routine (Permanently displayed during audio)
local function render_dashboard()
    if not is_audio_active or not hud_visible or not opts.enable_hud then
        clear_osd()
        return
    end

    local dims = mp.get_property_native("osd-dimensions") or {}
    local fallback_w, fallback_h = mp.get_osd_size()
    local screen_w = dims.w or fallback_w or 0
    local screen_h = dims.h or fallback_h or 0

    if screen_w == 0 or screen_h == 0 then
        return
    end

    local scale = math.max(0.65, math.min(screen_h / 720, 2.0))
    local has_albumart = mp.get_property_bool("current-tracks/video/albumart", false)

    -- Accurate video/artwork rectangle accounting for pillarbox/letterbox margins
    local ml = dims.ml or 0
    local mr = dims.mr or 0
    local mt = dims.mt or 0
    local vid_x = ml
    local vid_y = mt
    local vid_w = math.max(1, screen_w - ml - mr)

    -- Metadata Retrieval
    local title = get_meta_tag({"title", "TIT2"})
    if title == "" then
        title = mp.get_property("media-title") or mp.get_property("filename/no-ext") or "Unknown Track"
    end

    local artist = get_meta_tag({"artist", "album_artist", "TPE1", "aART"})
    local album = get_meta_tag({"album", "TALB"})
    local composer = get_meta_tag({"composer", "TCOM"})
    local publisher = get_meta_tag({"publisher", "organization", "label", "TPUB"})
    local genre = get_meta_tag({"genre", "TCON"})
    local encoder = get_meta_tag({"encoder", "ENCODER", "encoded_by", "TOOL"})
    local replaygain = get_meta_tag({"replaygain_track_gain", "REPLAYGAIN_TRACK_GAIN"})

    local date = get_meta_tag({"date", "year", "originalyear", "TYER", "TDRC"})
    if date:len() > 4 then date = date:sub(1, 4) end

    local track_num = get_meta_tag({"track", "tracknumber", "TRCK"})
    local disc_num = get_meta_tag({"disc", "discnumber", "TPOS"})
    local pl_pos = mp.get_property_number("playlist-pos-1", 1)
    local pl_count = mp.get_property_number("playlist-count", 1)
    local duration_str = format_time(mp.get_property_number("duration", 0))

    -- Source Technical Specifications
    local raw_codec = mp.get_property("audio-codec-name") or ""
    local codec, is_lossless = analyze_codec(raw_codec)
    local container_name = format_container(raw_codec)
    local in_fmt = mp.get_property("audio-params/format") or ""
    local in_sr = mp.get_property_number("audio-params/samplerate", 0)
    local in_ch = mp.get_property("audio-params/channels") or ""
    local in_bitdepth = get_bit_depth(in_fmt)

    local bitrate = mp.get_property_number("audio-bitrate", 0)
    local bitrate_str = bitrate > 0 and string.format("%d kbps", math.floor(bitrate / 1000 + 0.5)) or ""
    local file_size_str = format_file_size()

    -- Hardware Audio Output Specs
    local out_sr = mp.get_property_number("audio-out-params/samplerate", 0)
    local ao_device = (mp.get_property("current-ao") or "AUDIO OUT"):upper()

    -- Signal Path Verification
    local signal_path_text, signal_path_color = get_signal_path_status(is_lossless, in_sr, out_sr)

    local ass = assdraw.ass_new()

    if has_albumart then
        -- =================================================================
        -- ALBUM ART MODE: Slim Capsule Strictly Anchored to Artwork Bounds
        -- =================================================================
        local target_w = vid_w - math.floor(32 * scale)
        local max_w = math.floor(opts.capsule_max_width * scale)
        local capsule_w = math.max(280, math.min(target_w, max_w))
        local capsule_x = vid_x + math.floor((vid_w - capsule_w) / 2)
        local capsule_y = vid_y + math.floor(opts.capsule_margin_top * scale)
        local capsule_h = math.floor(opts.capsule_height * scale)
        local pad = math.floor(opts.capsule_padding_x * scale)

        -- Rounded Translucent Capsule Backdrop
        ass:new_event()
        ass:append("{\\an7\\bord0\\shad0}")
        ass:pos(0, 0)
        ass:draw_start()
        ass:append(string.format("{\\c&H0A0A0A&\\alpha&H%s&}", opts.bg_opacity))
        ass:round_rect_cw(capsule_x, capsule_y, capsule_x + capsule_w, capsule_y + capsule_h, 8 * scale)
        ass:draw_stop()

        -- Subtle 1px Top Highlight
        ass:new_event()
        ass:append("{\\an7\\bord0\\shad0}")
        ass:pos(0, 0)
        ass:draw_start()
        ass:append("{\\c&H303030&\\alpha&H70&}")
        ass:rect_cw(capsule_x, capsule_y, capsule_x + capsule_w, capsule_y + 1)
        ass:draw_stop()

        -- Left Column - Line 1: Track Number, Duration & Song Title
        local track_badge_parts = {}
        if track_num ~= "" then
            table.insert(track_badge_parts, track_num)
        elseif pl_count > 1 then
            table.insert(track_badge_parts, string.format("%d/%d", pl_pos, pl_count))
        end
        if duration_str ~= "" then
            table.insert(track_badge_parts, duration_str)
        end
        local track_prefix = #track_badge_parts > 0 and string.format("[%s] ", table.concat(track_badge_parts, " • ")) or ""

        local title_size = math.floor(15 * scale)
        ass:new_event()
        ass:append(string.format("{\\an1\\fn%s\\fs%d\\bord1\\3c&H000000&\\shad1}", opts.font_face, title_size))
        ass:pos(capsule_x + pad, capsule_y + math.floor(24 * scale))
        ass:append(string.format("{\\b1\\c&H%s&}%s{\\c&H%s&}%s", opts.color_gold, escape_ass(track_prefix), opts.color_white, escape_ass(title)))

        -- Left Column - Line 2: Artist, Album, Year & ReplayGain (if present)
        local sub_line = {}
        if artist ~= "" then table.insert(sub_line, artist) end
        if album ~= "" then table.insert(sub_line, "— " .. album) end
        if date ~= "" then table.insert(sub_line, "(" .. date .. ")") end
        if replaygain ~= "" then table.insert(sub_line, string.format("{\\c&H%s&}[RG: %s]{\\c&H%s&}", opts.color_muted, escape_ass(replaygain), opts.color_silver)) end
        local sub_text = table.concat(sub_line, "  ")

        local sub_size = math.floor(11 * scale)
        ass:new_event()
        ass:append(string.format("{\\an1\\fn%s\\b0\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}", opts.font_face, sub_size, opts.color_silver))
        ass:pos(capsule_x + pad, capsule_y + math.floor(45 * scale))
        ass:append(escape_ass(sub_text))

        -- Right Column - Line 1: Codec [LOSSY/LOSSLESS] (Container if non-standard) | Bit Depth | Sample Rate | Bitrate
        local quality_tag = is_lossless and "LOSSLESS" or "LOSSY"
        local codec_color = is_lossless and opts.color_lossless or opts.color_lossy
        
        local codec_full = string.format("%s [%s]", codec:upper(), quality_tag)
        if container_name ~= "" and container_name ~= codec:upper() then
            codec_full = codec_full .. " (" .. container_name .. ")"
        end

        local tech_p1 = { codec_full }
        if in_bitdepth ~= "" then table.insert(tech_p1, in_bitdepth) end
        if in_sr > 0 then table.insert(tech_p1, format_sample_rate(in_sr)) end
        if bitrate_str ~= "" then table.insert(tech_p1, bitrate_str) end

        local tech_size = math.floor(11 * scale)
        ass:new_event()
        ass:append(string.format("{\\an3\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}", opts.font_face, tech_size, codec_color))
        ass:pos(capsule_x + capsule_w - pad, capsule_y + math.floor(24 * scale))
        ass:append(table.concat(tech_p1, "  |  "))

        -- Right Column - Line 2: Channels + Audio Device & Signal Path
        local ch_str = format_channels(in_ch)
        local tech_p2 = {}
        if ch_str ~= "" then table.insert(tech_p2, ch_str) end
        table.insert(tech_p2, string.format("[%s • %s]", ao_device, signal_path_text))

        local sig_size = math.floor(10 * scale)
        ass:new_event()
        ass:append(string.format("{\\an3\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}", opts.font_face, sig_size, signal_path_color))
        ass:pos(capsule_x + capsule_w - pad, capsule_y + math.floor(45 * scale))
        ass:append(table.concat(tech_p2, "  •  "))

    else
        -- =================================================================
        -- PURE AUDIO MODE: Permanent Studio Rack (Black Screen)
        -- =================================================================
        local center_y = screen_h * 0.40

        local index_components = {}
        if disc_num ~= "" then table.insert(index_components, "DISC " .. disc_num) end
        if track_num ~= "" then
            table.insert(index_components, "TRACK " .. track_num)
        else
            table.insert(index_components, string.format("TRACK %02d / %02d", pl_pos, pl_count))
        end
        if duration_str ~= "" then table.insert(index_components, duration_str) end
        if genre ~= "" then table.insert(index_components, genre:upper()) end
        local track_header = table.concat(index_components, "   •   ")

        -- Line 1: Track / Disc / Genre Index
        local header_size = math.floor(14 * scale)
        ass:new_event()
        ass:append(string.format("{\\an8\\fn%s\\fs%d\\b1\\c&H%s&\\bord0\\shad1}", opts.font_face, header_size, opts.color_gold))
        ass:pos(screen_w / 2, center_y - (95 * scale))
        ass:append(escape_ass(track_header))

        -- Line 2: Track Title
        local title_size = math.floor(34 * scale)
        ass:new_event()
        ass:append(string.format("{\\an8\\fn%s\\fs%d\\b1\\c&H%s&\\bord0\\shad2}", opts.font_face, title_size, opts.color_white))
        ass:pos(screen_w / 2, center_y - (65 * scale))
        ass:append(escape_ass(title))

        -- Line 3: Artist & Album
        local artist_album_parts = {}
        if artist ~= "" then
            table.insert(artist_album_parts, string.format("{\\b1\\c&H%s&}%s{\\b0}", opts.color_white, escape_ass(artist)))
        end
        if album ~= "" then
            table.insert(artist_album_parts, string.format("{\\c&H%s&}%s", opts.color_silver, escape_ass(album)))
        end
        if date ~= "" then
            table.insert(artist_album_parts, string.format("{\\c&H%s&}(%s)", opts.color_muted, escape_ass(date)))
        end

        local mid_size = math.floor(19 * scale)
        ass:new_event()
        ass:append(string.format("{\\an8\\fn%s\\fs%d\\c&H%s&\\bord0\\shad1}", opts.font_face, mid_size, opts.color_silver))
        ass:pos(screen_w / 2, center_y - (5 * scale))
        ass:append(table.concat(artist_album_parts, "   •   "))

        -- Line 4: Composer, Label, Encoder, ReplayGain
        local credits = {}
        if composer ~= "" then table.insert(credits, "Comp: " .. composer) end
        if publisher ~= "" then table.insert(credits, "Label: " .. publisher) end
        if encoder ~= "" then table.insert(credits, "Encoder: " .. encoder) end
        if replaygain ~= "" then table.insert(credits, "RG: " .. replaygain) end
        if #credits > 0 then
            local credit_size = math.floor(13 * scale)
            ass:new_event()
            ass:append(string.format("{\\an8\\fn%s\\fs%d\\c&H%s&\\bord0\\shad1}", opts.font_face, credit_size, opts.color_muted))
            ass:pos(screen_w / 2, center_y + (30 * scale))
            ass:append(escape_ass(table.concat(credits, "   |   ")))
        end

        -- Line 5: Source Specification Rack
        local quality_tag = is_lossless and "LOSSLESS" or "LOSSY"
        local codec_desc = string.format("%s [%s]", codec:upper(), quality_tag)
        if container_name ~= "" and container_name ~= codec:upper() then
            codec_desc = codec_desc .. " (" .. container_name .. ")"
        end

        local source_specs = { codec_desc }
        if in_bitdepth ~= "" then table.insert(source_specs, in_bitdepth) end
        if in_sr > 0 then table.insert(source_specs, format_sample_rate(in_sr)) end
        if in_ch ~= "" then table.insert(source_specs, format_channels(in_ch)) end
        if bitrate_str ~= "" then table.insert(source_specs, bitrate_str) end
        if file_size_str ~= "" then table.insert(source_specs, file_size_str) end

        local rack_size = math.floor(14 * scale)
        local codec_color = is_lossless and opts.color_lossless or opts.color_lossy
        ass:new_event()
        ass:append(string.format("{\\an8\\fn%s\\fs%d\\b1\\c&H%s&\\bord0\\shad1}", opts.font_face, rack_size, codec_color))
        ass:pos(screen_w / 2, center_y + (70 * scale))
        ass:append("[  " .. escape_ass(table.concat(source_specs, "   |   ")) .. "  ]")

        -- Line 6: Output & Signal Path Verification Rack
        local out_sr_str = out_sr > 0 and format_sample_rate(out_sr) or "DIRECT"
        local path_details = string.format("OUTPUT: %s (%s)   |   SIGNAL PATH: %s", ao_device, out_sr_str, signal_path_text)

        local path_size = math.floor(12 * scale)
        ass:new_event()
        ass:append(string.format("{\\an8\\fn%s\\fs%d\\b1\\c&H%s&\\bord0\\shad1}", opts.font_face, path_size, opts.color_cyan))
        ass:pos(screen_w / 2, center_y + (102 * scale))
        ass:append("{ " .. escape_ass(path_details) .. " }")
    end

    mp.set_osd_ass(screen_w, screen_h, ass.text)
end

-- Synchronize playback state across playlist changes
local function update_playback_state()
    is_audio_active = is_audio_stream()

    if is_audio_active then
        if opts.force_osc_always then
            mp.commandv("script-message", "osc-visibility", "always", "no-osd")
        end
        hud_visible = true
        render_dashboard()
    else
        clear_osd()
        mp.commandv("script-message", "osc-visibility", "auto", "no-osd")
    end
end

local function on_shutdown()
    clear_osd()
end

-- Keybind toggle handler (manual show/hide via 'i')
mp.register_script_message("toggle-audio-hud", function()
    hud_visible = not hud_visible
    render_dashboard()
end)

-- Property observers and event listeners (Strictly event-driven, zero polling overhead)
mp.register_event("file-loaded", update_playback_state)
mp.register_event("end-file", on_shutdown)
mp.observe_property("metadata", "native", render_dashboard)
mp.observe_property("audio-params", "native", render_dashboard)
mp.observe_property("audio-out-params", "native", render_dashboard)
mp.observe_property("af", "native", render_dashboard)
mp.observe_property("current-ao", "native", render_dashboard)
mp.observe_property("audio-exclusive", "native", render_dashboard)
mp.observe_property("audio-bitrate", "number", render_dashboard)
mp.observe_property("osd-dimensions", "native", render_dashboard)