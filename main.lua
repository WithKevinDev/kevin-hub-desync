repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()

local function findRN()
    for _, bag in ipairs({ _G, (getgenv and getgenv()) or nil }) do
        if type(bag) == "table" then
            for _, n in ipairs({ "raknet", "Raknet", "RakNet", "rnet" }) do
                local t = bag[n]
                if type(t) == "table" and type(t.add_send_hook) == "function" then
                    return t
                end
            end
        end
    end
    return nil
end

local RN = findRN()
local addSend = RN and type(RN.add_send_hook) == "function" and RN.add_send_hook
local remSend = RN and type(RN.remove_send_hook) == "function" and RN.remove_send_hook
local addRecv = RN and (RN.add_receive_hook or RN.add_recv_hook)
local remRecv = RN and (RN.remove_receive_hook or RN.remove_recv_hook)
local desyncFn = RN and type(RN.desync) == "function" and RN.desync
local hasRaknet = addSend ~= nil
local raknetOn = false
local sendHook, recvHook
local pktCount = 0

local function blockPacket(packet)
    pcall(function()
        if packet.Block then packet:Block()
        elseif packet.Drop then packet:Drop()
        elseif packet.Blocked ~= nil then packet.Blocked = true end
    end)
end

local function poison1B(packet)
    pcall(function()
        local buf = packet.AsBuffer
        if not buf then return end
        buffer.writeu32(buf, 1, 0xFFFFFFFF)
        pcall(function() buffer.writeu32(buf, 5, 0xFFFFFFFF) end)
        if packet.SetData then packet:SetData(buf) end
    end)
end

local stealthStrong = false

local function onSend(packet)
    if not raknetOn then return end
    local id = packet.PacketId
    if id == 0x1B then
        poison1B(packet)
        pktCount += 1
        if stealthStrong then blockPacket(packet) end
    elseif stealthStrong and (id == 0x85 or id == 0x86) then
        blockPacket(packet)
        pktCount += 1
    end
end

local function onRecv(packet)
    if not raknetOn then return end
    local id = packet.PacketId
    if id == 0x1B or id == 0x85 then
        blockPacket(packet)
        pktCount += 1
    end
end

local function raknetStart()
    if not hasRaknet or raknetOn then return false end
    sendHook = onSend
    local ok = pcall(function() addSend(sendHook) end)
    if not ok then sendHook = nil return false end
    if addRecv then
        recvHook = onRecv
        pcall(function() addRecv(recvHook) end)
    end
    if desyncFn then pcall(function() desyncFn(true) end) end
    raknetOn = true
    return true
end

local function raknetStop()
    if not raknetOn then return end
    if sendHook and remSend then pcall(function() remSend(sendHook) end) end
    if recvHook and remRecv then pcall(function() remRecv(recvHook) end) end
    if desyncFn then pcall(function() desyncFn(false) end) end
    sendHook, recvHook = nil, nil
    raknetOn = false
end

local desyncOn = false
local speed = 30
local basePos = Vector3.zero
local offset = Vector3.zero
local root, hum
local hb, rs, step
local savedWS = 16
local statusFn
local ghostFolder
local syncing = false
local closed = false
local allConnections = {}

local keybinds = {
    desync = Enum.KeyCode.Z,
    rebase = Enum.KeyCode.C,
    stealth = Enum.KeyCode.V
}
local listeningFor = nil

local function trackConn(c)
    table.insert(allConnections, c)
    return c
end

local function disconnectAll()
    for _, c in ipairs(allConnections) do
        pcall(function() c:Disconnect() end)
    end
    allConnections = {}
end

local function worldPos()
    local y = (root and root.Position.Y) or basePos.Y
    return Vector3.new(basePos.X + offset.X, y, basePos.Z + offset.Z)
end

local function clearGhost()
    if ghostFolder then pcall(function() ghostFolder:Destroy() end) end
    ghostFolder = nil
end

