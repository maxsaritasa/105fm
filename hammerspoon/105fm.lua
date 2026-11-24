-- ===== 105fm =====
-- https://github.com/maxsaritasa/105fm - see README.md for setup.
-- Loaded from ~/.hammerspoon/init.lua with: require("105fm")
--
-- Both ⇧ keys (Karabiner -> F18)            improve clarity (also ⇧⇧ then i)
-- Both ⇧ keys (Karabiner -> F18), then f    fix spelling/grammar only
-- Both ⇧ keys, then e / r / s              improve + translate to English / Russian / Spanish
-- Both ⇧ keys, then w                      fix text typed in the wrong keyboard layout (RU<->EN, local, no API)
-- Esc or ⇧⇧ again within 1s cancels
-- ⌃⌥F / ⌃⌥I still work as direct shortcuts
--
-- Backends: every action runs on the local Apple Foundation Model (`fm respond`, macOS 27).
-- Anthropic Haiku is only the fallback when fm fails or times out.
-- To send Russian back to Haiku: FM_CYRILLIC = false and remove russian from FM_ACTIONS.

local MODEL = "claude-haiku-5-5"
-- Optional: only needed for the Haiku fallback. Stored in the macOS Keychain (see README).
local API_KEY = (hs.execute('security find-generic-password -a "$USER" -s anthropic_api_key -w 2>/dev/null') or ""):gsub("%s+$", "")

-- Local model (Apple Foundation Models CLI)
local USE_FM = true                 -- false = everything goes to Haiku, as before
local FM_PATH = "/usr/bin/fm"
local FM_TIMEOUT = 20               -- seconds before giving up on fm
local FM_FALLBACK_TO_HAIKU = true   -- if fm fails or times out, retry the same request on Haiku
local FM_ACTIONS = { fix = true, improve = true, english = true, spanish = true, russian = true }
local FM_CYRILLIC = true            -- false = any text containing Cyrillic goes to Haiku

-- Physical key codes (ANSI positions). Binding by code instead of letter makes every
-- hotkey and the simulated ⌘C / ⌘V work the same whatever input source is active (EN or RU).
local KEY = { s = 1, c = 8, v = 9, w = 13, e = 14, r = 15, f = 3, i = 34, escape = 53, f18 = 79 }

local PROMPTS = {
  fix = [[
You are a copy editor. Correct the text below.
Rules:
1. Fix spelling, grammar and punctuation only. Do not rephrase or shorten.
2. Fix pronoun case errors (e.g. "Me and X did" -> "X and I did").
3. Never use em dashes (—) or en dashes (–) anywhere in your output, including in text you write yourself. Always use a plain hyphen (-) instead, and replace any long dashes in the original.
4. Keep the tone, formatting and line breaks exactly as they are.
5. Return only the corrected text. No preamble, no explanation, no quotes around it.]],

  improve = [[
You are a copy editor. Improve the text below.
Rules:
1. Fix spelling, grammar and punctuation.
2. Lightly improve clarity and flow. Keep the meaning, tone and roughly the same length.
3. Use plain, direct business language. No corporate phrasing.
4. Never use em dashes (—) or en dashes (–) anywhere in your output, including in text you write yourself. Always use a plain hyphen (-) instead, and replace any long dashes in the original.
5. Keep formatting and line breaks as they are.
6. Return only the improved text. No preamble, no explanation, no quotes around it.]],
}

local TRANSLATE_TEMPLATE = [[
You are a professional translator and copy editor. Translate the text below into %s.
Rules:
1. Detect the source language automatically. If the text is already in %s, do not translate - just lightly improve it.
2. Translate accurately and naturally, as a native speaker would write it. Do not translate word for word.
3. Lightly improve clarity and flow. Keep the meaning, tone and roughly the same length.
4. Use plain, direct business language. No corporate phrasing.
5. Never use em dashes (—) or en dashes (–) anywhere in your output, including in text you write yourself. Always use a plain hyphen (-) instead, and replace any long dashes in the original.
6. Keep formatting and line breaks as they are. Keep names, product names and technical terms as they are.
7. Return only the translated text. No preamble, no explanation, no quotes around it.]]

