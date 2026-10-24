--- @since 26.9.1
--- @sync entry

local M = { menu = nil, last_click = nil, hovered = nil }
local items = {
  { "open", "Открыть", "Enter" },
  { "choose", "Открыть с помощью…", "Shift+Enter" },
  { "cut", "Вырезать", "X" },
  { "copy", "Копировать", "C" },
  { "paste", "Вставить сюда", "V" },
  { "select", "Выбрать / снять выбор", "Space" },
  { "rename", "Переименовать", "R" },
  { "file", "Новый файл", "N" },
  { "folder", "Новая папка", "Shift+N" },
  { "archive", "Упаковать / распаковать", "Z" },
  { "hidden", "Скрытые файлы: показать / скрыть", "H" },
  { "back", "В родительскую папку", "Backspace" },
}

function M.dismiss()
  M.menu = nil
  M.hovered = nil
  -- File rows also need motion reporting when no popup is open.
  rt.tty:queue("Print", { "\27[?1003h\27[?1006h" })
  rt.tty:flush()
  ui.render()
end

function M.run(action)
  M.dismiss()
  if action == "open" then ya.emit("plugin", { "smart-enter" })
  elseif action == "choose" then
    ya.emit("shell", { 'open-with.exe %s', orphan = true })
  elseif action == "cut" then ya.emit("yank", { cut = true })
  elseif action == "copy" then ya.emit("yank", {})
  elseif action == "paste" then ya.emit("paste", {})
  elseif action == "select" then ya.emit("toggle", {})
  elseif action == "rename" then ya.emit("rename", { cursor = "before_ext" })
  elseif action == "file" then ya.emit("create", {})
  elseif action == "folder" then ya.emit("create", { dir = true })
  elseif action == "archive" then ya.emit("plugin", { "smart-archive" })
  elseif action == "hidden" then ya.emit("hidden", { "toggle" })
  elseif action == "back" then ya.emit("leave", {})
  elseif action == "trash" then ya.emit("remove", {})
  elseif action == "delete" then ya.emit("remove", { permanently = true })
  end
end

function M.show(x, y, options)
  M.hovered = nil
  M.menu = options or {}
  M.menu.x, M.menu.y, M.menu.selected = x or 4, y or 3, 1
  -- Yazi enables 1002, which reports motion only while a button is held.
  rt.tty:queue("Print", { "\27[?1003h\27[?1006h" })
  rt.tty:flush()
  ui.render()
end