local function updateGhost()
    clearGhost()
    local f = Instance.new("Folder")
    f.Name = "_KevinGhost"
    f.Parent = workspace

    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Size = Vector3.new(3, 6, 3)
    p.Transparency = 0.55
    p.Color = Color3.fromRGB(255, 50, 50)
    p.Material = Enum.Material.Neon
    p.CFrame = CFrame.new(basePos)
    p.Parent = f

    local outline = Instance.new("SelectionBox")
    outline.Adornee = p
    outline.Color3 = Color3.fromRGB(255, 40, 40)
    outline.LineThickness = 0.06
    outline.Transparency = 0.3
    outline.SurfaceTransparency = 0.9
    outline.Parent = p

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(220, 44)
    bb.StudsOffset = Vector3.new(0, 3.8, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Parent = p

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text = "WHAT PLAYERS SEE"
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextSize = 16
    lbl.TextColor3 = Color3.fromRGB(255, 235, 235)
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3 = Color3.fromRGB(120, 10, 10)
    lbl.Parent = bb

    local lblGrad = Instance.new("UIGradient", lbl)
    lblGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 210)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 120)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 210, 210))
    })

    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxassetid://243660364"
    particles.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 30, 30))
    })
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.2, 0.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.3, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Lifetime = NumberRange.new(0.8, 1.4)
    particles.Rate = 40
    particles.Speed = NumberRange.new(2, 5)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.LightEmission = 0.6
    particles.Parent = p

    ghostFolder = f
end

local function zeroVel(r)
    if not r then return end
    pcall(function()
        local y = r.AssemblyLinearVelocity.Y
        r.AssemblyLinearVelocity = Vector3.new(0, y, 0)
        r.Velocity = Vector3.new(0, y, 0)
        r.AssemblyAngularVelocity = Vector3.zero
        r.RotVelocity = Vector3.zero
    end)
end

local function hardSet(r, pos)
    if not r then return end
    r.CFrame = CFrame.new(pos)
    zeroVel(r)
end

local function assertReal()
    if not root or syncing then return end
    hardSet(root, worldPos())
end

local function preferClient(r)
    if not r then return end
    pcall(function() r:SetNetworkOwner(LP) end)
    if typeof(sethiddenproperty) == "function" then
        pcall(function() sethiddenproperty(r, "PhysicsRepRootPart", r) end)
    end
end

local function getDir()
    if hum and hum.MoveDirection.Magnitude > 0.05 then
        local md = hum.MoveDirection
        return Vector3.new(md.X, 0, md.Z).Unit
    end
    local cam = workspace.CurrentCamera
    local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
    local right = cam and cam.CFrame.RightVector or Vector3.new(1, 0, 0)
    look = Vector3.new(look.X, 0, look.Z)
    right = Vector3.new(right.X, 0, right.Z)
    if look.Magnitude > 1e-3 then look = look.Unit end
    if right.Magnitude > 1e-3 then right = right.Unit end
    local d = Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then d += look end
    if UIS:IsKeyDown(Enum.KeyCode.S) then d -= look end
    if UIS:IsKeyDown(Enum.KeyCode.A) then d -= right end
    if UIS:IsKeyDown(Enum.KeyCode.D) then d += right end
    if d.Magnitude > 1e-3 then return d.Unit end
    return Vector3.zero
end

local function rebaseGhost()
    if not root then return end
    local p = root.Position
    basePos = Vector3.new(p.X, p.Y, p.Z)
    offset = Vector3.zero
    updateGhost()
end

local function bind(char)
    if not char then return end
    root = char:FindFirstChild("HumanoidRootPart")
    hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end
    savedWS = (hum.WalkSpeed > 1 and hum.WalkSpeed) or 16
    basePos = root.Position
    offset = Vector3.zero
    hum.WalkSpeed = 0
    hum.AutoRotate = false
    preferClient(root)
    zeroVel(root)
    updateGhost()
end