PROMPTS.english = string.format(TRANSLATE_TEMPLATE, "English", "English")
PROMPTS.russian = string.format(TRANSLATE_TEMPLATE, "Russian", "Russian")
PROMPTS.spanish = [[
You are a professional translator and copy editor based in Buenos Aires. Translate the text below into Argentine (Rioplatense) Spanish.
Rules:
1. Detect the source language automatically. If the text is already in Spanish, do not translate - rewrite it so it reads as natural Argentine Spanish.
2. Write the way an educated professional in Buenos Aires writes a business email or Slack message. It must sound native, not like a translation.
3. Use voseo consistently: "vos" with its verb forms (tenés, podés, querés, sabés, hacé, mandá, fijate), never "tú" or "tienes". Use "ustedes" for plural, never "vosotros".
4. Prefer Argentine vocabulary where it differs: "celular" not "móvil", "computadora" not "ordenador", "acá/allá" over "aquí/allí", "mail" or "correo" for email, "charlar", "laburo" only if the source is informal, "dale" / "bárbaro" / "genial" where the source is casual.
5. Match the register of the source. A formal email stays formal (usted is acceptable only if the source is clearly formal and distant); a casual message stays casual with natural Argentine warmth.
6. Lightly improve clarity and flow. Keep the meaning, tone and roughly the same length.
7. Never use em dashes (—) or en dashes (–) anywhere in your output, including in text you write yourself. Always use a plain hyphen (-) instead, and replace any long dashes in the original.
8. Keep formatting and line breaks as they are. Keep names, product names and technical terms (staging, deploy, pull request, etc.) in English as Argentine developers do.
9. Return only the translated text. No preamble, no explanation, no quotes around it.]]

-- ---------- menubar indicator ----------
local IDLE = "✎"
local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local bar = hs.menubar.new()
local spinner = nil
local resetTimer = nil
local lastStatus = "idle"

local function setMenu()
  bar:setMenu({
    { title = "Last run: " .. lastStatus, disabled = true },
    { title = "-" },
    { title = "⇧⇧            Improve text  (or ⌃⌥I)", disabled = true },
    { title = "⇧⇧ then f   Fix spelling/grammar  (or ⌃⌥F)", disabled = true },
    { title = "⇧⇧ then e   Improve + translate to English", disabled = true },
    { title = "⇧⇧ then r   Improve + translate to Russian", disabled = true },
    { title = "⇧⇧ then s   Improve + translate to Argentine Spanish", disabled = true },
    { title = "⇧⇧ then w   Fix wrong keyboard layout (RU <-> EN)", disabled = true },
    { title = "-" },
    { title = USE_FM and "Local model (fm): on, Haiku fallback" or "Local model (fm): off", disabled = true },
    { title = "-" },
    { title = "Open console", fn = function() hs.openConsole() end },
    { title = "Reload config", fn = function() hs.reload() end },
  })
end

local function showIdle()
  if spinner then spinner:stop(); spinner = nil end
  bar:setTitle(IDLE)
end

