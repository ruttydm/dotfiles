-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- Docked layout (physical left → right):
--   HDMI Philips 248E9Q  |  USB-C Dell P2720DC  |  laptop
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

-- HDMI left (Philips 1920x1080).
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "0x0", scale = 1 })

-- USB-C Dell middle (2560x1440), or left if HDMI is unplugged.
if hdmi then
  hl.monitor({ output = "DP-2", mode = "preferred", position = "1920x0", scale = 1 })
else
  hl.monitor({ output = "DP-2", mode = "preferred", position = "0x0", scale = 1 })
end

-- Laptop right. Logical width at 1.25 is 1536.
local laptop_x = 0
if hdmi and dell then
  laptop_x = 1920 + 2560
elseif hdmi then
  laptop_x = 1920
elseif dell then
  laptop_x = 2560
end
hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = laptop_x .. "x0",
  scale = 1.25,
})