function M.show_drives(drives)
  local list = {}
  for i, drive in ipairs(drives) do
    list[#list + 1] = { "drive", drive.label, i <= 9 and tostring(i) or "", drive.path }
  end
  if #list == 0 then return end
  M.show(nil, nil, { kind = "drives", items = list, centered = true, title = " Диски · ↑ ↓ Enter · 1–9 · Esc " })
end

local function choices() return M.menu and M.menu.items or items end

function M.activate(index)
  local item = choices()[index]
  if not item then return end
  if item[1] == "drive" then M.dismiss(); ya.emit("cd", { item[4] })
  else M.run(item[1]) end
end

function M.step(delta)
  M.menu.selected = (M.menu.selected - 1 + delta) % #choices() + 1
  ui.render()
end

function M.setup()
  local redraw, click, scroll, move = Root.redraw, Root.click, Root.scroll, Root.move
  local entity_style = Entity.style
  function Entity:style()
    local style = entity_style(self)
    if not self._file.is_hovered and M.hovered == tostring(self._file.url) then
      return style:patch(ui.Style():fg("#e0def4"):bg("#403d52"))
    end
    return style
  end
  function Root:redraw()
    local elements = redraw(self)
    local menu, bounds = M.menu, self._area
    if not menu or tostring(cx.layer) ~= "mgr" then return elements end
    local list = choices()
    local w, h = math.min(54, bounds.w), math.min(#list + 2, bounds.h)
    if menu.centered then
      menu.x = bounds.x + math.floor((bounds.w - w) / 2)
      menu.y = bounds.y + math.floor((bounds.h - h) / 2)
    end
    local x = math.max(bounds.x, math.min(menu.x, bounds.x + bounds.w - w))
    local y = math.max(bounds.y, math.min(menu.y, bounds.y + bounds.h - h))
    menu.area = ui.Rect { x = x, y = y, w = w, h = h }
    elements[#elements + 1] = ui.Clear(menu.area)
    elements[#elements + 1] = ui.Text(""):area(menu.area):bg("#26233a")
    elements[#elements + 1] = ui.Border(ui.Edge.ALL):area(menu.area):style(ui.Style():fg("#c4a7e7")):title(menu.title or " Действия · Esc: закрыть ")
    for i = 1, math.min(#list, h - 2) do
      local item, active = list[i], i == menu.selected
      local label = item[2] .. (item[3] ~= "" and "  [" .. item[3] .. "]" or "")
      label = " " .. ui.truncate(label, { max = w - 4 })
      elements[#elements + 1] = ui.Text(label)
        :area(ui.Rect { x = x + 1, y = y + i, w = w - 2, h = 1 })
        :fg(active and "#191724" or "#e0def4")
        :bg(active and "#c4a7e7" or "#26233a")
    end
    return elements
  end
  local function row_at(event)
    local a = M.menu and M.menu.area
    if not a or event.x <= a.x or event.x >= a.x + a.w - 1 then return end
    local row = event.y - a.y
    if row >= 1 and row <= math.min(#choices(), a.h - 2) then return row end
  end
  function Root:click(event, up)
    if not M.menu then return click(self, event, up) end
    if up then return end
    local row = row_at(event)
    if row and event.is_left then M.activate(row)
    else M.dismiss() end
  end
  function Root:scroll(event, step)
    if M.menu then M.step(step) else return scroll(self, event, step) end
  end
  function Root:move(event)
    if tostring(cx.layer) ~= "mgr" then return end
    if not M.menu then
      local child = ya.child_at(ui.Rect { x = event.x, y = event.y }, self:reflow())
      local folder = child and child._folder
      local file = folder and folder.window[event.y - child._area.y + 1]
      local path = file and tostring(file.url) or nil
      if path ~= M.hovered then M.hovered = path; ui.render() end
      return move(self, event)
    end
    local row = row_at(event)
    if row and row ~= M.menu.selected then M.menu.selected = row; ui.render() end
  end
  function Entity:click(event, up)
    if up then return end
    ya.emit("reveal", { self._file.url })
    if event.is_right then M.show(event.x, event.y)
    elseif event.is_middle then M.run("select")
    elseif event.is_left then
      local path, now = tostring(self._file.url), ya.time()
      local last = M.last_click
      M.last_click = { path = path, time = now }
      if last and last.path == path and now - last.time < 0.4 then
        M.last_click = nil
        M.run("open")
      end
    end
  end
  local current_click = Current.click
  function Current:click(event, up)
    local row = event.y - self._area.y + 1
    if not up and event.is_right and not self._folder.window[row] then
      M.show(event.x, event.y)
    else return current_click(self, event, up) end
  end
  -- Process this after Yazi has initialized its normal terminal modes.
  ya.emit("plugin", { "mouse-menu", "motion" })
end

function M.entry(_, job)
  local action = job.args[1] or "menu"
  if action == "menu" then M.show()
  elseif action == "motion" then
    rt.tty:queue("Print", { "\27[?1003h\27[?1006h" }); rt.tty:flush()
  elseif action:match("^digit%-") then
    local number = tonumber(action:match("%d+$"))
    if M.menu and M.menu.kind == "drives" then M.activate(number)
    elseif not M.menu then ya.emit("tab_switch", { number - 1 }) end
  elseif action == "up" or action == "down" then
    if M.menu then M.step(action == "up" and -1 or 1)
    else ya.emit("arrow", { action == "up" and "prev" or "next" }) end
  elseif action == "enter" then
    if M.menu then M.activate(M.menu.selected) else M.run("open") end
  elseif action == "escape" then
    if M.menu then M.dismiss() else ya.emit("escape", { all = true }) end
  elseif action == "quit" and M.menu then M.dismiss()
  elseif action == "quit" then ya.emit("quit", {})
  else M.run(action) end
end

return M
