--[[
    ============================================================================
    AZOTH v2.7 - RoChess / "Chess" helper (Place 139717576471404)
    ============================================================================
    Public release build. Everything in this script calls the game's own
    public module API, exactly as the game itself calls it - no reimplemented
    chess logic, no guessed remote payloads.

    FEATURES
      Engine  - best move + eval (game's own Bot.analyse locally, or the
                server engine via VortexBot.analyse), best-move arrow on the
                game's board, eval mirrored to the game's eval bar,
                Auto Play Best Move through App.onBoardMove.
      Game    - Copy FEN/PGN, flip, ply navigation, resign/abort/draw/
                rematch/new game, native takeback & hint (vs bot).
      Play    - online queue per time control, bot games (20 personas).
      Play+   - Auto Match (pick a Game Mode, auto queue again after every
                finished game - pair it with Auto Play for a full
                hands-free loop) and Hide Name (your in-game bar name
                becomes "AZOTH", local only) live in the Play tab.
      Settings- Menu (Anti AFK, No Gameplay Paused, Auto Reconnect on
                Kick, Disable 3D Rendering, Ultra FPS Boost, FPS Limit,
                Hide/Minimize UI on Start, Auto Execute toggle, Unload)
                + Airflow configs & themes. Several menu utilities are
                adapted from Infinite Yield (EdgeIY/infiniteyield).

    LOGO / AUTO EXECUTE SETUP (single file - everything is built in)
      - Put AZOTH_logo.png next to the script as  AZOTH/logo.png  and the
        window + floating button will use the AZOTH seal as their icon
        (loaded through getcustomasset; without the file a default icon
        is used).
      - Auto Execute is INSIDE this file: drop THIS AZOTH.lua into your
        executor's autoexec folder and it starts by itself on launch
        (it waits for the game to load and checks the PlaceId first).
        While it runs, it also arms queue_on_teleport on its own, so
        after a rejoin / teleport it re-executes itself from that same
        file - no separate loader file, no button to press.
        getgenv().AZOTH_URL can point the rejoin loader at a hosted
        copy instead of the local file.

    HONEST LIMITS
      - The server is authoritative for online games (matchmaking, clocks,
        move validation). Illegal suggestions simply do nothing.
      - Hide Name is LOCAL: it changes what YOUR screen shows (stream /
        screenshot privacy). Other players still see your real name.
      - There is NO redeem-code list in the game client (codes are posted
        in the game's Discord server and group), so no code feature is
        included - auto redeem-all is impossible from the client.
    ============================================================================
]]

return {
Init = function(context)

local PLACE_ID = 139717576471404

-- AutoExec bootstrap: this file is its own autoexec file. When an executor
-- runs it from the autoexec folder the game may not be loaded yet - wait.
-- A second execution in the same session (autoexec + manual) is ignored
-- while the first window is alive; delete getgenv().AZOTH_LOADED to force.
if getgenv then
    if getgenv().AZOTH_LOADED then return end
    getgenv().AZOTH_LOADED = true
end
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ----------------------------------------------------------------------------
-- 1. Load Airflow UI
-- ----------------------------------------------------------------------------
local Airflow
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/joustingmatch/-3/refs/heads/main/Source.luau"
        ))()
    end)
    if not ok or not lib then
        warn("[AZOTH] Failed to load Airflow UI: " .. tostring(lib))
        return
    end
    Airflow = lib
end

-- ----------------------------------------------------------------------------
-- 2. Services & game modules (all pcall-guarded, cached)
-- ----------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local Hub = {
    mods = {},
    state = {
        alive = true,
        autoAnalyse = false,
        autoPlay = false,
        showArrow = true,
        useServerEngine = false,
        mirrorEvalBar = true,
        thinkSeconds = 0.7,
        depth = 22,
        autoPlayDelay = 0.9,
        gen = 0,              -- analysis generation (staleness guard)
        lastKey = nil,        -- last analysed position key
        lastResult = nil,     -- last analyse() result + san + forKey
        lastSession = nil,
        selectedTc = "3+2",
        selectedBot = "jasper",
        botColor = "white",
        movesPlayed = 0,
        antiAfk = false,
        autoMatch = false,
        autoMatchDelay = 3,
        gamesCompleted = 0,
        autoMatchBusy = false,
        hideName = false,
        nameOriginals = {},
        autoExecArmed = false,
        autoExecEnabled = false,
        noPause = false,
        reconnect = false,
        reconnectBusy = false,
        noRender = false,
        fpsBoost = false,
        fpsLimit = 0,
        conns = {},
    },
    logHandle = nil,
    logQueue = {},
}

function Hub.mod(name)
    if Hub.mods[name] ~= nil then return Hub.mods[name] or nil end
    local ok, result = pcall(function()
        if name == "Engine" or name == "Bot" or name == "VortexBot"
            or name == "Config" or name == "Openings" then
            local chess = ReplicatedStorage:WaitForChild("Chess", 15)
            return require(chess:WaitForChild(name, 15))
        else
            local client = ReplicatedStorage:WaitForChild("ChessClient", 15)
            return require(client:WaitForChild(name, 15))
        end
    end)
    if ok and type(result) == "table" then
        Hub.mods[name] = result
        return result
    end
    Hub.mods[name] = false
    return nil
end

function Hub.app()
    return Hub.mod("App")
end

function Hub.session()
    local app = Hub.app()
    if app and app.session then return app.session end
    return nil
end

-- ----------------------------------------------------------------------------
-- 3. Window (AZOTH seal logo via getcustomasset when the file is present)
-- ----------------------------------------------------------------------------
-- The seal logo is EMBEDDED in the script (base64 PNG, 256px). Earlier
-- versions downloaded it from Imgur at runtime - on the user's executor
-- that HttpGet never produced the image, so the window kept Airflow's
-- default icon. Embedded = no network, no manual file, works anywhere
-- writefile + getcustomasset exist. Decoder verified byte-exact offline.
local LOGO_B64 = [==[
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
]==]
local B64CH = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64REV = {}
for i = 1, #B64CH do B64REV[string.sub(B64CH, i, i)] = i - 1 end
local function b64decode(data)
    data = string.gsub(data, "[^A-Za-z0-9%+/=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local c1, c2, c3, c4 = string.sub(data, i, i), string.sub(data, i + 1, i + 1),
            string.sub(data, i + 2, i + 2), string.sub(data, i + 3, i + 3)
        local v3 = (c3 == "=" or c3 == "") and 0 or (B64REV[c3] or 0)
        local v4 = (c4 == "=" or c4 == "") and 0 or (B64REV[c4] or 0)
        local n = (B64REV[c1] or 0) * 262144 + (B64REV[c2] or 0) * 4096 + v3 * 64 + v4
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if c3 ~= "=" and c3 ~= "" then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if c4 ~= "=" and c4 ~= "" then
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

local LOGO_URL = "https://i.imgur.com/6ftmM67.png" -- fallback only
local function resolveLogo()
    if getgenv and getgenv().AZOTH_LOGO then return getgenv().AZOTH_LOGO end
    if not getcustomasset then return nil end
    pcall(function()
        if makefolder and isfolder and not isfolder("AZOTH") then
            makefolder("AZOTH")
        end
    end)
    -- 1) Embedded logo (fresh filename every version era: defeats stale
    --    getcustomasset caches from earlier AZOTH/logo.png files).
    if writefile then
        local ok = pcall(function()
            writefile("AZOTH/logo_embed_v2.png", b64decode(LOGO_B64))
        end)
        if ok then
            local okA, asset = pcall(getcustomasset, "AZOTH/logo_embed_v2.png")
            if okA and asset then
                if getgenv then getgenv().AZOTH_LOGO_SOURCE = "embedded" end
                return asset
            end
        end
    end
    -- 2) Hosted download (fallback; kept from v2.2).
    if writefile then
        local okD, data = pcall(function() return game:HttpGet(LOGO_URL) end)
        if okD and type(data) == "string" and #data > 10000
            and string.sub(data, 2, 4) == "PNG" then
            if pcall(writefile, "AZOTH/logo.png", data) then
                local okA, asset = pcall(getcustomasset, "AZOTH/logo.png")
                if okA and asset then return asset end
            end
        end
    end
    -- 3) A logo file the user dropped in manually.
    if isfile then
        for _, path in ipairs({ "AZOTH/logo.png", "AZOTH/AZOTH_logo.png", "AZOTH_logo.png", "logo.png" }) do
            local ok, exists = pcall(isfile, path)
            if ok and exists then
                local ok2, asset = pcall(getcustomasset, path)
                if ok2 and asset then return asset end
            end
        end
    end
    return nil
