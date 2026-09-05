-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- Docked layout (physical left → right):
--   HDMI Philips 248E9Q  |  USB-C Dell P2720DC (primary)  |  laptop
-- Coordinate origin is the Dell so it is the XWayland/GTK primary.
-- Externals stay at scale 1; the 14" 1920x1200 panel stays at 1.25.

hl.env("GDK_SCALE", "1")

local function connected(name)
  local monitors = hl.get_monitors()
  for i = 1, #monitors do
    if monitors[i].name == name then
      return true
    end
  end
  return false
end

local hdmi = connected("HDMI-A-1")
local dell = connected("DP-2")

if dell then
  -- Dell is the origin (primary). HDMI sits to its left.
  hl.monitor({ output = "DP-2", mode = "preferred", position = "0x0", scale = 1 })
  hl.monitor({
    output = "HDMI-A-1",
    mode = "preferred",
    position = hdmi and "-1920x0" or "0x0",
    scale = 1,
  })
else
  hl.monitor({ output = "DP-2", mode = "preferred", position = "0x0", scale = 1 })
  hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "0x0", scale = 1 })
end

local laptop_x = 0
if dell then
  laptop_x = 2560
elseif hdmi then
  laptop_x = 1920
end
hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = laptop_x .. "x0",
  scale = 1.25,
})

if dell then
  hl.config({ cursor = { default_monitor = "DP-2" } })
  hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true })
else
  hl.config({ cursor = { default_monitor = "eDP-1" } })
end