local function showWorking()
  if resetTimer then resetTimer:stop(); resetTimer = nil end
  if spinner then spinner:stop() end
  local i = 0
  spinner = hs.timer.doEvery(0.08, function()
    i = (i % #FRAMES) + 1
    bar:setTitle(FRAMES[i])
  end)
end

local function showResult(ok, secs)
  if spinner then spinner:stop(); spinner = nil end
  bar:setTitle(ok and ("✓ " .. secs) or "✗")
  lastStatus = (ok and "ok " or "failed ") .. secs
  setMenu()
  resetTimer = hs.timer.doAfter(3, showIdle)
end

-- ---------- Haiku (Anthropic API) ----------
local function callHaiku(prompt, text, cb)
  if API_KEY == "" then
    cb(nil, "no Anthropic API key in Keychain (service anthropic_api_key); Haiku fallback unavailable")
    return
  end
  local body = hs.json.encode({
    model = MODEL,
    max_tokens = 2048,
    system = prompt,
    messages = { { role = "user", content = text } },
  })
  local headers = {
    ["x-api-key"] = API_KEY,
    ["anthropic-version"] = "2023-06-01",
    ["content-type"] = "application/json",
  }
  hs.http.asyncPost("https://api.anthropic.com/v1/messages", body, headers, function(status, respBody, _)
    if status ~= 200 then
      cb(nil, "HTTP " .. tostring(status) .. ": " .. tostring(respBody))
      return
    end
    local ok, data = pcall(hs.json.decode, respBody)
    if not ok or type(data) ~= "table" or type(data.content) ~= "table" then
      cb(nil, "bad response: " .. tostring(respBody))
      return
    end
    local parts = {}
    for _, block in ipairs(data.content) do
      if block.type == "text" and block.text then
        table.insert(parts, block.text)
      end
    end
    if #parts == 0 then
      cb(nil, "no text block in response: " .. tostring(respBody))
      return
    end
    cb(table.concat(parts, ""), nil)
  end)
end

-- ---------- local model (fm respond) ----------
-- fm takes a single prompt, so the instructions and the text go in one argument.
-- hs.task passes arguments straight to the binary: no shell, no quoting problems.
if USE_FM and not hs.fs.attributes(FM_PATH) then
  print("105fm: " .. FM_PATH .. " not found; using Haiku for everything")
  USE_FM = false
end

local function callFM(prompt, text, cb)
  local full = prompt
    .. "\n\nThe text to process is between the <<< and >>> markers. Do not include the markers in your answer."
    .. "\n<<<\n" .. text .. "\n>>>"
  local done, timer = false, nil
  local function finish(out, err)
    if done then return end
    done = true
    if timer then timer:stop(); timer = nil end
    cb(out, err)
  end

  local task = hs.task.new(FM_PATH, function(code, stdOut, stdErr)
    if code ~= 0 then
      finish(nil, "fm exit " .. tostring(code) .. ": " .. tostring(stdErr))
      return
    end
    local out = (stdOut or ""):gsub("^%s+", ""):gsub("%s+$", "")
    out = out:gsub("^<<<%s*", ""):gsub("%s*>>>$", "")
    if out == "" then
      finish(nil, "fm returned nothing; stderr: " .. tostring(stdErr))
      return
    end
    finish(out, nil)
  end, { "respond", full })

  if not task or not task:start() then
    finish(nil, "could not start " .. FM_PATH)
    return
  end
  timer = hs.timer.doAfter(FM_TIMEOUT, function()
    if not done then
      task:terminate()
      finish(nil, "fm timed out after " .. FM_TIMEOUT .. "s")
    end
  end)
end

-- Cyrillic letters are U+0400..U+04FF: UTF-8 lead byte 0xD0..0xD3.
local function hasCyrillic(text)
  return text:find("[\208-\211][\128-\191]") ~= nil
end

local function chooseBackend(action, text)
  if USE_FM and FM_ACTIONS[action] and (FM_CYRILLIC or not hasCyrillic(text)) then return "fm" end
  return "haiku"
end

showIdle()
setMenu()

-- ---------- clipboard save / restore ----------
-- Saves every type on the clipboard (text, rich text, images, files) and puts it back
-- after the paste has landed, so the tool never leaves its own output on the clipboard.
local RESTORE_CLIPBOARD = true
local RESTORE_DELAY = 0.5   -- seconds after ⌘V; slow apps (Electron) need time to read the paste

local function saveClipboard()
  return { data = hs.pasteboard.readAllData() or {}, count = hs.pasteboard.changeCount() }
end

local function restoreClipboard(saved, delay)
  if not RESTORE_CLIPBOARD or not saved then return end
  hs.timer.doAfter(delay or 0, function()
    if next(saved.data) then hs.pasteboard.writeAllData(saved.data)
    else hs.pasteboard.clearContents() end
  end)
end

-- ⌘C, then hand the copied text to cb. Nothing selected means ⌘C did not touch the
-- clipboard (changeCount unchanged): show ∅ instead of acting on stale clipboard text.
local function copySelection(saved, cb)
  hs.eventtap.keyStroke({"cmd"}, KEY.c)
  hs.timer.doAfter(0.2, function()
    local text = hs.pasteboard.getContents()
    if hs.pasteboard.changeCount() == saved.count or not text or text == "" then
      bar:setTitle("∅")
      hs.timer.doAfter(1.5, showIdle)
      return
    end
    cb(text)
  end)
end

local function pasteText(text, saved)
  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({"cmd"}, KEY.v)
  restoreClipboard(saved, RESTORE_DELAY)
end

-- Models sometimes turn single line breaks into blank lines. Never return more blank
-- lines than the input had: none if the input had none, otherwise at most one in a row.
local function matchLineBreaks(input, out)
  out = out:gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n")
  if input:gsub("\r\n", "\n"):find("\n[ \t]*\n") then
    out = out:gsub("\n\n\n+", "\n\n")
  else
    out = out:gsub("\n\n+", "\n")
  end
  return out
end

-- ---------- the fix action ----------
-- action is a PROMPTS key: fix / improve / english / russian / spanish
local function fixSelection(action)
  local prompt = PROMPTS[action]
  local saved = saveClipboard()
  copySelection(saved, function(text)
    showWorking()
    local started = hs.timer.secondsSinceEpoch()

    local function finish(out, err, used)
      local secs = string.format("%.1fs", hs.timer.secondsSinceEpoch() - started)
        .. (used == "fm" and " fm" or " H")
      if not out or out == "" then
        showResult(false, secs)
        print("105fm error (" .. used .. "): " .. tostring(err))
        restoreClipboard(saved)
        return
      end
      pasteText((matchLineBreaks(text, out):gsub("%s+$", "")), saved)
      showResult(true, secs)
    end

    local function viaHaiku()
      callHaiku(prompt, text, function(out, err) finish(out, err, "haiku") end)
    end

    if chooseBackend(action, text) == "fm" then
      callFM(prompt, text, function(out, err)
        if not out and FM_FALLBACK_TO_HAIKU then
          print("105fm: fm failed, retrying on Haiku: " .. tostring(err))
          viaHaiku()
        else
          finish(out, err, "fm")
        end
      end)
    else
      viaHaiku()
    end
  end)
end

-- ---------- wrong keyboard layout fixer (⇧⇧ then w) ----------
-- "ghbdtn" -> "привет", "руддщ" -> "hello". Pure character mapping, no API call.
-- Direction is detected from the text: mostly Latin letters -> EN>RU, mostly Cyrillic -> RU>EN.
-- After pasting, the input source is switched to the layout the text was meant to be in.
local SWITCH_LAYOUT_AFTER_FIX = true

local UTF8_CHAR = "[\0-\127\194-\244][\128-\191]*"

local function utf8chars(s)
  local t = {}
  for ch in s:gmatch(UTF8_CHAR) do t[#t + 1] = ch end
  return t
end

local function zipInto(map, from, to)
  local a, b = utf8chars(from), utf8chars(to)
  assert(#a == #b, "layout map length mismatch: " .. from)
  for i = 1, #a do map[a[i]] = b[i] end
end

-- Which Russian layout is enabled decides the punctuation map.
-- Letters, [ ] ; ' , . and their shifted forms are the same in Apple "Russian" and "Russian - PC".
local ruLayoutName, enLayoutName = nil, nil
for _, name in ipairs(hs.keycodes.layouts()) do
  if name:match("Russian") then ruLayoutName = ruLayoutName or name
  elseif name:match("U%.S%.") or name:match("ABC") or name:match("English") then enLayoutName = enLayoutName or name
  end
end
local RU_IS_PC = ruLayoutName and ruLayoutName:match("PC") ~= nil

local EN2RU, RU2EN = {}, {}
zipInto(EN2RU, [=[qwertyuiop[]asdfghjkl;'zxcvbnm,.QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>]=],
               [=[йцукенгшщзхъфывапролджэячсмитьбюЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ]=])
if RU_IS_PC then
  zipInto(EN2RU, [=[`~/?@#$^&|]=], [=[ёЁ.,"№;:?/]=])
else
  zipInto(EN2RU, [=[\|`~$%^&*]=], [=[ёЁ][%:,.;]=])
end
for k, v in pairs(EN2RU) do RU2EN[v] = k end

local function convertLayout(text)
  local cyr, lat = 0, 0
  for ch in text:gmatch(UTF8_CHAR) do
    if ch:match("^[A-Za-z]$") then
      lat = lat + 1
    elseif #ch == 2 and (ch:byte(1) == 0xD0 or ch:byte(1) == 0xD1) then
      cyr = cyr + 1
    end
  end
  if cyr == 0 and lat == 0 then return nil end
  local toRussian = lat >= cyr
  local map = toRussian and EN2RU or RU2EN
  local out = text:gsub(UTF8_CHAR, function(ch) return map[ch] or ch end)
  return out, toRussian
end

local function fixLayout()
  local saved = saveClipboard()
  copySelection(saved, function(text)
    local out, toRussian = convertLayout(text)
    if not out then
      bar:setTitle("∅")
      hs.timer.doAfter(1.5, showIdle)
      restoreClipboard(saved)
      return
    end

    pasteText(out, saved)

    if SWITCH_LAYOUT_AFTER_FIX then
      local target = toRussian and ruLayoutName or enLayoutName
      if target then hs.keycodes.setLayout(target) end
    end
    showResult(true, toRussian and "EN>RU" or "RU>EN")
  end)
end

if not ruLayoutName then
  print("layout fixer: no Russian input source enabled; ⇧⇧ w will convert but not switch layouts")
end

-- direct shortcuts
hs.hotkey.bind({"ctrl", "alt"}, KEY.f, function() fixSelection("fix") end)
hs.hotkey.bind({"ctrl", "alt"}, KEY.i, function() fixSelection("improve") end)

-- ---------- leader sequence: F18 (both ⇧ via Karabiner), then f / i / e / r / s / w ----------
local LEADER_TIMEOUT = 1   -- seconds to press a second key (or Esc); otherwise defaults to improve

local leader = hs.hotkey.modal.new({}, KEY.f18)
local leaderTimer = nil

function leader:entered()
  if resetTimer then resetTimer:stop(); resetTimer = nil end
  bar:setTitle("…")
  leaderTimer = hs.timer.doAfter(LEADER_TIMEOUT, function()
    leader:exit()
    fixSelection("improve")   -- no second key -> default to improve
  end)
end

function leader:exited()
  if leaderTimer then leaderTimer:stop(); leaderTimer = nil end
  if bar:title() == "…" then showIdle() end
end

leader:bind({}, KEY.f,      function() leader:exit(); fixSelection("fix") end)
leader:bind({}, KEY.i,      function() leader:exit(); fixSelection("improve") end)
leader:bind({}, KEY.e,      function() leader:exit(); fixSelection("english") end)
leader:bind({}, KEY.r,      function() leader:exit(); fixSelection("russian") end)
leader:bind({}, KEY.s,      function() leader:exit(); fixSelection("spanish") end)
leader:bind({}, KEY.w,      function() leader:exit(); fixLayout() end)
leader:bind({}, KEY.escape, function() leader:exit() end)
leader:bind({}, KEY.f18,    function() leader:exit() end)   -- chord again cancels

if API_KEY == "" then
  if USE_FM then
    print("105fm: no API key in Keychain; running local-only (no Haiku fallback)")
  else
    hs.alert.show("105fm: fm unavailable and no API key in Keychain", 4)
    bar:setTitle("✎ !")
  end
end