end
local LOGO = resolveLogo()

local Window = Airflow:CreateWindow({
    Name = "AZOTH",
    LoadingSubtitle = "RoChess - place 139717576471404",
    Icon = LOGO,
    ToggleUIKeybind = "RightControl",
    ToggleButton = { Platform = "Both", Icon = LOGO or "layout-grid" },
    OpenButton = false,
    ConfigurationSaving = { Enabled = true, FolderName = "AZOTH" },
    Home = {
        Stats = { "Players", "FPS", "Ping", "Session" },
    },
})

function Hub.notify(title, content, kind)
    local ok = pcall(function()
        Window:Notify({ Title = title, Content = content, Type = kind or "Info", Duration = 4 })
    end)
    if not ok then
        warn("[AZOTH] " .. tostring(title) .. ": " .. tostring(content))
    end
end

function Hub.log(text)
    if Hub.logHandle then
        pcall(function() Hub.logHandle:Push(text) end)
    else
        table.insert(Hub.logQueue, text)
        if #Hub.logQueue > 200 then table.remove(Hub.logQueue, 1) end
    end
end

function Hub.flushLog()
    if Hub.logHandle and #Hub.logQueue > 0 then
        for _, t in ipairs(Hub.logQueue) do
            pcall(function() Hub.logHandle:Push(t) end)
        end
        Hub.logQueue = {}
    end
end