local function startDesync()
    if closed or desyncOn then return end
    desyncOn = true
    bind(LP.Character)
    pktCount = 0

    local stealth = raknetStart()
    preferClient(root)

    if hb then hb:Disconnect() end
    if rs then rs:Disconnect() end
    if step then step:Disconnect() end

    hb = RunService.Heartbeat:Connect(function(dt)
        if not desyncOn or syncing then return end
        if not root or not root.Parent or not hum or not hum.Parent then
            bind(LP.Character)
            preferClient(root)
            return
        end

        local dir = getDir()
        if dir.Magnitude > 0 then
            offset = offset + dir * (speed * dt)
        end

        assertReal()
        preferClient(root)

        if hum.PlatformStand then hum.PlatformStand = false end
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        end
        hum.WalkSpeed = 0
    end)

    rs = RunService.RenderStepped:Connect(function()
        if not desyncOn or syncing or not root then return end
        assertReal()
    end)

    step = RunService.Stepped:Connect(function()
        if not desyncOn or syncing or not root then return end
        zeroVel(root)
        assertReal()
        if hum then hum.WalkSpeed = 0 end
    end)

    if statusFn then pcall(statusFn) end
end

local function stopDesync()
    if not desyncOn then return end
    syncing = true
    raknetStop()

    local r = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if r then
        local target = worldPos()
        preferClient(r)
        for _ = 1, 3 do
            hardSet(r, target)
            RunService.Heartbeat:Wait()
        end
    end

    desyncOn = false
    syncing = false
    if hb then hb:Disconnect() hb = nil end
    if rs then rs:Disconnect() rs = nil end
    if step then step:Disconnect() step = nil end

    if hum then
        hum.WalkSpeed = savedWS
        hum.AutoRotate = true
    end
    offset = Vector3.zero
    clearGhost()
    if statusFn then pcall(statusFn) end
end

trackConn(LP.CharacterAdded:Connect(function(c)
    task.wait(0.25)
    if closed then return end
    if desyncOn then
        bind(c)
        preferClient(root)
        if not raknetOn then raknetStart() end
    end
end))

local function parentGui(gui)
    pcall(function() if gethui then gui.Parent = gethui() end end)
    if not gui.Parent then pcall(function() gui.Parent = game:GetService("CoreGui") end) end
    if not gui.Parent then pcall(function() gui.Parent = LP:WaitForChild("PlayerGui") end) end
end

pcall(function()
    for _, n in ipairs({"KevinHub", "KevinDesyncGUI", "KevinDesyncDiag"}) do
        pcall(function() if gethui then local x = gethui():FindFirstChild(n) if x then x:Destroy() end end end)
        pcall(function() local x = game:GetService("CoreGui"):FindFirstChild(n) if x then x:Destroy() end end)
        pcall(function() local pg = LP:FindFirstChild("PlayerGui") if pg then local x = pg:FindFirstChild(n) if x then x:Destroy() end end end)
    end
end)

local mobile = UIS.TouchEnabled
local W = mobile and 280 or 260
local H = mobile and 210 or 195

local sg = Instance.new("ScreenGui")
sg.Name = "KevinHub"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 1000
parentGui(sg)

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(W, H)
frame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
frame.BackgroundColor3 = Color3.fromRGB(35, 20, 20)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.Parent = sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(220, 60, 60)
stroke.Thickness = 1.5

local gradient = Instance.new("UIGradient", frame)
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 25, 25)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 15, 15))
})
gradient.Rotation = 45

local glow = Instance.new("ImageLabel", frame)
glow.Size = UDim2.new(1, 60, 1, 60)
glow.Position = UDim2.fromOffset(-30, -30)
glow.BackgroundTransparency = 1
glow.Image = "rbxassetid://5028857084"
glow.ImageColor3 = Color3.fromRGB(255, 80, 80)
glow.ImageTransparency = 0.75
glow.ZIndex = 0

local fxHolder = Instance.new("Frame", frame)
fxHolder.Size = UDim2.new(1, 0, 1, 0)
fxHolder.BackgroundTransparency = 1
fxHolder.ClipsDescendants = true
fxHolder.ZIndex = 2

