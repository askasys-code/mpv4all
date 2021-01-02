-- Loading lua scripts in mpv:
-- 1: Scripts passed to the --script option
-- --script /path/to/script
-- 2: scripts subdirectory of the mpv configuration directory
-- ~/.config/mpv/scripts/
-- 
local interp_changed = true

function toggle_interp()
    if interp_changed then
        mp.commandv('vo-cmdline', 'interpolation=yes:tscale=oversample')
    else
        mp.commandv('vo-cmdline', 'interpolation=yes:tscale=catmull_rom')
    end
    interp_changed = not interp_changed
end

-- Bind function to "T"
mp.add_key_binding("T", "toggle_interp", toggle_interp)

-- Unbound function
-- Bind in 'input.conf' via script-message
-- I.E.: KEY script-message toggle_interp
-- With arguments:
--     : KEY script-message <Function> <%1> <%2> ... 
mp.add_key_binding(nil, "toggle_interp", toggle_interp)

-- Note: If supported by script, can be activated like this:
--     : KEY script_binding <scriptfile>