function Hub.call(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        Hub.notify(label .. " failed", tostring(err), "Error")
        Hub.log("[ERR] " .. label .. ": " .. tostring(err))
        return false
    end
    return true
end

-- ----------------------------------------------------------------------------
-- 4. Chess helpers (game's own Engine / Bot / Session APIs only)
-- ----------------------------------------------------------------------------

-- Position identity: changes whenever the viewed position changes.
function Hub.posKey(session)
    if not session then return nil end
    return tostring(session) .. "|" .. tostring(session.kind)
        .. "|" .. tostring(#(session.ucis or {}))
        .. "|" .. tostring(session.viewPly)
        .. "|" .. tostring(session.version)
end

-- Moves up to the currently viewed ply (what the Analysis page analyses).
function Hub.movesToView(session)
    local out = {}
    local ucis = session.ucis or {}
    local n = math.min(session.viewPly or #ucis, #ucis)
    for i = 1, n do out[i] = ucis[i] end
    return out
end

function Hub.fenNow(session)
    local ok, fen = pcall(function()
        return session:engineAt(session.viewPly or #session.ucis):getFen()
    end)
    if ok and type(fen) == "string" then return fen end
    return session and session.startFen or "-"
end

-- Convert a UCI best move to SAN at the viewed position (display only).
function Hub.bestSan(session, moves, bestUci)
    local Bot = Hub.mod("Bot")
    if not (Bot and Bot.buildEngine and bestUci) then return nil end
    local ok, san = pcall(function()
        local eng = Bot.buildEngine(session.startFen, moves)
        local mv = eng:moveFromUci(bestUci)
        if not mv then return nil end
        return eng:moveToSan(mv)
    end)
    if ok then return san end
    return nil
end

function Hub.formatEval(result)
    if not result then return "-" end
    if result.terminal then
        return result.terminal
    end
    if result.mate then
        if result.mate > 0 then return "M" .. tostring(result.mate) end
        if result.mate < 0 then return "-M" .. tostring(-result.mate) end
        return "mate"
    end
    if type(result.score) == "number" then
        return string.format("%+.2f", result.score / 100)
    end
    return "-"
end

function Hub.clearArrow()
    local app = Hub.app()
    if app and app.board and app.board.setArrow then
        pcall(function() app.board:setArrow("best", nil) end)
    end
end

function Hub.drawBestArrow(result)
    if not (Hub.state.showArrow and result and result.best) then
        Hub.clearArrow()
        return
    end
    local Engine = Hub.mod("Engine")
    local app = Hub.app()
    if not (Engine and app and app.board and app.board.setArrow) then return end
    local best = result.best
    if type(best) ~= "string" or #best < 4 then return end
    pcall(function()
        local from64 = Engine.algToIndex64(string.sub(best, 1, 2))
        local to64 = Engine.algToIndex64(string.sub(best, 3, 4))
        app.board:setArrow("best", from64, to64,
            Color3.fromRGB(129, 182, 76), 0.2)
    end)
end

-- Core analysis. Mirrors the game's own calls:
--   vs bot hint : Bot.analyse(startFen, ucis, 0.7, 20)
--   (the game's own analysis path uses the same call shape)
-- Returns { best, score, mate, depth, nodes, terminal, san, key } or nil.
function Hub.analyseNow(reason)
    local session = Hub.session()
    if not session then
        Hub.log("[Engine] No active session.")
        return nil
    end
    local Bot = Hub.mod("Bot")
    if not Bot then
        Hub.notify("Engine", "The engine could not be found. Try rejoining the game.", "Error")
        return nil
    end
    Hub.state.gen = Hub.state.gen + 1
    local myGen = Hub.state.gen
    local moves = Hub.movesToView(session)
    local seconds = Hub.state.thinkSeconds
    local depth = Hub.state.depth
    local useServer = Hub.state.useServerEngine
    local key = Hub.posKey(session)

    local function cancelled()
        return myGen ~= Hub.state.gen or not Hub.state.alive
    end

    local ok, result = pcall(function()
        if useServer then
            local Vortex = Hub.mod("VortexBot")
            if Vortex and Vortex.analyse then
                return Vortex.analyse(session.startFen, moves, seconds, depth,
                    { cancelled = cancelled })
            end
        end
        return Bot.analyse(session.startFen, moves, seconds, depth,
            { cancelled = cancelled })
    end)
    if cancelled() then return nil end
    if not ok or type(result) ~= "table" then
        Hub.log("[Engine] analyse failed: " .. tostring(result))
        return nil
    end
    result.san = Hub.bestSan(session, moves, result.best)
    result.key = key
    Hub.state.lastResult = result
    Hub.state.lastKey = key
    Hub.drawBestArrow(result)
    if Hub.state.mirrorEvalBar then
        local app = Hub.app()
        if app and app.setEval then
            pcall(function() app.setEval(result.score or 0, result.mate) end)
        end
    end
    Hub.log(string.format("[Engine] %s | best %s (%s) | eval %s | d%s",
        tostring(reason or "analyse"),
        tostring(result.best), tostring(result.san or "-"),
        Hub.formatEval(result), tostring(result.depth or "-")))
    return result
end

-- Play the current best move through the game's own board entry point.
-- App.onBoardMove(from64, to64, promo, instant) validates turn/legality
-- itself and routes per session kind (online/bot/puzzle/rush/analysis).
function Hub.playBest()
    local session = Hub.session()
    if not session then
        Hub.notify("Engine", "No active session.", "Warning")
        return false
    end
    if session.over then
        Hub.notify("Engine", "Game is over.", "Warning")
        return false
    end
    if session.viewPly ~= #session.ucis then
        Hub.notify("Engine", "You are viewing an earlier position - go to the latest move first.", "Warning")
        return false
    end
    local isMine = false
    pcall(function() isMine = session:isMyTurn() end)
    if not isMine then
        Hub.notify("Engine", "Not your turn.", "Warning")
        return false
    end
    local result = Hub.state.lastResult
    if not result or result.key ~= Hub.posKey(session) or not result.best then
        result = Hub.analyseNow("play-refresh")
    end
    if not result or not result.best then
        Hub.notify("Engine", "No best move available (terminal position?).", "Warning")
        return false
    end
    local Engine = Hub.mod("Engine")
    local Bot = Hub.mod("Bot")
    local app = Hub.app()
    if not (Engine and Bot and app and app.onBoardMove) then
        Hub.notify("Engine", "App.onBoardMove unavailable.", "Error")
        return false
    end
    local played = false
    local ok, err = pcall(function()
        local eng = Bot.buildEngine(session.startFen, session.ucis)
        local mv = eng:moveFromUci(result.best)
        if not mv then error("best move not legal in current position") end
        local from64, to64 = Engine.moveSquares64(mv)
        local promo = Engine.movePromo(mv)
        played = app.onBoardMove(from64, to64, promo, false) == true
    end)
    if not ok then
        Hub.notify("Play Best Move failed", tostring(err), "Error")
        return false
    end
    if played then
        Hub.state.movesPlayed = Hub.state.movesPlayed + 1
        Hub.log("[Engine] Played best move " .. tostring(result.best)
            .. " (" .. tostring(result.san or "-") .. ")")
        Hub.state.lastResult = nil
        Hub.clearArrow()
    else
        Hub.log("[Engine] Game rejected the move (see App.onBoardMove guards).")
    end
    return played
end

-- Background loop: auto-analyse on position change + optional auto-play.
task.spawn(function()
    while Hub.state.alive do
        task.wait(0.3)
        local session = Hub.session()
        if session and not session.over then
            local key = Hub.posKey(session)
            if key and key ~= Hub.state.lastKey then
                if Hub.state.autoAnalyse or Hub.state.autoPlay then
                    local res = Hub.analyseNow("auto")
                    if res and Hub.state.autoPlay and Hub.state.alive then
                        local mine = false
                        pcall(function() mine = session:isMyTurn() end)
                        if mine and session.viewPly == #session.ucis
                            and Hub.posKey(session) == res.key then
                            task.wait(Hub.state.autoPlayDelay)
                            if Hub.state.autoPlay and Hub.state.alive
                                and Hub.posKey(session) == res.key then
                                Hub.playBest()
                            end
                        end
                    end
                end
            end
        end
        if not session then
            if Hub.state.lastKey ~= nil then
                Hub.state.lastKey = nil
                Hub.state.lastResult = nil
                Hub.clearArrow()
            end
        end
    end
end)

local function copyText(text, label)
    local done = false
    if setclipboard then
        local ok = pcall(function() setclipboard(text) end)
        done = ok
    end
    if done then
        Hub.notify(label, "Copied to clipboard.", "Success")
    else
        Hub.notify(label, "setclipboard unavailable - see Log.", "Warning")
        Hub.log("[" .. label .. "] " .. text)
    end
end

-- ----------------------------------------------------------------------------
-- 4b. Hide Name (in-game) + Auto Execute helpers
-- ----------------------------------------------------------------------------
-- Session white/black are myInfo-style tables { userId, name, display, ... }
-- built from the LocalPlayer for your side. Patching them locally changes
-- what the game's PlayerBars render (refreshBars -> bar:setPlayer(info)).
function Hub.applyHideName()
    local session = Hub.session()
    if not session then return end
    local changed = false
    for _, key in ipairs({ "white", "black" }) do
        local info = session[key]
        if type(info) == "table" and info.userId == LocalPlayer.UserId then
            if not Hub.state.nameOriginals[info] then
                Hub.state.nameOriginals[info] = {
                    display = info.display, name = info.name,
                }
            end
            if info.display ~= "AZOTH" then info.display = "AZOTH"; changed = true end
            if info.name ~= "AZOTH" then info.name = "AZOTH"; changed = true end
        end
    end
    if changed then
        local app = Hub.app()
        if app and app.refreshBars then
            pcall(function() app.refreshBars() end)
        end
    end
end

function Hub.restoreNames()
    for info, orig in pairs(Hub.state.nameOriginals) do
        pcall(function()
            info.display = orig.display
            info.name = orig.name
        end)
    end
    Hub.state.nameOriginals = {}
    local app = Hub.app()
    if app and app.refreshBars then
        pcall(function() app.refreshBars() end)
    end
end

local SELF_LOADER = [=[
repeat task.wait() until game and game:IsLoaded()
task.wait(2)
local ok, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Azoth666/AZOTH/main/loader.lua"))()
end)
if not ok then
    warn("[AZOTH] auto execute failed: " .. tostring(err))
end
]=]

-- Arm BOTH auto-execute routes: queue_on_teleport (rejoins in this session)
-- and an autoexec folder file (fresh launches). The file is written by this
-- script itself - users still only ever receive the single AZOTH.lua.
function Hub.armAutoExec(silent)
    local armed = {}
    local qot = queue_on_teleport or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if qot and pcall(function() qot(SELF_LOADER) end) then
        armed[#armed + 1] = "queue_on_teleport"
    end
    if writefile and pcall(function()
        writefile("autoexec/AZOTH.lua", SELF_LOADER)
    end) then
        armed[#armed + 1] = "autoexec file"
    end
    Hub.state.autoExecArmed = #armed > 0
    if Hub.state.autoExecArmed then
        Hub.log("[Menu] Auto Execute armed via: " .. table.concat(armed, " + "))
    elseif not silent then
        Hub.log("[Menu] Auto Execute could not arm: this executor exposes neither queue_on_teleport nor writefile.")
    end
    return Hub.state.autoExecArmed
end

function Hub.installAutoExec()
    if Hub.armAutoExec() then
        Hub.notify("AZOTH", "Auto Execute is ON - AZOTH will start by itself when you rejoin or reopen the game.", "Success")
    else
        Hub.notify("AZOTH", "Your executor does not support Auto Execute, so it could not be turned on.", "Warning")
    end
end

-- ----------------------------------------------------------------------------
-- 4c. Menu utilities (Settings tab) - several adapted from Infinite Yield
--     (EdgeIY/infiniteyield): antigameplaypaused, antiafk, norender, setfpscap
-- ----------------------------------------------------------------------------
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")

function Hub.setAntiAfk(v)
    Hub.state.antiAfk = v
    if v then
        -- Infinite Yield approach: neutralise the existing Idled handlers,
        -- then answer future idle checks ourselves.
        if getconnections then
            pcall(function()
                for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
                    pcall(function() c:Disable() end)
                end
            end)
        end
        if not Hub.state.conns.afk then
            Hub.state.conns.afk = LocalPlayer.Idled:Connect(function()
                if not Hub.state.antiAfk then return end
                pcall(function()
                    local vu = game:GetService("VirtualUser")
                    vu:CaptureController()
                    vu:ClickButton2(Vector2.new())
                end)
                pcall(function()
                    local vim = Instance.new("VirtualInputManager")
                    vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    vim:Destroy()
                end)
                Hub.log("[Menu] Anti-AFK: idle check answered.")
            end)
        end
    else
        if Hub.state.conns.afk then
            pcall(function() Hub.state.conns.afk:Disconnect() end)
            Hub.state.conns.afk = nil
        end
    end
    Hub.log("[Menu] Anti-AFK " .. (v and "ON" or "OFF"))
end

function Hub.setNoGameplayPaused(v)
    Hub.state.noPause = v
    if v then
        -- Infinite Yield "antigameplaypaused": the loading-lag pause box is
        -- CoreGui.RobloxGui child "CoreScripts/NetworkPause" - destroy it
        -- on sight (and the one already on screen).
        local rg = CoreGui:FindFirstChild("RobloxGui")
        if rg then
            local existing = rg:FindFirstChild("CoreScripts/NetworkPause")
            if existing then pcall(function() existing:Destroy() end) end
            if not Hub.state.conns.pause then
                Hub.state.conns.pause = rg.ChildAdded:Connect(function(obj)
                    if obj.Name == "CoreScripts/NetworkPause" then
                        pcall(function() obj:Destroy() end)
                        Hub.log("[Menu] Gameplay Paused box cleared.")
                    end
                end)
            end
        else
            Hub.log("[Menu] RobloxGui not found - No Gameplay Paused could not arm.")
        end
    else
        if Hub.state.conns.pause then
            pcall(function() Hub.state.conns.pause:Disconnect() end)
            Hub.state.conns.pause = nil
        end
    end
    Hub.log("[Menu] No Gameplay Paused " .. (v and "ON" or "OFF"))
end

local function attemptRejoin(why)
    if not Hub.state.reconnect or Hub.state.reconnectBusy then return end
    Hub.state.reconnectBusy = true
    Hub.log("[Menu] Disconnect/kick prompt detected (" .. tostring(why) .. ") - rejoining in 2s...")
    task.wait(2)
    local ok, err = pcall(function()
        TeleportService:Teleport(PLACE_ID, LocalPlayer)
    end)
    if not ok then
        Hub.state.reconnectBusy = false
        Hub.log("[Menu] Rejoin failed: " .. tostring(err))
    end
end

function Hub.setAutoReconnect(v)
    Hub.state.reconnect = v
    if v and not Hub.state.conns.reconnect then
        Hub.state.conns.reconnect = CoreGui.DescendantAdded:Connect(function(obj)
            if obj.Name == "ErrorPrompt" then
                task.spawn(function() attemptRejoin("ErrorPrompt") end)
            end
        end)
    elseif not v and Hub.state.conns.reconnect then
        pcall(function() Hub.state.conns.reconnect:Disconnect() end)
        Hub.state.conns.reconnect = nil
    end
    Hub.log("[Menu] Auto Reconnect on Kick " .. (v and "ON" or "OFF"))
end

function Hub.setNoRender(v)
    Hub.state.noRender = v
    -- Infinite Yield "norender"/"render".
    pcall(function() RunService:Set3dRenderingEnabled(not v) end)
    Hub.log("[Menu] 3D Rendering " .. (v and "DISABLED" or "enabled"))
end

local boostOriginals = nil
function Hub.setFpsBoost(v)
    Hub.state.fpsBoost = v
    local Lighting = game:GetService("Lighting")
    local Terrain = workspace:FindFirstChildOfClass("Terrain")
    if v then
        if not boostOriginals then
            boostOriginals = {}
            pcall(function() boostOriginals.shadows = Lighting.GlobalShadows end)
            pcall(function() boostOriginals.fogEnd = Lighting.FogEnd end)
            if Terrain then
                pcall(function() boostOriginals.waterWaveSize = Terrain.WaterWaveSize end)
                pcall(function() boostOriginals.waterWaveSpeed = Terrain.WaterWaveSpeed end)
                pcall(function() boostOriginals.waterReflectance = Terrain.WaterReflectance end)
                pcall(function() boostOriginals.waterTransparency = Terrain.WaterTransparency end)
            end
        end
        pcall(function() Lighting.GlobalShadows = false end)
        pcall(function() Lighting.FogEnd = 100000 end)
        if Terrain then
            pcall(function() Terrain.WaterWaveSize = 0 end)
            pcall(function() Terrain.WaterWaveSpeed = 0 end)
            pcall(function() Terrain.WaterReflectance = 0 end)
            pcall(function() Terrain.WaterTransparency = 0 end)
        end
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        Hub.log("[Menu] Ultra FPS Boost ON (shadows/water/quality lowered).")
    else
        if boostOriginals then
            pcall(function() Lighting.GlobalShadows = boostOriginals.shadows end)
            pcall(function() Lighting.FogEnd = boostOriginals.fogEnd end)
            if Terrain then
                pcall(function() Terrain.WaterWaveSize = boostOriginals.waterWaveSize end)
                pcall(function() Terrain.WaterWaveSpeed = boostOriginals.waterWaveSpeed end)
                pcall(function() Terrain.WaterReflectance = boostOriginals.waterReflectance end)
                pcall(function() Terrain.WaterTransparency = boostOriginals.waterTransparency end)
            end
        end
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
        Hub.log("[Menu] Ultra FPS Boost OFF (values restored where saved).")
    end
end

function Hub.setFpsLimit(v)
    Hub.state.fpsLimit = v
    if setfpscap and type(setfpscap) == "function" then
        -- 0 = off: cap so high it never engages.
        pcall(function() setfpscap(v > 0 and v or 1000) end)
    end
    -- Backup limiter: some executors accept setfpscap but never enforce it
    -- (v2.1 bug: limit set to 35 while the game still ran at 61 FPS).
    -- A RenderStepped gate that holds the frame until its slot arrives
    -- caps FPS on any executor. The connection is created once and idles
    -- (returns instantly) whenever the limit is off or >= 240.
    if not Hub.state.conns.fps then
        local lastFrame = os.clock()
        Hub.state.conns.fps = RunService.RenderStepped:Connect(function()
            local cap = Hub.state.fpsLimit
            if not cap or cap <= 0 or cap >= 240 or not Hub.state.alive then
                lastFrame = os.clock()
                return
            end
            local target = lastFrame + 1 / cap
            while os.clock() < target do end
            lastFrame = os.clock()
        end)
    end
    Hub.log("[Menu] FPS Limit = " .. (v > 0 and tostring(v) or "off")
        .. " (setfpscap " .. (setfpscap and "called" or "unavailable")
        .. " + frame limiter active)")
end

function Hub.unload()
    Hub.state.alive = false
    Hub.state.gen = Hub.state.gen + 1
    pcall(function() Hub.restoreNames() end)
    Hub.clearArrow()
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    for _, conn in pairs(Hub.state.conns) do
        pcall(function() conn:Disconnect() end)
    end
    Hub.state.conns = {}
    if getgenv then getgenv().AZOTH_LOADED = nil end
    Hub.log("[AZOTH] Unloading...")
    local ok = pcall(function() Window:Unload() end)
    if not ok then
        pcall(function() Window:Destroy() end)
    end
end

-- ----------------------------------------------------------------------------
-- 5. TAB: Engine
-- ----------------------------------------------------------------------------
local EngineTab = Window:CreateTab({ Name = "Engine", Icon = "cpu" })
local EngineBox = EngineTab:CreateGroupbox({ Name = "Best Move Engine", Side = "Left" })

EngineBox:CreateParagraph({
    Title = "How it works",
    Content = "AZOTH watches your live game and finds the strongest move for you. Turn on Auto Analyse to see it every turn, or Auto Play and AZOTH will play it for you.",
})

local tAutoAnalyse = EngineBox:CreateToggle({
    Name = "Auto Analyse", Flag = "AZ_AutoAnalyse", CurrentValue = false,
    Desc = "Analyse automatically whenever the position changes",
    Callback = function(v)
        Hub.state.autoAnalyse = v
        if v then task.spawn(function() Hub.analyseNow("auto-on") end) end
        if not v then Hub.state.gen = Hub.state.gen + 1 end
    end,
})
local tAutoPlay = EngineBox:CreateToggle({
    Name = "Auto Play Best Move", Flag = "AZ_AutoPlay", CurrentValue = false,
    Desc = "Plays the best move for you on your turn. The game mode it plays is picked in Play > Auto Match > Game Mode, with Auto Match ON",
    Callback = function(v)
        Hub.state.autoPlay = v
        if v then
            Hub.state.autoAnalyse = true
            Hub.log("[Engine] Auto Play ON (delay "
                .. tostring(Hub.state.autoPlayDelay) .. "s)")
            task.spawn(function() Hub.analyseNow("autoplay-on") end)
        end
    end,
})
EngineBox:CreateToggle({
    Name = "Show Best Arrow", Flag = "AZ_ShowArrow", CurrentValue = true,
    Desc = "Draws an arrow on the board showing the best move",
    Callback = function(v)
        Hub.state.showArrow = v
        if v then Hub.drawBestArrow(Hub.state.lastResult) else Hub.clearArrow() end
    end,
})
EngineBox:CreateToggle({
    Name = "Aether Engine", Flag = "AZ_ServerEngine", CurrentValue = false,
    Desc = "Use the stronger cloud engine for analysis instead of the onboard one",
    Callback = function(v) Hub.state.useServerEngine = v end,
})
EngineBox:CreateToggle({
    Name = "Mirror Eval to Game Bar", Flag = "AZ_MirrorEval", CurrentValue = true,
    Desc = "Shows the engine's score on the game's own score bar",
    Callback = function(v) Hub.state.mirrorEvalBar = v end,
})
EngineBox:CreateSlider({
    Name = "Think Time", Range = { 0.2, 10 }, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.7, Flag = "AZ_ThinkTime",
    Desc = "How many seconds the engine thinks before choosing a move",
    Callback = function(v) Hub.state.thinkSeconds = v end,
})
EngineBox:CreateSlider({
    Name = "Max Depth", Range = { 8, 30 }, Increment = 1,
    CurrentValue = 22, Flag = "AZ_Depth",
    Desc = "How far ahead the engine looks when choosing a move",
    Callback = function(v) Hub.state.depth = v end,
})
EngineBox:CreateSlider({
    Name = "Auto Play Delay", Range = { 0.3, 10 }, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.9, Flag = "AZ_PlayDelay",
    Desc = "Wait this long after analysis before auto-playing",
    Callback = function(v) Hub.state.autoPlayDelay = v end,
})
EngineBox:CreateButtonRow({
    { Name = "Analyse Now", Callback = function()
        task.spawn(function() Hub.analyseNow("manual") end)
    end },
    { Name = "Play Best Move", Callback = function()
        task.spawn(function() Hub.playBest() end)
    end },
})
EngineBox:CreateButton({
    Name = "Clear Arrow",
    Callback = function() Hub.clearArrow() end,
})

local EngineInfo = EngineTab:CreateGroupbox({ Name = "Live Position", Side = "Right" })
EngineInfo:CreateStatus({
    Name = "Session", Style = "Row", Pin = true,
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>none</Muted>" end
        return "<Accent>" .. tostring(s.kind) .. "</Accent>"
            .. (s.over and " <Error>(over)</Error>" or "")
    end,
})
EngineInfo:CreateStatus({
    Name = "Turn / Ply", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local mine = false
        pcall(function() mine = s:isMyTurn() end)
        return "<Muted>ply " .. tostring(s.viewPly) .. "/" .. tostring(#s.ucis)
            .. (mine and " - <Success>your turn</Success>" or "") .. "</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Best Move", Style = "Row",
    Update = function()
        local r = Hub.state.lastResult
        if not r or not r.best then return "<Muted>-</Muted>" end
        return "<Success>" .. tostring(r.san or r.best) .. "</Success>"
            .. " <Muted>(" .. tostring(r.best) .. ")</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Eval", Style = "Row",
    Update = function()
        local r = Hub.state.lastResult
        if not r then return "<Muted>-</Muted>" end
        return "<Accent>" .. Hub.formatEval(r) .. "</Accent>"
            .. " <Muted>(White perspective)</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Depth / Nodes", Style = "Row",
    Update = function()
        local r = Hub.state.lastResult
        if not r then return "<Muted>-</Muted>" end
        return "<Muted>d" .. tostring(r.depth or "-")
            .. " / " .. tostring(r.nodes or "-") .. " nodes</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Opening", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local Openings = Hub.mod("Openings")
        if not Openings then return "<Muted>n/a</Muted>" end
        local ok, name = pcall(function()
            return Openings.forSession(s, s.viewPly)
        end)
        if ok and name then return "<Muted>" .. tostring(name) .. "</Muted>" end
        return "<Muted>-</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Material", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local ok, diff = pcall(function()
            local _, _, d = s:material(s.viewPly)
            return d
        end)
        if ok and type(diff) == "number" then
            if diff == 0 then return "<Muted>equal</Muted>" end
            return "<Muted>" .. string.format("%+d", diff) .. " (White)</Muted>"
        end
        return "<Muted>-</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Game Status", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local ok, st = pcall(function() return s:status() end)
        if ok and st then return "<Muted>" .. tostring(st) .. "</Muted>" end
        return "<Muted>-</Muted>"
    end,
})
EngineInfo:CreateStatus({
    Name = "Auto-Played", Style = "Row",
    Update = function()
        return "<Accent>" .. tostring(Hub.state.movesPlayed) .. "</Accent>"
    end,
})

-- ----------------------------------------------------------------------------
-- 6. TAB: Game
-- ----------------------------------------------------------------------------
local GameTab = Window:CreateTab({ Name = "Game", Icon = "swords" })
local GameBox = GameTab:CreateGroupbox({ Name = "Current Game", Side = "Left" })

GameBox:CreateButtonRow({
    { Name = "Copy FEN", Callback = function()
        local s = Hub.session()
        if s then copyText(Hub.fenNow(s), "FEN") end
    end },
    { Name = "Copy PGN", Callback = function()
        local s = Hub.session()
        if s then
            local ok, pgn = pcall(function() return s:pgn("*") end)
            if ok and pgn then copyText(pgn, "PGN") end
        end
    end },
})
GameBox:CreateButtonRow({
    { Name = "Flip Board", Callback = function()
        local app = Hub.app()
        if app and app.flip then Hub.call("Flip", function() app.flip() end) end
    end },
    { Name = "Go Home", Callback = function()
        local app = Hub.app()
        if app and app.goHome then Hub.call("Go Home", function() app.goHome() end) end
    end },
})
GameBox:CreateButtonRow({
    { Name = "|< First", Callback = function()
        local app = Hub.app()
        if app and app.navigate then pcall(function() app.navigate(0) end) end
    end },
    { Name = "< Prev", Callback = function()
        local app, s = Hub.app(), Hub.session()
        if app and app.navigate and s then pcall(function() app.navigate(s.viewPly - 1) end) end
    end },
    { Name = "Next >", Callback = function()
        local app, s = Hub.app(), Hub.session()
        if app and app.navigate and s then pcall(function() app.navigate(s.viewPly + 1) end) end
    end },
    { Name = "Last >|", Callback = function()
        local app, s = Hub.app(), Hub.session()
        if app and app.navigate and s then pcall(function() app.navigate(#s.ucis) end) end
    end },
})
GameBox:CreateParagraph({
    Title = "Online actions",
    Content = "These buttons do exactly what the game's own buttons do - resign, ask for a draw, rematch, and more - just from here, without leaving this menu.",
})
GameBox:CreateButtonRow({
    { Name = "Resign", Style = "Danger", Callback = function()
        local app = Hub.app()
        if app and app.resign then Hub.call("Resign", function() app.resign() end) end
    end },
    { Name = "Abort", Callback = function()
        local app = Hub.app()
        if app and app.abort then Hub.call("Abort", function() app.abort() end) end
    end },
})
GameBox:CreateButtonRow({
    { Name = "Offer Draw", Callback = function()
        local app = Hub.app()
        if app and app.offerDraw then Hub.call("Offer Draw", function() app.offerDraw() end) end
    end },
    { Name = "Accept Draw", Callback = function()
        local app = Hub.app()
        if app and app.respondDraw then Hub.call("Accept Draw", function() app.respondDraw(true) end) end
    end },
})
GameBox:CreateButtonRow({
    { Name = "Rematch", Callback = function()
        local app = Hub.app()
        if app and app.rematch then Hub.call("Rematch", function() app.rematch() end) end
    end },
    { Name = "New Game", Callback = function()
        local app = Hub.app()
        if app and app.newGame then Hub.call("New Game", function() app.newGame() end) end
    end },
})

local BotTools = GameTab:CreateGroupbox({ Name = "Vs Bot Tools", Side = "Right" })
BotTools:CreateParagraph({
    Title = "Game-native helpers",
    Content = "Takeback and Hint are features from the game itself. Hint only works in bot games - that is how the game made it.",
})
BotTools:CreateButtonRow({
    { Name = "Takeback", Callback = function()
        local app = Hub.app()
        if app and app.takeback then Hub.call("Takeback", function() app.takeback() end) end
    end },
    { Name = "Native Hint", Callback = function()
        local app = Hub.app()
        if app and app.hint then Hub.call("Hint", function() app.hint() end) end
    end },
})
BotTools:CreateStatus({
    Name = "Opponent", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local opp = (s.myColor == 1) and s.black or s.white
        if type(opp) == "table" and opp.display then
            return "<Muted>" .. tostring(opp.display)
                .. (opp.rating and (" (" .. tostring(opp.rating) .. ")") or "")
                .. "</Muted>"
        end
        return "<Muted>-</Muted>"
    end,
})
BotTools:CreateStatus({
    Name = "FEN", Style = "Row",
    Update = function()
        local s = Hub.session()
        if not s then return "<Muted>-</Muted>" end
        local fen = Hub.fenNow(s)
        return "<Muted>" .. string.sub(fen, 1, 42) .. "</Muted>"
    end,
})

-- ----------------------------------------------------------------------------
-- 7. TAB: Play (matchmaking + bot games, via App entry points)
-- ----------------------------------------------------------------------------
local PlayTab = Window:CreateTab({ Name = "Play", Icon = "play" })
local QueueBox = PlayTab:CreateGroupbox({ Name = "Online Queue", Side = "Left" })

local tcOptions, tcByLabel = {}, {}
do
    local Config = Hub.mod("Config")
    if Config and Config.TIME_CONTROLS then
        for _, tc in ipairs(Config.TIME_CONTROLS) do
            local label = tostring(tc.label) .. " (" .. tostring(tc.class) .. ")"
            tcOptions[#tcOptions + 1] = label
            tcByLabel[label] = tc.id
        end
    end
    if #tcOptions == 0 then
        tcOptions = { "3 | 2 (blitz)" }
        tcByLabel["3 | 2 (blitz)"] = "3+2"
    end
end
QueueBox:CreateDropdown({
    Name = "Time Control", Options = tcOptions, CurrentOption = { tcOptions[6] or tcOptions[1] },
    Flag = "AZ_TC",
    Callback = function(list)
        local label = type(list) == "table" and list[1] or list
        if label and tcByLabel[label] then Hub.state.selectedTc = tcByLabel[label] end
    end,
})
QueueBox:CreateButtonRow({
    { Name = "Start Search", Callback = function()
        local app = Hub.app()
        if app and app.startSearch then
            Hub.call("Start Search", function() app.startSearch(Hub.state.selectedTc) end)
            Hub.log("[Play] Queue " .. tostring(Hub.state.selectedTc))
        end
    end },
    { Name = "Cancel Search", Style = "Danger", Callback = function()
        local app = Hub.app()
        if app and app.cancelSearch then Hub.call("Cancel Search", function() app.cancelSearch() end) end
    end },
})
QueueBox:CreateStatus({
    Name = "Searching", Style = "Row",
    Update = function()
        local app = Hub.app()
        if app and app.searching then return "<Success>yes</Success>" end
        return "<Muted>no</Muted>"
    end,
})

local BotBox = PlayTab:CreateGroupbox({ Name = "Play vs Bot", Side = "Right" })
local botOptions, botByLabel = {}, {}
do
    local Config = Hub.mod("Config")
    if Config and Config.BOTS then
        for _, b in ipairs(Config.BOTS) do
            local label = tostring(b.name) .. " (" .. tostring(b.rating) .. ")"
            botOptions[#botOptions + 1] = label
            botByLabel[label] = b.id
        end
    end
    if #botOptions == 0 then
        botOptions = { "Jasper (800)" }
        botByLabel["Jasper (800)"] = "jasper"
    end
end
BotBox:CreateDropdown({
    Name = "Bot", Options = botOptions, CurrentOption = { "Jasper (800)" },
    Flag = "AZ_Bot",
    Callback = function(list)
        local label = type(list) == "table" and list[1] or list
        if label and botByLabel[label] then Hub.state.selectedBot = botByLabel[label] end
    end,
})
BotBox:CreateDropdown({
    Name = "Play As", Options = { "White", "Black", "Random" },
    CurrentOption = { "White" }, Flag = "AZ_BotColor",
    Callback = function(list)
        local label = type(list) == "table" and list[1] or list
        if label == "White" then Hub.state.botColor = "white"
        elseif label == "Black" then Hub.state.botColor = "black"
        else Hub.state.botColor = nil end
    end,
})
BotBox:CreateButton({
    Name = "Start Bot Game",
    Callback = function()
        local app = Hub.app()
        if app and app.startBotGame then
            Hub.call("Start Bot Game", function()
                app.startBotGame(Hub.state.selectedBot, Hub.state.botColor)
            end)
            Hub.log("[Play] Bot game vs " .. tostring(Hub.state.selectedBot))
        end
    end,
})

-- (Auto Match + Privacy live in the Play tab since v2.2 - no separate Auto tab.)
local MatchBox = PlayTab:CreateGroupbox({ Name = "Auto Match Loop", Side = "Left" })
MatchBox:CreateParagraph({
    Title = "How it works",
    Content = "Pick the Game Mode below first (e.g. Blitz 3 min, Bullet, Rapid), turn Auto Match on, and AZOTH queues that mode for you. When a game ends it waits a few seconds and queues the same mode again - forever, until you turn it off. Pair with Engine > Auto Play Best Move for a fully hands-free loop; without it, you play the moves yourself and AZOTH only re-queues.",
})
MatchBox:CreateDropdown({
    Name = "Game Mode",
    Desc = "The time control Auto Match queues for (Bullet / Blitz / Rapid - same list as the Play tab queue)",
    Options = tcOptions,
    CurrentOption = { tcOptions[6] or tcOptions[1] },
    Flag = "AZ_AutoMatchTC",
    Callback = function(list)
        local label = type(list) == "table" and list[1] or list
        if label and tcByLabel[label] then
            Hub.state.selectedTc = tcByLabel[label]
            Hub.log("[Auto] Game Mode = " .. tostring(label) .. " (" .. tostring(Hub.state.selectedTc) .. ")")
        end
    end,
})
local tAutoMatch = MatchBox:CreateToggle({
    Name = "Auto Match", Flag = "AZ_AutoMatch", CurrentValue = false,
    Desc = "Auto queue, and auto queue again after every finished game",
    Callback = function(v)
        Hub.state.autoMatch = v
        Hub.log("[Auto] Auto Match " .. (v and "ON (TC " .. tostring(Hub.state.selectedTc) .. ")" or "OFF"))
        if v then Hub.notify("AZOTH", "Auto Match ON - queueing " .. tostring(Hub.state.selectedTc) .. ".", "Success") end
    end,
})
MatchBox:CreateSlider({
    Name = "Re-queue Delay", Range = { 1, 30 }, Increment = 1, Suffix = "s",
    CurrentValue = 3, Flag = "AZ_RequeueDelay",
    Desc = "Wait this long after a game ends before queueing again",
    Callback = function(v) Hub.state.autoMatchDelay = v end,
})
MatchBox:CreateButton({
    Name = "STOP ALL AUTOMATION",
    Style = "Danger",
    Callback = function()
        Hub.state.autoAnalyse = false
        Hub.state.autoPlay = false
        Hub.state.autoMatch = false
        Hub.state.gen = Hub.state.gen + 1
        Hub.clearArrow()
        pcall(function() tAutoAnalyse:Set(false) end)
        pcall(function() tAutoPlay:Set(false) end)
        pcall(function() tAutoMatch:Set(false) end)
        Hub.notify("AZOTH", "All automation stopped.", "Warning")
    end,
})
MatchBox:CreateStatus({
    Name = "Games Completed", Style = "Row", Pin = true,
    Update = function()
        return "<Accent>" .. tostring(Hub.state.gamesCompleted) .. "</Accent>"
    end,
})
MatchBox:CreateStatus({
    Name = "Loop State", Style = "Row",
    Update = function()
        if not Hub.state.autoMatch then return "<Muted>off</Muted>" end
        local app = Hub.app()
        local s = Hub.session()
        if app and app.searching then return "<Success>searching...</Success>" end
        if app and app.joining then return "<Success>match found, joining...</Success>" end
        if s and not s.over and (s.kind == "online" or s.kind == "bot") then
            return "<Accent>in game (" .. tostring(s.kind) .. ")</Accent>"
        end
        return "<Muted>waiting to queue</Muted>"
    end,
})

local PrivacyBox = PlayTab:CreateGroupbox({ Name = "Privacy", Side = "Right" })
PrivacyBox:CreateToggle({
    Name = "Hide Name (In-Game)", Flag = "AZ_HideName", CurrentValue = false,
    Desc = "Your name on the game's player bars becomes AZOTH (local only - for streams/screenshots; also hides the name inside this GUI)",
    Callback = function(v)
        Hub.state.hideName = v
        pcall(function() Window:SetHideName(v) end)
        if v then
            Hub.applyHideName()
            Hub.log("[Auto] Hide Name ON - in-game name shows AZOTH.")
        else
            Hub.restoreNames()
            Hub.log("[Auto] Hide Name OFF - real name restored.")
        end
    end,
})
PrivacyBox:CreateStatus({
    Name = "Shown As", Style = "Row",
    Update = function()
        if Hub.state.hideName then return "<Success>AZOTH</Success>" end
        return "<Muted>" .. tostring(LocalPlayer.DisplayName) .. "</Muted>"
    end,
})

-- Auto Match state machine + Hide Name re-apply (new sessions carry the
-- real name again, so the patch is re-applied while the toggle is on).
task.spawn(function()
    local wasLive = false
    while Hub.state.alive do
        task.wait(1)
        local app = Hub.app()
        local session = Hub.session()
        if Hub.state.hideName then Hub.applyHideName() end
        if session and not session.over
            and (session.kind == "online" or session.kind == "bot") then
            wasLive = true
        elseif wasLive and session and session.over then
            wasLive = false
            Hub.state.gamesCompleted = Hub.state.gamesCompleted + 1
            Hub.log("[Auto] Game finished (#" .. tostring(Hub.state.gamesCompleted) .. ").")
        end
        if Hub.state.autoMatch and app and not Hub.state.autoMatchBusy
            and not app.searching and not app.joining then
            local needQueue = false
            local useNewGame = false
            if not session or session.kind == "idle" then
                needQueue = true
            elseif session.over and session.kind == "online" then
                needQueue = true
                useNewGame = true -- game's own post-game flow (leaveGame + search, same TC)
            elseif session.over and session.kind == "bot" then
                needQueue = true -- handled as rematch below
            end
            if needQueue then
                Hub.state.autoMatchBusy = true
                task.spawn(function()
                    task.wait(Hub.state.autoMatchDelay)
                    if Hub.state.autoMatch and Hub.state.alive then
                        local a = Hub.app()
                        local s2 = Hub.session()
                        if a and not a.searching and not a.joining then
                            if s2 and s2.over and s2.kind == "bot" and a.rematch then
                                Hub.call("Auto Rematch", function() a.rematch() end)
                                Hub.log("[Auto] Bot game restarted (rematch).")
                            elseif useNewGame and a.newGame then
                                Hub.call("Auto New Game", function() a.newGame() end)
                                Hub.log("[Auto] Next game via New Game flow.")
                            elseif a.startSearch then
                                Hub.call("Auto Queue", function() a.startSearch(Hub.state.selectedTc) end)
                                Hub.log("[Auto] Queued " .. tostring(Hub.state.selectedTc) .. ".")
                            end
                        end
                    end
                    Hub.state.autoMatchBusy = false
                end)
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 9. TAB: Settings
-- ----------------------------------------------------------------------------
local CfgTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })

-- Groupbox literally named "Menu": Airflow automatically adds its
-- "Minimize UI on Start" toggle to it (Window:SetMinimizeOnStart).
local MenuBox = CfgTab:CreateGroupbox({ Name = "Menu", Side = "Left" })
MenuBox:CreateDropdown({
    Name = "Toggle Button",
    Desc = "Floating button that reopens the UI",
    Options = { "Mobile only", "Both", "Off" },
    CurrentOption = { "Both" },
    Flag = "AZ_ToggleBtn",
    Callback = function(list)
        local label = type(list) == "table" and list[1] or list
        pcall(function()
            if label == "Off" then
                Window:SetToggleButton(false)
            else
                Window:SetToggleButton(true)
                Window:SetToggleButtonPlatform(label == "Both" and "Both" or "Mobile")
            end
        end)
    end,
})
MenuBox:CreateToggle({
    Name = "Anti AFK", Flag = "AZ_AntiAFK", CurrentValue = false,
    Desc = "Stops the game from kicking you out for standing still too long",
    Callback = function(v) Hub.setAntiAfk(v) end,
})
MenuBox:CreateToggle({
    Name = "No Gameplay Paused", Flag = "AZ_NoPause", CurrentValue = false,
    Desc = "Removes the 'Gameplay Paused' box that pops up when the game lags while loading",
    Callback = function(v) Hub.setNoGameplayPaused(v) end,
})
MenuBox:CreateToggle({
    Name = "Auto Reconnect on Kick", Flag = "AZ_Reconnect", CurrentValue = false,
    Desc = "If you get disconnected or kicked, AZOTH joins the game again by itself",
    Callback = function(v) Hub.setAutoReconnect(v) end,
})
MenuBox:CreateToggle({
    Name = "Disable 3D Rendering", Flag = "AZ_NoRender", CurrentValue = false,
    Desc = "Turns off the 3D view for a big FPS boost while AFK - perfect for farming",
    Callback = function(v) Hub.setNoRender(v) end,
})
MenuBox:CreateToggle({
    Name = "Ultra FPS Boost", Flag = "AZ_FpsBoost", CurrentValue = false,
    Desc = "Lowers shadows, water and render quality (restored when turned off)",
    Callback = function(v) Hub.setFpsBoost(v) end,
})
MenuBox:CreateSlider({
    Name = "FPS Limit (0 = off)", Range = { 0, 240 }, Increment = 5, Suffix = " fps",
    CurrentValue = 0, Flag = "AZ_FpsLimit",
    Desc = "Caps your FPS at this number (0 = no cap)",
    Callback = function(v) Hub.setFpsLimit(v) end,
})
MenuBox:CreateToggle({
    Name = "Hide UI On Start", Flag = "AZ_HideUIStart", CurrentValue = false,
    Desc = "Start with the window hidden - open it again with the floating button. Works from the next time you run the script",
    Callback = function() end,
})
MenuBox:CreateToggle({
    Name = "Auto Execute", Flag = "AZ_AutoExec", CurrentValue = false,
    Desc = "Your choice. When ON, AZOTH starts by itself when you rejoin or reopen the game. When OFF, nothing starts on its own. Note: if it was already ON this session, one last auto start may still happen when you rejoin.",
    Callback = function(v)
        Hub.state.autoExecEnabled = v
        if v then
            Hub.armAutoExec()
        else
            Hub.state.autoExecArmed = false
            Hub.log("[Menu] Auto Execute OFF (will not re-arm next run).")
        end
    end,
})
MenuBox:CreateButton({
    Name = "Unload",
    Desc = "Stop everything, restore name/rendering and remove the UI",
    Style = "Danger",
    Callback = function() Hub.unload() end,
})

CfgTab:CreateThemeManager({ Side = "Right" })
CfgTab:CreateConfigManager({ Side = "Left" })

Window:LoadAutoload()

-- ----------------------------------------------------------------------------
-- 10. Boot
-- ----------------------------------------------------------------------------
if game.PlaceId ~= PLACE_ID then
    Hub.notify("AZOTH",
        "Different PlaceId (" .. tostring(game.PlaceId) .. "). Features may not match.",
        "Warning")
end
-- Saved-config driven startup switches (flags load via LoadAutoload above).
do
    local ae = Airflow.Flags and Airflow.Flags.AZ_AutoExec
    if ae and ae.Value then
        Hub.state.autoExecEnabled = true
        Hub.armAutoExec(true)
    end
    local hs = Airflow.Flags and Airflow.Flags.AZ_HideUIStart
    if hs and hs.Value then
        task.delay(0.5, function()
            pcall(function() Window:Toggle(false) end)
            Hub.log("[AZOTH] UI hidden on start (RightControl / floating button to reopen).")
        end)
    end
end
if LOGO then
    local src = (getgenv and getgenv().AZOTH_LOGO_SOURCE) or "local file"
    Hub.log("[AZOTH] Logo loaded (" .. src .. ").")
else
    Hub.log("[AZOTH] Logo FAILED to load (embedded + download + local all failed) - using default icon. This executor may lack writefile/getcustomasset.")
end
Hub.log("[AZOTH] v2.7 loaded. Engine = best move, Play = queue/bots/auto match, Settings = menu utilities.")
Hub.notify("AZOTH", "Loaded. Engine for best moves, Auto for the hands-free loop.", "Success")
end,
}
