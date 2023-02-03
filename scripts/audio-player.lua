alwaysShownText = {
	text = nil,
	change = (function(self, _text)
		self.text = _text
	end),
	show = (function(self)
		if self.text ~= nil then
			mp.command("show-text " .. self.text .. " 1000")
		end
	end),
	start_showing = (function(self)
		self:show()
		self.timer = mp.add_periodic_timer(0.9, (function () self:show() end))
	end),
	timer = nil
}

print(mp.get_property_osd("video"))

function osc_always()
	print(mp.get_property_osd("video"))
	if mp.get_property_osd("video") == "no" then
	    mp.commandv("script-message", "osc-visibility", "always", "no-osd")
	    mp.commandv("set", "options/osd-bar", "no")
	end
end


function show_metadata()
	print(mp.get_property_osd("video"))
	if mp.get_property_osd("video") == "no" then
	    alwaysShownText:change('${filtered-metadata}')
	end
end

mp.register_event("file-loaded", osc_always)
mp.register_event("file-loaded", show_metadata)
alwaysShownText:start_showing()