local embers = {}
for i = 1, 22 do
    local ember = Instance.new("Frame", fxHolder)
    local size = math.random(2, 4)
    ember.Size = UDim2.fromOffset(size, size)
    ember.BackgroundColor3 = Color3.fromRGB(255, math.random(80, 160), math.random(40, 80))
    ember.BackgroundTransparency = math.random(20, 60) / 100
    ember.BorderSizePixel = 0
    ember.ZIndex = 2
    Instance.new("UICorner", ember).CornerRadius = UDim.new(1, 0)

    local startX = math.random(0, W)
    local startY = math.random(0, H)
    ember.Position = UDim2.fromOffset(startX, startY)

    table.insert(embers, {
        frame = ember,
        speed = math.random(15, 45),
        drift = math.random(-6, 6) / 10,
        x = startX,
        y = startY,
        phase = math.random() * math.pi * 2
    })
end

local fxConn
fxConn = RunService.RenderStepped:Connect(function(dt)
    if not frame.Parent then fxConn:Disconnect() return end
    local t = tick()
    for _, e in ipairs(embers) do
        if not e.frame.Parent then continue end
        e.y = e.y - e.speed * dt
        e.x = e.x + math.sin(t * 2 + e.phase) * e.drift

        if e.y < -10 then
            e.y = H + 10
            e.x = math.random(0, W)
        end
        if e.x < -10 then e.x = W + 5 end
        if e.x > W + 10 then e.x = -5 end

        local flicker = 0.7 + math.sin(t * 8 + e.phase) * 0.3
        e.frame.BackgroundTransparency = 1 - flicker * 0.7
        e.frame.Position = UDim2.fromOffset(e.x, e.y)
    end
end)
trackConn(fxConn)

local function closeUI()
    if closed then return end
    closed = true

    if desyncOn then stopDesync() end
    raknetStop()
    clearGhost()

    if hum then
        pcall(function()
            hum.WalkSpeed = savedWS
            hum.AutoRotate = true
        end)
    end

    disconnectAll()

    local tween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0)
    })
    tween:Play()
    tween.Completed:Connect(function()
        pcall(function() sg:Destroy() end)
    end)
end

do
    local drag, a, b
    trackConn(frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            drag = true; a = input.Position; b = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then drag = false end
            end)
        end
    end))
    trackConn(UIS.InputChanged:Connect(function(input)
        if not drag then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - a
            frame.Position = UDim2.new(b.X.Scale, b.X.Offset + d.X, b.Y.Scale, b.Y.Offset + d.Y)
        end
    end))
end

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -50, 0, 28)
title.Position = UDim2.fromOffset(12, 4)
title.BackgroundTransparency = 1
title.Text = "KEVIN DESYNC"
title.Font = Enum.Font.GothamBlack
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 90, 90)
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 3

local titleGradient = Instance.new("UIGradient", title)
titleGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 30, 30))
})
titleGradient.Rotation = 0

local closeBtn = Instance.new("TextButton", frame)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 45, 45)
closeBtn.Text = "x"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 3
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 7)

local closeStroke = Instance.new("UIStroke", closeBtn)
closeStroke.Color = Color3.fromRGB(255, 110, 110)
closeStroke.Thickness = 1

trackConn(closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(255, 60, 60)}):Play()
end))
trackConn(closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(200, 45, 45)}):Play()
end))
trackConn(closeBtn.MouseButton1Click:Connect(closeUI))

