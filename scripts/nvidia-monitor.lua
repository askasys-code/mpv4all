-- =========================================================================
-- MPV NVIDIA Hardware Monitor & RivaTuner-Style Categorized Suite
-- Telemetry: GPU, MEMORY & DISPLAY (with Native HDR & RTX True HDR Detection)
-- =========================================================================

local mp = require("mp")
local utils = require("mp.utils")
local assdraw = require("mp.assdraw")

local is_enabled = false
local is_fetching = false
local poll_timer = nil
local vrr_os_enabled = false

-- Visual Configuration & Styling (ASS Colors in &HBBGGRR& format)
local cfg = {
    ui_scale        = 1.35,        -- User size multiplier (1.0 = normal, 1.35 = 4K recommended, 1.6 = large for TV)
    poll_interval   = 1.0,         -- Telemetry update rate in seconds
    font_face       = "Segoe UI",
    color_green     = "00E676",    -- NVIDIA Green (Headers, Titles & RTX True HDR)
    color_cyan      = "00E5FF",    -- RivaTuner Cyan (Clocks, FPS & Native HDR)
    color_yellow    = "00C8FF",    -- Amber Warning (Power & Latencies)
    color_red       = "3B3BFF",    -- Critical Red
    color_white     = "FFFFFF",
    color_gray      = "9E9E9E",
    bg_alpha        = "35",        -- Box transparency (Hex: 00-FF, 35 = ~80% dark)
}

-- Telemetry State
local stats = {
    gpu_name   = "Detecting...",
    temp       = "N/A",
    fan        = "N/A",
    pwr_draw   = "N/A",
    pwr_lim    = "N/A",
    load       = "N/A",
    nvdec_load = "0",
    vram_use   = "N/A",
    vram_tot   = "N/A",
    clk_core   = "N/A",
    clk_mem    = "N/A"
}

-- Locate nvidia-smi executable safely using zero-overhead file inspection
local function get_smi_path()
    local default_paths = {
        "C:\\Windows\\System32\\nvidia-smi.exe",
        "C:\\Program Files\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe"
    }
    for _, path in ipairs(default_paths) do
        local info = utils.file_info(path)
        if info and info.is_file then
            return path
        end
    end
    return "nvidia-smi"
end

local smi_binary = get_smi_path()
local overlay = mp.create_osd_overlay("ass-events")

-- Check Windows OS-level Variable Refresh Rate registry toggle asynchronously
local function check_windows_vrr()
    mp.command_native_async({
        name = "subprocess",
        args = { "reg", "query", "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences", "/v", "DirectXUserGlobalSettings" },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = false
    }, function(success, res)
        if success and res and res.stdout then
            vrr_os_enabled = res.stdout:find("VRROptimizeEnable=1") ~= nil
        end
    end)
end

-- Resolve active dynamic range state (SDR, Native HDR or NVIDIA RTX True HDR)
local function get_dynamic_range_status()
    local has_video = mp.get_property_native("current-tracks/video")
    if not has_video then
        return "N/A", cfg.color_gray
    end

    -- 1. Check if NVIDIA RTX Video True HDR is active in video filters
    local vf_str = mp.get_property("vf") or ""
    if vf_str:find("@truehdr") or vf_str:find("nvidia%-true%-hdr") then
        return "RTX True HDR (Tensor AI)", cfg.color_green
    end

    -- 2. Check native HDR color transfer characteristics
    local gamma = mp.get_property("video-params/gamma") or ""
    local sig_peak = mp.get_property_number("video-params/sig-peak", 1.0)
    local colormatrix = mp.get_property("video-params/colormatrix") or ""

    if gamma == "pq" then
        return "Native HDR10 (PQ)", cfg.color_cyan
    elseif gamma == "hlg" then
        return "Native HDR (HLG)", cfg.color_cyan
    elseif sig_peak > 1.0 or colormatrix:find("bt.2020") then
        return "Native HDR (BT.2020)", cfg.color_cyan
    end

    return "SDR (Standard)", cfg.color_gray
end

-- Resolve active upscaler engine
local function get_active_upscaler()
    local vf_str = mp.get_property("vf") or ""
    if vf_str:find("@vsr") or vf_str:find("d3d11vpp") then
        return "RTX VSR (Tensor AI)", cfg.color_green
    end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    if #shaders > 0 then
        for _, s in ipairs(shaders) do
            if s:find("NVScaler") then return "NVIDIA NIS", cfg.color_cyan end
            if s:find("FSR") then return "AMD FSR 1.0", cfg.color_cyan end
            if s:find("SGSR") then return "Qualcomm SGSR", cfg.color_cyan end
            if s:find("CAS") then return "AMD CAS", cfg.color_cyan end
        end
        return "Custom GLSL", cfg.color_cyan
    end
    return "Native (Lanczos)", cfg.color_gray
end

