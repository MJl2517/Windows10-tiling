--- @since 26.9.1
--- @sync entry

local extensions = {
  zip=true, ["7z"]=true, rar=true, tar=true, gz=true, tgz=true,
  bz2=true, tbz=true, tbz2=true, xz=true, txz=true, zst=true,
  tzst=true, lzma=true, cab=true, iso=true, arj=true, xar=true, cpio=true,
}

local function is_archive(file)
  return not file.cha.is_dir and extensions[(file.name:match("%.([^%.]+)$") or ""):lower()] == true
end

local function entry()
  local tab = cx.active
  local count, archives = 0, true
  for _, file in pairs(tab.selected) do
    count = count + 1
    archives = archives and is_archive(file)
  end
  if count == 0 then
    if not tab.current.hovered then return end
    archives = is_archive(tab.current.hovered)
  end
  if archives then
    ya.emit("shell", { "ya pub extract --list %s" })
  else
    ya.emit("plugin", { "compress", args = "zip" })
  end
end

return { entry = entry }