local function makeRow(y, height, color, strokeColor)
    local b = Instance.new("TextButton", frame)
    b.Size = UDim2.new(1, -60, 0, height)
    b.Position = UDim2.fromOffset(12, y)
    b.BackgroundColor3 = color
    b.Text = ""
    b.AutoButtonColor = false
    b.ZIndex = 3
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", b)
    s.Color = strokeColor
    s.Thickness = 1
    local g = Instance.new("UIGradient", b)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(
            math.min(color.R * 255 + 40, 255),
            math.min(color.G * 255 + 30, 255),
            math.min(color.B * 255 + 30, 255)
        )),
        ColorSequenceKeypoint.new(1, color)
    })
    g.Rotation = 90

    local lbl = Instance.new("TextLabel", b)
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text = ""
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.ZIndex = 4

    local kb = Instance.new("TextButton", frame)
    kb.Size = UDim2.fromOffset(40, height)
    kb.Position = UDim2.new(1, -48, 0, y)
    kb.BackgroundColor3 = Color3.fromRGB(90, 25, 25)
    kb.Text = ""
    kb.AutoButtonColor = false
    kb.ZIndex = 3
    Instance.new("UICorner", kb).CornerRadius = UDim.new(0, 8)
    local ks = Instance.new("UIStroke", kb)
    ks.Color = Color3.fromRGB(255, 90, 90)
    ks.Thickness = 1

    local klbl = Instance.new("TextLabel", kb)
    klbl.Size = UDim2.fromScale(1, 1)
    klbl.BackgroundTransparency = 1
    klbl.Text = ""
    klbl.Font = Enum.Font.GothamBold
    klbl.TextSize = 12
    klbl.TextColor3 = Color3.fromRGB(255, 170, 170)
    klbl.ZIndex = 4

    return b, lbl, kb, klbl, s, ks
end

local desyncBtn, desyncLbl, desyncKb, desyncKlbl, desyncStroke = makeRow(40, mobile and 40 or 36, Color3.fromRGB(180, 40, 40), Color3.fromRGB(255, 100, 100))
local rebaseBtn, rebaseLbl, rebaseKb, rebaseKlbl, rebaseStroke = makeRow(86, mobile and 36 or 32, Color3.fromRGB(140, 35, 35), Color3.fromRGB(255, 90, 90))

local status = Instance.new("TextLabel", frame)
status.Size = UDim2.new(1, -24, 0, 36)
status.Position = UDim2.fromOffset(12, 126)
status.BackgroundTransparency = 1
status.Text = "Ready"
status.Font = Enum.Font.GothamBold
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(255, 170, 170)
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.ZIndex = 3

local watermark = Instance.new("TextButton", frame)
watermark.Size = UDim2.new(1, 0, 0, 20)
watermark.Position = UDim2.new(0, 0, 1, -22)
watermark.BackgroundTransparency = 1
watermark.Text = "discord.gg/luascript"
watermark.Font = Enum.Font.GothamBold
watermark.TextSize = 12
watermark.TextColor3 = Color3.fromRGB(255, 110, 110)
watermark.ZIndex = 5
watermark.AutoButtonColor = false

local wmGradient = Instance.new("UIGradient", watermark)
wmGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 140)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 90)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 140))
})

task.spawn(function()
    local t = 0
    while watermark.Parent and not closed do
        t = t + task.wait(0.03)
        wmGradient.Offset = Vector2.new(math.sin(t * 2) * 0.3, 0)
    end
end)

trackConn(watermark.MouseEnter:Connect(function()
    TweenService:Create(watermark, TweenInfo.new(0.15), {TextColor3 = Color3.fromRGB(255, 200, 200)}):Play()
end))
trackConn(watermark.MouseLeave:Connect(function()
    TweenService:Create(watermark, TweenInfo.new(0.15), {TextColor3 = Color3.fromRGB(255, 110, 110)}):Play()
end))

trackConn(watermark.MouseButton1Click:Connect(function()
    local ok = pcall(function()
        if setclipboard then
            setclipboard("discord.gg/luascript")
        elseif toclipboard then
            toclipboard("discord.gg/luascript")
        end
    end)
    local old = watermark.Text
    watermark.Text = ok and "copied!" or "discord.gg/luascript"
    task.delay(1.2, function()
        if watermark.Parent then watermark.Text = old end
    end)
end))

local pulseConn
local function pulseButton(btn)
    if pulseConn then pulseConn:Disconnect() end
    local t = 0
    pulseConn = RunService.RenderStepped:Connect(function(dt)
        if not btn.Parent then pulseConn:Disconnect() return end
        t = t + dt
        local a = (math.sin(t * 4) + 1) / 2
        btn.BackgroundTransparency = 0.15 * a
    end)
