-- Cua input plugin from Omarchy's package (cua-hyprland-plugin). Loaded only when the load guard
-- confirms the installed Hyprland and ABI libraries are the ones the package was built against.
local home = os.getenv("HOME")
local plugin = "/usr/lib/cua/hyprland/cua-hyprland-plugin.so"
-- Hyprland reaps children; read an explicit result instead of os.execute status.
local check = io.popen(home .. "/.local/bin/cua-hyprland-check 2>/dev/null && echo OK")
local valid = check and check:read("*a"):match("OK")
if check then check:close() end
if valid then
  hl.plugin.load(plugin)
  hl.config({ plugin = { cua = { enabled = true } } })
end
