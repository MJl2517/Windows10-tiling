local selected = ya.sync(function()
  local paths = {}
  for _, file in pairs(cx.active.selected) do paths[#paths + 1] = tostring(file.path) end
  if #paths == 0 and cx.active.current.hovered then paths[1] = tostring(cx.active.current.hovered.path) end
  return paths
end)

return { entry = function()
  local paths = selected()
  if #paths == 0 then return end
  local child, err = Command("@PROFILE_F@/AppData/Roaming/yazi/config/bin/yazi-drag.exe")
    :arg("--stdin"):stdin(Command.PIPED):spawn()
  if child then
    local ok
    ok, err = child:write_all(ya.json_encode(paths) .. "\n")
    if ok then ok, err = child:flush() end
    if ok then
      local status
      status, err = child:wait()
      if status and status.success then return end
    end
  end
  ya.notify { title = "Перетаскивание файлов", content = tostring(err or "Не удалось открыть окно перетаскивания"), level = "error", timeout = 6 }
end }