end
local function stopPulse(btn)
    if pulseConn then pulseConn:Disconnect() pulseConn = nil end
    btn.BackgroundTransparency = 0
end

local function keyName(k)
    return k and k.Name or "?"
end

statusFn = function()
    if closed then return end
    if desyncOn then
        desyncLbl.Text = "Desync: ON"
        desyncBtn.BackgroundColor3 = Color3.fromRGB(220, 45, 45)
        desyncStroke.Color = Color3.fromRGB(255, 140, 140)
        pulseButton(desyncBtn)
        local st = hasRaknet and (raknetOn and ("RakNet ON pkts " .. pktCount) or "RakNet fail") or "No RakNet"
        status.Text = string.format("Hitbox = REAL body\n%s · stealth %s", st, stealthStrong and "STRONG" or "NORMAL")
        status.TextColor3 = Color3.fromRGB(255, 190, 190)
        stroke.Color = Color3.fromRGB(255, 90, 90)
        TweenService:Create(glow, TweenInfo.new(0.4), {ImageTransparency = 0.55}):Play()
    else
        desyncLbl.Text = "Desync: OFF"
        desyncBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        desyncStroke.Color = Color3.fromRGB(255, 100, 100)
        stopPulse(desyncBtn)
        status.Text = hasRaknet and "RakNet found — stealth possible" or "No RakNet — players may still see you"
        status.TextColor3 = Color3.fromRGB(255, 170, 170)
        stroke.Color = Color3.fromRGB(220, 60, 60)
        TweenService:Create(glow, TweenInfo.new(0.4), {ImageTransparency = 0.75}):Play()
    end
    rebaseLbl.Text = "REBASE GHOST"
    desyncKlbl.Text = keyName(keybinds.desync)
    rebaseKlbl.Text = keyName(keybinds.rebase)
end

trackConn(desyncBtn.MouseButton1Click:Connect(function()
    if desyncOn then stopDesync() else startDesync() end
end))
trackConn(rebaseBtn.MouseButton1Click:Connect(function()
    if desyncOn then rebaseGhost() end
end))

local function startListen(action, kbLabel)
    if listeningFor then return end
    listeningFor = action
    kbLabel.Text = "..."
    kbLabel.TextColor3 = Color3.fromRGB(255, 255, 120)
    task.delay(3, function()
        if listeningFor == action then
            listeningFor = nil
            if statusFn then pcall(statusFn) end
        end
    end)
end

trackConn(desyncKb.MouseButton1Click:Connect(function()
    startListen("desync", desyncKlbl)
end))
trackConn(rebaseKb.MouseButton1Click:Connect(function()
    startListen("rebase", rebaseKlbl)
end))

trackConn(UIS.InputBegan:Connect(function(inp, gpe)
    if gpe or closed then return end

    if listeningFor then
        keybinds[listeningFor] = inp.KeyCode
        listeningFor = nil
        if statusFn then pcall(statusFn) end
        return
    end

    if inp.KeyCode == keybinds.desync then
        if desyncOn then stopDesync() else startDesync() end
    elseif inp.KeyCode == keybinds.rebase then
        if desyncOn then rebaseGhost() end
    elseif inp.KeyCode == keybinds.stealth then
        stealthStrong = not stealthStrong
        if statusFn then pcall(statusFn) end
    end
end))

local function btnPressAnim(btn)
    trackConn(btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {Size = UDim2.new(1, -64, 0, btn.Size.Y.Offset - 2)}):Play()
    end))
    trackConn(btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {Size = UDim2.new(1, -60, 0, btn.Size.Y.Offset + 2)}):Play()
    end))
end
btnPressAnim(desyncBtn)
btnPressAnim(rebaseBtn)

local openAnim = TweenService:Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(W, H)
})
frame.Size = UDim2.fromOffset(0, 0)
openAnim:Play()

statusFn()
task.spawn(function()
    while sg and sg.Parent and not closed do
        task.wait(0.5)
        if desyncOn and statusFn then pcall(statusFn) end
    end
end)
