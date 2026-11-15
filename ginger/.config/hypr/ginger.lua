-- Ginger dev boxes. bindings.lua loads this with require("hypr.ginger")
-- (install.sh adds that line). Super+Alt+R/P/T/D were free in Omarchy's defaults.
o.bind("SUPER + ALT + R", "Terminal on rz", "omarchy-launch-terminal rz")
o.bind("SUPER + ALT + P", "Terminal on pi", "omarchy-launch-terminal rpi")
o.bind("SUPER + ALT + T", "T3 on rz", "t3o rz")
o.bind("SUPER + ALT + D", "Ginger menu", { menu = "ginger" })