-- Extract real-time MPV engine metrics (Native Video FPS, Display Hz, Latency & Drops)
local function get_mpv_perf_stats()
    local is_paused = mp.get_property_bool("pause", false)

    -- 1. Native Video Framerate (Container / Stream FPS)
    local v_fps = mp.get_property_number("container-fps", 0)
    if v_fps <= 0 then
        v_fps = mp.get_property_number("estimated-vf-fps", 0)
    end

    -- 2. Physical Display Refresh Rate
    local d_fps = mp.get_property_number("display-fps", 0)
    if d_fps <= 0 then
        d_fps = mp.get_property_number("estimated-display-fps", 0)
    end

    -- 3. GPU Render Latency via vo-passes (nanoseconds -> milliseconds)
    local render_ms = 0
    local vo_p = mp.get_property_native("vo-passes")
    if vo_p and vo_p["fresh"] then
        local total_ns = 0
        for _, pass in ipairs(vo_p["fresh"]) do
            total_ns = total_ns + (pass["last"] or pass["avg"] or 0)
        end
        if total_ns > 0 then
            render_ms = total_ns / 1000000
        end
    end

    -- 4. Target Frametime interval (1000 / Display Hz)
    local frametime_ms = (d_fps > 0) and (1000 / d_fps) or 0

    -- 5. Dropped and Mistimed frames
    local drops = mp.get_property_number("drop-frame-count", 0)
    local mistimed = mp.get_property_number("mistimed-frame-count", 0)

    -- 6. G-Sync / VRR status detection
    local vsync_mode = mp.get_property("video-sync") or "audio"
    local interpolation = mp.get_property_bool("interpolation", false)
    local vrr_text = "OFF"
    local vrr_color = cfg.color_gray

    if vrr_os_enabled then
        if vsync_mode == "audio" and not interpolation then
            vrr_text = "ACTIVE (VRR Mode)"
            vrr_color = cfg.color_green
        else
            vrr_text = "STANDBY (VSync Lock)"
            vrr_color = cfg.color_yellow
        end
    else
        vrr_text = "DISABLED (Windows)"
        vrr_color = cfg.color_gray
    end

    local video_fps_str = "N/A"
    if v_fps > 0 then
        if is_paused then
            video_fps_str = string.format("%.3f FPS (Paused)", v_fps)
        else
            video_fps_str = string.format("%.3f FPS", v_fps)
        end
    end

    local display_hz_str = "N/A"
    if d_fps > 0 then
        display_hz_str = string.format("%.2f Hz (%.1f ms)", d_fps, frametime_ms)
    end

    local lat_str = (render_ms > 0) and string.format("%.2f ms", render_ms) or "0.00 ms"
    local drops_str = string.format("%d (Mistimed: %d)", drops, mistimed)
    local drops_color = (drops == 0 and mistimed == 0) and cfg.color_green or cfg.color_yellow
    if drops > 5 then drops_color = cfg.color_red end

    return video_fps_str, display_hz_str, lat_str, vrr_text, vrr_color, drops_str, drops_color
end

-- Parse raw CSV output from nvidia-smi (includes GPU Name, Clocks & Video Decoder load)
local function parse_smi_csv(csv_line)
    if not csv_line or csv_line == "" then return end
    local fields = {}
    for val in csv_line:gmatch("([^,]+)") do
        table.insert(fields, val:match("^%s*(.-)%s*$"))
    end

    if #fields >= 11 then
        stats.gpu_name   = fields[1]
        stats.temp       = fields[2]
        stats.fan        = fields[3]
        stats.pwr_draw   = fields[4]
        stats.pwr_lim    = fields[5]
        stats.load       = fields[6]

        -- Clean and validate NVDEC decoder utilization
        local nvdec_raw  = fields[7]
        local nvdec_clean = nvdec_raw:match("(%d+)")
        stats.nvdec_load = nvdec_clean or "0"

        stats.clk_core   = fields[10]
        stats.clk_mem    = fields[11]

        -- Convert VRAM from MiB to rounded GB
        local mem_u = tonumber(fields[8])
        local mem_t = tonumber(fields[9])
        stats.vram_use = mem_u and string.format("%.2f", mem_u / 1024) or "N/A"
        stats.vram_tot = mem_t and string.format("%.0f", mem_t / 1024) or "N/A"
    end
end

