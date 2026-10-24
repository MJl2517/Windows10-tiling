--- @since 26.9.1

local show = ya.sync(function(_, drives)
  require("mouse-menu").show_drives(drives)
end)

return {
  entry = function()
    local command = '[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); @([IO.DriveInfo]::GetDrives() | Where-Object IsReady | ForEach-Object { [pscustomobject]@{path=$_.Name;label=($_.Name + "  " + $_.VolumeLabel)} }) | ConvertTo-Json -Compress'
    local output, err = Command("powershell.exe")
      :arg({ "-NoProfile", "-NonInteractive", "-Command", command }):output()
    if not output or not output.status.success then
      ya.notify { title = "Диски", content = tostring(err or (output and output.stderr)), level = "error", timeout = 5 }
      return
    end
    local drives = ya.json_decode(output.stdout)
    if not drives then return end
    if drives.path then drives = { drives } end
    show(drives)
  end,
}