-- Render ASS HUD Overlay with Dynamic Range and Unified Vector Diamond Headers
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

    -- Temperature dynamic coloring
    local temp_num = tonumber(stats.temp) or 0
    local temp_color = cfg.color_green
    if temp_num >= 82 then
        temp_color = cfg.color_red
    elseif temp_num >= 72 then
        temp_color = cfg.color_yellow
    end

    -- Fan string formatting
    local fan_str = stats.fan ~= "N/A" and (stats.fan .. " %") or "N/A"
    if stats.fan == "0" then
        fan_str = "0 % (Fan Stop)"
    end

    -- Retrieve real-time MPV engine metrics
    local v_fps_val, d_hz_val, lat_val, vrr_val, vrr_col, drops_val, drops_col = get_mpv_perf_stats()
    local upscaler_name, upscaler_col = get_active_upscaler()
    local hdr_name, hdr_col = get_dynamic_range_status()

    -- =========================================================================
    -- Sectioned Telemetry Data Structure
    -- =========================================================================
    local sections = {
        {
            title = "GPU",
            title_color = cfg.color_green,
            items = {
                { "Core Clock", stats.clk_core .. " MHz", cfg.color_cyan },
                { "GPU Load", stats.load .. " % (NVDEC: " .. stats.nvdec_load .. " %)", cfg.color_white },
                { "Temperature", stats.temp .. " °C", temp_color },
                { "Power Draw", stats.pwr_draw .. " W / " .. stats.pwr_lim .. " W", cfg.color_yellow },
                { "Fan Speed", fan_str, cfg.color_white }
            }
        },
        {
            title = "MEMORY",
            title_color = cfg.color_green,
            items = {
                { "VRAM Clock", stats.clk_mem .. " MHz", cfg.color_cyan },
                { "VRAM Usage", stats.vram_use .. " GB / " .. stats.vram_tot .. " GB", cfg.color_white }
            }
        },
        {
            title = "DISPLAY",
            title_color = cfg.color_green,
            items = {
                { "Video FPS", v_fps_val, cfg.color_cyan },
                { "Display Rate", d_hz_val, cfg.color_white },
                { "Dynamic Range", hdr_name, hdr_col },
                { "Upscaler", upscaler_name, upscaler_col },
                { "G-Sync / VRR", vrr_val, vrr_col },
                { "Render Time", lat_val, cfg.color_yellow },
                { "Dropped Frames", drops_val, drops_col }
            }
        }
    }

    -- Font Sizes & Spacing Geometry
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

    -- Dynamic Height Calculation (Auto-fits with new Dynamic Range row)
    local total_rows = 0
    for _, sec in ipairs(sections) do
        total_rows = total_rows + #sec.items
    end

    local header_h = title_size + subtitle_size + math.floor(8 * scale)
    local sections_h = (#sections * section_step) + ((#sections - 1) * section_gap) + (total_rows * row_step)
    local box_h = top_pad + header_h + header_gap + sections_h + bottom_pad
    local box_w = math.floor(400 * scale)

    local margin_x = math.floor(24 * scale)
    local margin_y = math.floor(24 * scale)
    local x2 = d.w - margin_x
    local x1 = x2 - box_w
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

    -- 3. Header Block: Title & Detected GPU Model Subtitle
    local cur_y = y1 + top_pad
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}NVIDIA HARDWARE MONITOR", 
        x1 + pad_x, cur_y, cfg.font_face, title_size, cfg.color_green))

    cur_y = cur_y + title_size + math.floor(4 * scale)
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        x1 + pad_x, cur_y, cfg.font_face, subtitle_size, cfg.color_white, stats.gpu_name))

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
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", sec.title_color or cfg.color_green))
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
            text_x, cur_y, cfg.font_face, section_size, sec.title_color or cfg.color_green, sec.title))

        cur_y = cur_y + section_step

        -- Section Item Rows (Indented for clean hierarchy)
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

        -- Spacing between sections (except after the last one)
        if s_idx < #sections then
            cur_y = cur_y + section_gap
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- Asynchronous polling routine (Non-blocking)
local function poll_nvidia_smi()
    if not is_enabled or is_fetching then return end
    is_fetching = true

    mp.command_native_async({
        name = "subprocess",
        args = {
            smi_binary,
            "--query-gpu=name,temperature.gpu,fan.speed,power.draw,power.limit,utilization.gpu,utilization.decoder,memory.used,memory.total,clocks.gr,clocks.mem",
            "--format=csv,noheader,nounits"
        },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = false
    }, function(success, res, err)
        is_fetching = false
        if success and res and res.status == 0 and res.stdout then
            parse_smi_csv(res.stdout)
            draw_hud()
        end
    end)
end

-- Explicit state setter with inter-script tracking
local function set_enabled(state)
    is_enabled = state
    mp.set_property_native("user-data/gpu-monitor-active", is_enabled)
    if is_enabled then
        check_windows_vrr()
        draw_hud()
        poll_nvidia_smi()
        if not poll_timer then
            poll_timer = mp.add_periodic_timer(cfg.poll_interval, poll_nvidia_smi)
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
local function toggle_overlay()
    set_enabled(not is_enabled)
end

-- Keybindings and script messages
mp.add_forced_key_binding("g", "toggle-gpu-monitor-forced", toggle_overlay)
mp.register_script_message("toggle-gpu-monitor", toggle_overlay)

mp.register_script_message("set-gpu-monitor", function(val)
    if val == "yes" or val == "true" or val == "on" or val == "1" then
        set_enabled(true)
    elseif val == "no" or val == "false" or val == "off" or val == "0" then
        set_enabled(false)
    else
        toggle_overlay()
    end
end)

mp.observe_property("osd-dimensions", "native", draw_hud)
mp.observe_property("pause", "bool", draw_hud)
mp.observe_property("vf", "native", draw_hud)
mp.observe_property("glsl-shaders", "native", draw_hud)