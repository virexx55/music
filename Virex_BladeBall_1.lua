task.spawn(function()  
  
-- ===== VIREX loading screen: el panel y los botones solo aparecen al llegar a 100% =====
do
	local G = getgenv()
	G.VIREX_Loaded = false
	G.VIREX_Loader_Active = false
	G.VIREX_BypassReady = false -- al volver a ejecutar, el bypass se vuelve a pedir
	G.VIREX_NewsShown = false
	G.VIREX_HintShown = false
	G.VIREX_BypassSplashShown = false -- (se quedaba guardado y no volvia a salir)
	G.VIREX_BypassImg = nil
	G.VIREX_BypassHD = nil
	G.VIREX_LoadSet = function() end
	-- carga una imagen por id probando varias formas (Image, Decal, miniatura) hasta que una cargue
	G.VIREX_ResolveImage = function(id, target, apply, onFail)
		task.spawn(function()
			local CP = game:GetService("ContentProvider")
			local function loaded(c)
				apply(c)
				local ok = false
				pcall(function()
					CP:PreloadAsync({ target }, function(_, st)
						if st == Enum.AssetFetchStatus.Success then ok = true end
					end)
				end)
				if not ok then pcall(function() ok = target.IsLoaded == true end) end
				return ok
			end
			id = tostring(id)
			if loaded("rbxassetid://" .. id) then return end
			-- si es un Decal: sacar la imagen real que lleva dentro
			local got
			task.spawn(function()
				pcall(function()
					local objs = game:GetObjects("rbxassetid://" .. id)
					local o = objs and objs[1]
					if o then
						if o:IsA("Decal") or o:IsA("Texture") then got = o.Texture
						elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then got = o.Image end
						pcall(function() o:Destroy() end)
					end
				end)
				got = got or false
			end)
			local t0 = os.clock()
			while got == nil and os.clock() - t0 < 3 do task.wait(0.05) end
			if type(got) == "string" and got ~= "" and loaded(got) then return end
			-- no cargo: NO se usa la miniatura de Roblox (en algunos dispositivos sale el gris con el logo de Roblox)
			pcall(apply, "")
			if onFail then pcall(onFail) end
		end)
	end
	-- imagen desde un enlace directo (catbox): se descarga una vez, se guarda en VIREX/ y se carga en HD
	G.VIREX_UrlImage = function(url, target, apply, onFail)
		task.spawn(function()
			local ok = false
			pcall(function()
				local custom = getcustomasset or getsynasset
				if not (custom and writefile and isfile) then return end
				-- solo se acepta si de verdad es una imagen (no una pagina de error)
				local function isImage(d)
					return type(d) == "string" and #d > 1000 and (d:sub(1, 4) == "\137PNG" or d:sub(1, 2) == "\255\216" or d:sub(1, 4) == "RIFF")
				end
				local name = tostring(url):match("([%w_%-]+%.%w+)$") or "img.png"
				local path = "VIREX/" .. name
				pcall(function() if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end end)
				local function fileOk()
					local has = false
					pcall(function() has = isfile(path) end)
					if has and readfile then
						local okr, d = pcall(readfile, path)
						if okr and not isImage(d) then
							pcall(function() if delfile then delfile(path) end end) -- archivo roto: se borra
							has = false
						end
					end
					return has
				end
				local function download()
					for _ = 1, 2 do
						local okh, data = pcall(function() return game:HttpGet(url) end)
						if okh and isImage(data) then
							pcall(writefile, path, data)
							return true
						end
						task.wait(0.5)
					end
					return false
				end
				if not fileOk() then download() end
				if not fileOk() then return end
				local c = custom(path)
				if type(c) ~= "string" or c == "" then return end
				apply(c)
				-- comprobar que de verdad se ve (max 6 s)
				local loaded = false
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ target }, function(_, st)
						if st == Enum.AssetFetchStatus.Success then loaded = true end
					end)
				end)
				local t0 = os.clock()
				while not loaded and os.clock() - t0 < 6 do
					pcall(function() loaded = target.IsLoaded == true end)
					if loaded then break end
					task.wait(0.1)
				end
				if loaded then
					ok = true
				else
					pcall(function() if delfile then delfile(path) end end) -- no cargo: la proxima vez se descarga de nuevo
				end
			end)
			if not ok and onFail then pcall(onFail) end
		end)
	end
	G.VIREX_LoadDone = function() G.VIREX_Loaded = true end
	pcall(function()
		local TS = game:GetService("TweenService")
		local RS = game:GetService("RunService")
		local parent
		pcall(function() if gethui then parent = gethui() end end)
		if not parent then
			pcall(function()
				local t = Instance.new("Folder")
				t.Parent = game:GetService("CoreGui")
				t:Destroy()
				parent = game:GetService("CoreGui")
			end)
		end
		if not parent then parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end
		local old = parent:FindFirstChild("VIREX_Loader")
		if old then old:Destroy() end

		local gui = Instance.new("ScreenGui")
		gui.Name = "VIREX_Loader"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 500
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = parent

		-- ===== CARGA VIREX: foto "wait for it to load" + barra de cuadrados (16 s, sin skip) =====
		local INTRO_IMAGE = 89584936796953
		local INTRO_MUSIC = tonumber(G.VIREX_IntroMusicId) or 109356844790520 -- id de la cancion (16 s)
		local INTRO_MUSIC_FILE = "VIREX/intro_cwwpfn.mp3" -- se guarda aqui tras descargarlo (cambia el nombre si cambias de cancion)
		local DURATION = 10
		local IMG_RATIO = 1684 / 934
		local WHITE = Color3.new(1, 1, 1)
		local BLACK = Color3.new(0, 0, 0)
		local PIXEL = Enum.Font.Arcade

		local function tw(o, t, props, style, dir, rep, rev)
			local tn = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, rep or 0, rev or false), props)
			tn:Play()
			return tn
		end
		local function mk(class, props)
			local o = Instance.new(class)
			for k2, v in pairs(props) do if k2 ~= "Parent" then o[k2] = v end end
			if props.Parent then o.Parent = props.Parent end
			return o
		end

		local back = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0, BorderSizePixel = 0, Active = true, Parent = gui })
		local view = gui.AbsoluteSize
		if view.X < 10 then view = Vector2.new(1280, 720) end

		-- foto arriba
		local IW = math.min(view.X * 0.82, view.Y * 0.8 * IMG_RATIO)
		local IH = IW / IMG_RATIO
		local IMG_Y = 0 -- centrada (sin barra)
		local photo = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, IMG_Y), Size = UDim2.fromOffset(IW, IH), BackgroundTransparency = 1, Parent = back })
		local photoSc = mk("UIScale", { Scale = 0.97, Parent = photo })
		local img = mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ImageTransparency = 0, ZIndex = 2, Parent = photo })
		local mask -- (se crea justo despues)
		-- respaldo si la foto no carga: la frase escrita en rojo neon, inclinada como la foto
		local function textFallback()
			img.Visible = false
			local holder = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.42), BackgroundTransparency = 1, Rotation = -12, ZIndex = 2, Parent = photo })
			local function line(z, strokeT, strokeW, textT)
				local t = mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Kalam, Text = "wait for it to load", TextScaled = true, TextColor3 = Color3.fromRGB(255, 40, 40), TextTransparency = textT, ZIndex = z, Parent = holder })
				mk("UIStroke", { Color = Color3.fromRGB(255, 40, 40), Thickness = strokeW, Transparency = strokeT, Parent = t })
				local m2 = mask:Clone()
				m2.Parent = t
				task.spawn(function()
					-- sigue la misma mascara que la foto (se escribe a mano)
					while t.Parent do
						m2.Offset = mask.Offset
						t.TextTransparency = textT + img.ImageTransparency * 0.6
						task.wait()
					end
				end)
				return t
			end
			line(2, 0.86, 8, 0.6) -- brillo
			line(3, 0.4, 1.5, 0)  -- texto
		end
		-- "se escribe a mano": una mascara revela la frase siguiendo su inclinacion
		mask = mk("UIGradient", { Rotation = -12, Offset = Vector2.new(-0.72, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.46, 0), NumberSequenceKeypoint.new(0.54, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = img })
		G.VIREX_UrlImage("https://files.catbox.moe/5xdkb1.png", img, function(c) img.Image = c end, function()
			G.VIREX_ResolveImage(INTRO_IMAGE, img, function(a) img.Image = a end, textFallback)
		end)
		-- lineas VHS muy suaves + franja de escaneo
		local scan = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, IMG_Y), Size = UDim2.new(1, 0, 0, IH * 1.1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 4, Parent = back })
		for i = 0, math.clamp(math.floor(IH * 1.1 / 4), 20, 200) - 1 do
			mk("Frame", { Position = UDim2.fromOffset(0, i * 4), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 4, Parent = scan })
		end
		local band = mk("Frame", { Position = UDim2.new(0, 0, 0, -40), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = WHITE, BackgroundTransparency = 0.96, BorderSizePixel = 0, ZIndex = 5, Parent = scan })
		mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = band })

		-- barra retro de cuadrados debajo de la foto (diseño base 620 px, se escala)
		local BW, BHt, INSET, NSQ, GAP = 620, 58, 9, 20, 6
		local stage = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, IMG_Y + IH * 0.29), Size = UDim2.fromOffset(BW, 100), BackgroundTransparency = 1, ZIndex = 6, Parent = back })
		local stageSc = mk("UIScale", { Scale = math.clamp(IW * 0.6 / BW, 0.5, 2.6), Parent = stage })
		local barGroup = mk("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 6, Parent = stage })
		stage.Visible = false -- (sin barra: solo la foto)
		local barPop = mk("UIScale", { Scale = 0.9, Parent = barGroup })
		local bar = mk("Frame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(BW, BHt), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 6, Parent = barGroup })
		mk("UICorner", { CornerRadius = UDim.new(0, 14), Parent = bar })
		mk("UIStroke", { Color = WHITE, Thickness = 5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = bar })
		local innerW = BW - INSET * 2
		local sqW = (innerW - GAP * (NSQ - 1)) / NSQ
		local squares = {}
		for i = 1, NSQ do
			local sq = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(INSET + (i - 1) * (sqW + GAP) + sqW / 2, BHt / 2), Size = UDim2.fromOffset(sqW, BHt - INSET * 2), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7, Parent = bar })
			mk("UICorner", { CornerRadius = UDim.new(0, 3), Parent = sq })
			squares[i] = { f = sq, sc = mk("UIScale", { Parent = sq }) }
		end
		local mainTxt = mk("TextLabel", { Position = UDim2.fromOffset(2, BHt + 14), Size = UDim2.fromOffset(BW - 140, 28), BackgroundTransparency = 1, Font = PIXEL, Text = "LOADING", TextSize = 28, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = barGroup })
		local pct = mk("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, BHt + 14), Size = UDim2.fromOffset(130, 28), BackgroundTransparency = 1, Font = PIXEL, Text = "0%", TextSize = 28, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = barGroup })
		local status = mk("TextLabel", { Visible = false, Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Text = "", Parent = barGroup })

		local shown = 0
		local function setProgress(a)
			local n = math.floor(a * NSQ + 1e-4)
			if n > shown then
				for i = shown + 1, n do
					local s = squares[i]
					s.f.BackgroundTransparency = 0
					s.sc.Scale = 0.35
					tw(s.sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				end
				shown = n
			end
			pct.Text = tostring(math.floor(a * 100 + 0.5)) .. "%"
		end
		setProgress(0)

		local exiting, done = false, false
		-- musica: el audio subido a Roblox no suena en Blade Ball (privacidad de audio),
		-- asi que se usa el mp3 desde el executor. Si no esta, se descarga una vez del enlace.
		local INTRO_MUSIC_URL = tostring(G.VIREX_IntroMusicURL or "https://files.catbox.moe/cwwpfn.mp3") -- enlace directo al mp3
		local music = Instance.new("Sound")
		music.Name = "VIREX_IntroMusic"
		music.Volume = 0
		music.Looped = false
		music.Parent = game:GetService("SoundService")
		-- silencia todo el sonido del juego mientras dura la intro
		local muted, muteConns = {}, {}
		local function muteObj(o)
			if o == music or muted[o] ~= nil then return end
			if o:IsA("Sound") or o:IsA("SoundGroup") then
				local ok, v = pcall(function() return o.Volume end)
				if ok and type(v) == "number" and v > 0 then
					muted[o] = v
					pcall(function() o.Volume = 0 end)
				end
			end
		end
		local function muteAll()
			for _, svc in ipairs({ game:GetService("SoundService"), workspace, game:GetService("Players").LocalPlayer }) do
				pcall(function()
					for _, d in ipairs(svc:GetDescendants()) do muteObj(d) end
					muteConns[#muteConns + 1] = svc.DescendantAdded:Connect(function(d)
						if not exiting then task.defer(muteObj, d) end
					end)
				end)
			end
		end
		local function unmuteAll()
			for _, c in ipairs(muteConns) do pcall(function() c:Disconnect() end) end
			muteConns = {}
			for o, v in pairs(muted) do
				pcall(function() TS:Create(o, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Volume = v }):Play() end)
			end
			muted = {}
		end
		pcall(muteAll)
		task.spawn(function()
			pcall(function()
				local custom = getcustomasset or getsynasset
				local has = false
				pcall(function() has = isfile and isfile(INTRO_MUSIC_FILE) end)
				if not has and INTRO_MUSIC_URL ~= "" and writefile then
					pcall(function() if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end end)
					local ok, data = pcall(function() return game:HttpGet(INTRO_MUSIC_URL) end)
					if ok and type(data) == "string" and #data > 20000 then
						pcall(writefile, INTRO_MUSIC_FILE, data)
						pcall(function() has = isfile(INTRO_MUSIC_FILE) end)
					end
				end
				local id = ""
				if has and custom then
					pcall(function() id = custom(INTRO_MUSIC_FILE) end)
				end
				if id == "" and INTRO_MUSIC and INTRO_MUSIC > 0 then id = "rbxassetid://" .. tostring(INTRO_MUSIC) end
				if id == "" or exiting then return end
				music.SoundId = id
				task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync({ music }) end) end)
				local w0 = os.clock()
				while not music.IsLoaded and os.clock() - w0 < 2 do task.wait(0.05) end
				if not music.Parent or exiting then return end
				music.TimePosition = 0
				music:Play()
				tw(music, 0.6, { Volume = 1 }, Enum.EasingStyle.Quad)
				task.wait(3)
				if music.Parent and (not music.IsLoaded or music.TimeLength == 0) then
					warn("[VIREX] La musica de la intro no cargo. Pon el mp3 en la carpeta del executor: " .. INTRO_MUSIC_FILE)
				end
			end)
		end)

		-- secuencia
		local t0 = os.clock()
		tw(photoSc, DURATION, { Scale = 1.02 }, Enum.EasingStyle.Linear)
		task.spawn(function()
			-- espera a que la foto cargue (max 5 s) y luego se "escribe"
			task.wait(0.4)
			local w0 = os.clock()
			while os.clock() - w0 < 5 do
				local ok = false
				pcall(function() ok = img.IsLoaded == true end)
				if ok then break end
				task.wait(0.1)
			end
			tw(mask, 3.2, { Offset = Vector2.new(0.72, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end)
		task.delay(1.6, function()
			tw(barGroup, 0.5, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
			tw(barPop, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		-- como una tele / letrero: cada pocos segundos se apaga suave y vuelve a encenderse con dos destellos
		task.spawn(function()
			local rnd = Random.new()
			task.wait(4)
			while gui.Parent and not exiting do
				task.wait(rnd:NextNumber(2.6, 3.6))
				if exiting then break end
				-- se apaga
				tw(img, 0.22, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.wait(0.22 + rnd:NextNumber(0.25, 0.4))
				if exiting then break end
				-- vuelve: dos destellos rapidos y se queda encendida
				img.ImageTransparency = 0.2
				task.wait(0.05)
				img.ImageTransparency = 0.85
				task.wait(0.07)
				img.ImageTransparency = 0.1
				task.wait(0.04)
				img.ImageTransparency = 0.7
				task.wait(0.06)
				if exiting then break end
				tw(img, 0.25, { ImageTransparency = 0 }, Enum.EasingStyle.Quad)
			end
		end)
		task.spawn(function()
			while gui.Parent and not exiting do
				band.Position = UDim2.new(0, 0, 0, -40)
				tw(band, 2.6, { Position = UDim2.new(0, 0, 1, 0) }, Enum.EasingStyle.Linear)
				task.wait(3.4)
			end
		end)

		G.VIREX_LoadSet = function() end
		local conn
		conn = RS.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - t0) / DURATION, 0, 1)
			if not done then a = math.min(a, 0.97) end
			setProgress(a)
			mainTxt.Text = "LOADING" .. string.rep(".", math.floor(os.clock() * 2.5) % 4)
		end)

		G.VIREX_LoadDone = function()
			if done then return end
			done = true
			task.spawn(function()
				-- la carga dura 16 s aunque el script termine antes
				while os.clock() - t0 < DURATION - 1.1 do task.wait(0.05) end
				if music then tw(music, 1.1, { Volume = 0 }, Enum.EasingStyle.Quad) end
				pcall(unmuteAll) -- vuelve el sonido del juego
				while os.clock() - t0 < DURATION do task.wait(0.05) end
				exiting = true
				if conn then conn:Disconnect() end
				setProgress(1)
				mainTxt.Text = "COMPLETE"
				tw(barGroup, 0.4, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
				tw(barPop, 0.4, { Scale = 1.06 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				tw(img, 0.6, { ImageTransparency = 1 }, Enum.EasingStyle.Quad)
				tw(photoSc, 0.7, { Scale = 1.08 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				task.wait(0.45)
				scan.Visible = false
				tw(back, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				G.VIREX_Loaded = true -- el panel se abre aqui
				task.wait(0.8)
				if music then pcall(function() music:Stop() music:Destroy() end) end
				gui:Destroy()
			end)
		end
		task.delay(DURATION + 4, function() pcall(unmuteAll) end) -- seguro
		task.delay(DURATION + 2, function() pcall(function() if music and music.Parent and done then music:Destroy() end end) end)
		task.delay(90, function() G.VIREX_LoadDone() end) -- seguro por si algo falla
		G.VIREX_Loader_Active = true
	end)
end

local Library = (function()
---------------------------------------------------------------------------
-- VIREX UI v3  (escrita desde cero, blanco y negro)
-- Pestañas arriba, grupos en 2 columnas con filas, ajustes que se despliegan
-- debajo de cada funcion. Misma API: _new / create_category / create_tab /
-- create_group / create_toggle / create_slider / create_dropdown /
-- create_button / create_textbox / create_keybind / link / notify
---------------------------------------------------------------------------
local Lib = {}
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local LOGO = "rbxassetid://107391174248131"
pcall(function() getgenv().VIREX_LOGO = LOGO end)
local TOGGLE_KEY = Enum.KeyCode.RightShift
local W, H = 640, 392
local HEAD, TABS, FOOT = 46, 36, 26
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local K = {
	bg = Color3.fromRGB(0, 0, 0),
	panel = Color3.fromRGB(10, 10, 12),
	line = Color3.fromRGB(62, 62, 70),
	line2 = Color3.fromRGB(96, 96, 104),
	soft = Color3.fromRGB(232, 232, 236),
	mute = Color3.fromRGB(168, 168, 176),
	dark = Color3.fromRGB(30, 30, 33),
	knobOff = Color3.fromRGB(105, 105, 112),
}
local F, FB, FK = Enum.Font.GothamMedium, Enum.Font.GothamBold, Enum.Font.GothamBlack
-- texto blanco que se apaga a negro en el borde derecho (solo seleccionado / activo)
local FADE = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.84, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 20)) })
-- luz que revela el texto de izquierda a derecha
local REVEAL = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.45, WHITE), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(16, 16, 18)), ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 18)) })

local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do if k ~= "Parent" then o[k] = v end end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if props and props.Parent then o.Parent = props.Parent end
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(c, t, tr) return new("UIStroke", { Color = c, Thickness = t or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function tween(o, t, props, style, dir, rep, rev)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, rep or 0, rev or false), props)
	tw:Play()
	return tw
end
local function txt(parent, props)
	props.Parent = parent
	props.BackgroundTransparency = 1
	props.Font = props.Font or F
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props)
end
local function isPress(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
-- arrastre con un solo dedo: en movil cada dedo es un "input" distinto; solo se sigue el que empezo
local function sameDrag(startInput, i)
	if not startInput then return false end
	if startInput.UserInputType == Enum.UserInputType.Touch then return i == startInput end
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.MouseButton1
end
getgenv().VIREX_SameDrag = sameDrag
local function isMove(i) return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch end
local function safe(cb, ...)
	if type(cb) ~= "function" then return end
	local ok, err = pcall(cb, ...)
	if not ok then warn("[VIREX] callback error: " .. tostring(err)) end
end
local function smooth(frame)
	local s = { goal = frame.Position }
	RunService.Heartbeat:Connect(function(dt)
		local c, g = frame.Position, s.goal
		local dx, dy = g.X.Offset - c.X.Offset, g.Y.Offset - c.Y.Offset
		if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 and c.X.Scale == g.X.Scale and c.Y.Scale == g.Y.Scale then
			if dx ~= 0 or dy ~= 0 then frame.Position = g end
			return
		end
		local a = 1 - math.exp(-dt * 20)
		frame.Position = UDim2.new(g.X.Scale, c.X.Offset + dx * a, g.Y.Scale, c.Y.Offset + dy * a)
	end)
	return s
end
-- iconos dibujados (ojo / engranaje) dentro de un CanvasGroup: se tiñen con GroupColor3
local function drawIcon(parent, kind)
	local f = new("CanvasGroup", { Parent = parent, LayoutOrder = 1, Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, GroupColor3 = K.mute, ZIndex = 3 })
	if kind == "eye" then
		-- ojo de verdad: dos parpados curvos (arcos de un circulo grande recortados) + iris con brillo
		local R = 8.9
		local function lid(y0, cy)
			local clip = new("Frame", { Parent = f, Position = UDim2.fromOffset(0, 3 + y0), Size = UDim2.fromOffset(16, 5), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3 })
			local c = new("Frame", { Parent = clip, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, cy), Size = UDim2.fromOffset(R * 2, R * 2), BackgroundTransparency = 1, ZIndex = 3 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			new("UIStroke", { Parent = c, Color = WHITE, Thickness = 1.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		end
		lid(0, R + 0.6) -- parpado de arriba
		lid(5, 5 - R - 0.6) -- parpado de abajo
		local iris = new("Frame", { Parent = f, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(6, 6), BackgroundTransparency = 1, ZIndex = 4 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		new("UIStroke", { Parent = iris, Color = WHITE, Thickness = 1.4 })
		new("Frame", { Parent = f, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(2.6, 2.6), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	else -- engranaje
		local ring = new("Frame", { Parent = f, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ZIndex = 3 }, { corner(4) })
		new("UIStroke", { Parent = ring, Color = WHITE, Thickness = 1.8 })
		for i = 0, 5 do
			local a = math.rad(i * 60)
			new("Frame", { Parent = f, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 5.6, 0.5, math.sin(a) * 5.6), Size = UDim2.fromOffset(2.6, 2.6), Rotation = i * 60, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, { corner(1) })
		end
	end
	return f
end
-- onda roja que sale de un punto y se apaga (interruptores, botones)
local function ripple(parent, pos, color, from, to, z)
	local r = new("Frame", { Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(from, from), BackgroundColor3 = color, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = z or 6 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	tween(r, 0.55, { Size = UDim2.fromOffset(to, to), BackgroundTransparency = 1 }, Enum.EasingStyle.Quint)
	task.delay(0.6, function() pcall(function() r:Destroy() end) end)
end
-- ===== piel del UI =====
-- letra (por defecto codigo / RobotoMono), color de acento y sin traduccion automatica (todo en ingles).
-- Se aplica a todo lo de VIREX (panel, avisos, botones flotantes, HUD) y se puede cambiar en Config.
local SKIN = { family = "rbxasset://fonts/families/RobotoMono.json", accH = nil, accS = 1 }
local FONT_FAMILIES = {
	Code = "rbxasset://fonts/families/RobotoMono.json",
	Gotham = "rbxasset://fonts/families/GothamSSm.json",
	Ubuntu = "rbxasset://fonts/families/Ubuntu.json",
	Arial = "rbxasset://fonts/families/Arial.json",
	Fredoka = "rbxasset://fonts/families/FredokaOne.json",
	Oswald = "rbxasset://fonts/families/Oswald.json",
	Arcade = "rbxasset://fonts/families/PressStart2P.json",
	Comic = "rbxasset://fonts/families/ComicNeueAngular.json",
}
local MONO_BOLD = { [Enum.Font.GothamBold] = true, [Enum.Font.GothamBlack] = true, [Enum.Font.SourceSansBold] = true, [Enum.Font.ArialBold] = true }
local SKINNED = {} -- guis con piel
local BOLDMAP = setmetatable({}, { __mode = "k" })
local function fontOne(o)
	if not (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then return end
	if BOLDMAP[o] == nil then
		if o.Font == Enum.Font.Kalam then BOLDMAP[o] = "skip" return end -- el titulo VIREX de pincel se queda igual
		BOLDMAP[o] = MONO_BOLD[o.Font] == true
	end
	if BOLDMAP[o] == "skip" then return end
	pcall(function() o.FontFace = Font.new(SKIN.family, BOLDMAP[o] and Enum.FontWeight.Bold or Enum.FontWeight.Medium) end)
end
-- color de acento: todo lo azul del UI cambia al color elegido (mismo brillo y textura)
local COLOR_PROPS = {
	Frame = { "BackgroundColor3" }, TextButton = { "BackgroundColor3", "TextColor3" }, TextLabel = { "TextColor3" },
	TextBox = { "BackgroundColor3", "TextColor3" }, ImageLabel = { "ImageColor3", "BackgroundColor3" }, ImageButton = { "ImageColor3", "BackgroundColor3" },
	CanvasGroup = { "BackgroundColor3", "GroupColor3" }, UIStroke = { "Color" },
}
local RAW = setmetatable({}, { __mode = "k" })
local busy = false
local function conv(c)
	if not SKIN.accH then return nil end
	c = Color3.new(math.clamp(c.R, 0, 1), math.clamp(c.G, 0, 1), math.clamp(c.B, 0, 1))
	local h, sat, v = c:ToHSV()
	if h >= 0.53 and h <= 0.70 and sat >= 0.2 then return Color3.fromHSV(SKIN.accH, sat * SKIN.accS, v) end
	return nil
end
local function convSeq(seqC)
	local ks, changed = {}, false
	for _, k in ipairs(seqC.Keypoints) do
		local n = conv(k.Value)
		if n then changed = true end
		ks[#ks + 1] = ColorSequenceKeypoint.new(k.Time, n or k.Value)
	end
	return changed and ColorSequence.new(ks) or seqC
end
local function paintProp(o, pr)
	local raw = RAW[o][pr]
	local val = raw
	if pr == "Color" and o:IsA("UIGradient") then val = convSeq(raw) else val = conv(raw) or raw end
	busy = true
	pcall(function() o[pr] = val end)
	busy = false
end
local function colorOne(o)
	local props = COLOR_PROPS[o.ClassName]
	if o:IsA("UIGradient") then props = { "Color" } end
	if not props then return end
	if not RAW[o] then
		RAW[o] = {}
		for _, pr in ipairs(props) do
			RAW[o][pr] = o[pr]
			o:GetPropertyChangedSignal(pr):Connect(function()
				if busy then return end
				RAW[o][pr] = o[pr]
				if SKIN.accH then paintProp(o, pr) end
			end)
		end
	end
	if SKIN.accH or RAW[o].__painted then
		for _, pr in ipairs(props) do paintProp(o, pr) end
		RAW[o].__painted = SKIN.accH ~= nil
	end
end
local function skinOne(o)
	fontOne(o)
	colorOne(o)
end
local function skinGui(g)
	pcall(function() g.AutoLocalize = false end)
	table.insert(SKINNED, g)
	for _, d in ipairs(g:GetDescendants()) do skinOne(d) end
	g.DescendantAdded:Connect(function(d) task.defer(skinOne, d) end)
end
local function reskinAll()
	for i = #SKINNED, 1, -1 do
		local g = SKINNED[i]
		if not g.Parent then table.remove(SKINNED, i) else
			for _, d in ipairs(g:GetDescendants()) do pcall(skinOne, d) end
		end
	end
end
pcall(function() getgenv().VIREX_Skin = skinGui end)
local function guiParent()
	local ok, p = pcall(function() return gethui and gethui() end)
	if ok and p then return p end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then
		local t = Instance.new("Folder")
		local okp = pcall(function() t.Parent = cg end)
		t:Destroy()
		if okp then return cg end
	end
	return lp:WaitForChild("PlayerGui")
end

function Lib._new()
	local rt = { _flags = {}, _config = {} }
	-- ===== config guardada: se lee ANTES de crear los botones, asi salen como los dejaste =====
	local HttpService = game:GetService("HttpService")
	local CONFIG_PATH = "VIREX/BladeBall_Config.json"
	rt._autosave = true
	rt._born = os.clock()
	do
		local saved
		pcall(function()
			if isfile and readfile and isfile(CONFIG_PATH) then saved = HttpService:JSONDecode(readfile(CONFIG_PATH)) end
		end)
		if type(saved) == "table" then
			if saved.__autosave == false then
				rt._autosave = false
			else
				for k, val in pairs(saved) do
					if type(k) == "string" and k:sub(1, 2) ~= "__" then rt._flags[k] = val end
				end
				rt._loadedConfig = true
			end
		end
	end
	local function writeConfig(data)
		if not writefile then return false end
		return (pcall(function()
			if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end
			writefile(CONFIG_PATH, HttpService:JSONEncode(data))
		end))
	end
	local saveQueued = false
	function rt:_save(force)
		if not (force or rt._autosave) then return false end
		local data = { __autosave = rt._autosave }
		for k, val in pairs(rt._flags) do
			local t = type(val)
			if t == "boolean" or t == "number" or t == "string" then data[k] = val end
		end
		return writeConfig(data)
	end
	function rt._changed()
		if not rt._autosave or saveQueued then return end
		saveQueued = true
		task.delay(0.6, function()
			saveQueued = false
			rt:_save()
		end)
	end
	function rt:set_autosave(on)
		rt._autosave = on == true
		if rt._autosave then rt:_save(true) else writeConfig({ __autosave = false }) end
	end
	function rt:get_autosave() return rt._autosave end
	function rt:save_now() return rt:_save(true) end
	function rt:reset_config() return writeConfig({ __autosave = rt._autosave }) end
	local function keyFromName(n)
		if type(n) ~= "string" then return nil end
		local ok, k = pcall(function() return Enum.KeyCode[n] end)
		return ok and k or nil
	end
	local gui = new("ScreenGui", { Name = "VirexPanel", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100 })
	skinGui(gui)
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
	gui.Parent = guiParent()

	-----------------------------------------------------------------------
	-- ventana
	-----------------------------------------------------------------------

	-----------------------------------------------------------------------
	-- sonidos estilo iPhone (generados, van dentro del script)
	-----------------------------------------------------------------------
	local SND = {}
	do
		local DATA = {
			tap = "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",
			toggle_on = "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",
			toggle_off = "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",
			open = "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",
			close = "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",
		}
		local VOL = { tap = 0.45, toggle_on = 0.55, toggle_off = 0.5, open = 0.55, close = 0.5 }
		local function b64dec(str)
			local native
			pcall(function() native = (crypt and (crypt.base64decode or (crypt.base64 and crypt.base64.decode))) or base64_decode end)
			if native then
				local ok, r = pcall(native, str)
				if ok and type(r) == "string" and #r > 0 then return r end
			end
			local map, chars = {}, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
			for i = 1, 64 do map[chars:byte(i)] = i - 1 end
			local out, n = {}, 0
			for i = 1, #str, 4 do
				local a, b, c, d = str:byte(i, i + 3)
				a, b = map[a], map[b]
				c = c and map[c]
				d = d and map[d]
				if not a or not b then break end
				local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
				n += 1 out[n] = string.char(math.floor(v / 65536) % 256)
				if c then n += 1 out[n] = string.char(math.floor(v / 256) % 256) end
				if d then n += 1 out[n] = string.char(v % 256) end
			end
			return table.concat(out)
		end
		task.spawn(function()
			pcall(function()
				local custom = getcustomasset or getsynasset
				if not (custom and writefile and isfile) then return end
				pcall(function() if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end end)
				for name, data in pairs(DATA) do
					pcall(function()
						local path = "VIREX/snd_" .. name .. "_v1.ogg"
						if not isfile(path) then writefile(path, b64dec(data)) end
						local sd = Instance.new("Sound")
						sd.Name = "VIREX_" .. name
						sd.SoundId = custom(path)
						sd.Volume = VOL[name] or 0.5
						sd.Parent = game:GetService("SoundService")
						SND[name] = sd
					end)
				end
			end)
		end)
	end
	local function sfx(name)
		local sd = SND[name]
		if not sd then return end
		pcall(function() game:GetService("SoundService"):PlayLocalSound(sd) end)
	end
	local root = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Visible = false })
	local fit = new("UIScale", { Parent = root })
	local uiMul = 1 -- tamaño elegido en Config (UI Size)
	local function refit()
		local v = gui.AbsoluteSize
		local big = math.clamp(math.min(v.X / 1280, v.Y / 820), 1, 1.75)
		local sc
		if UIS.TouchEnabled and not UIS.MouseEnabled then
			-- movil: mas pequeño para que se vea el juego
			sc = math.max(0.4, math.min(0.8, (v.X - 40) / W, (v.Y * 0.74) / H))
		else
			sc = math.max(0.45, math.min(big, (v.X - 24) / W, (v.Y - 24) / H))
		end
		fit.Scale = sc * uiMul
	end
	function rt:set_ui_scale(pct)
		uiMul = math.clamp((tonumber(pct) or 100) / 100, 0.6, 1.5)
		refit()
	end
	function rt:set_font(name)
		SKIN.family = FONT_FAMILIES[name] or FONT_FAMILIES.Code
		reskinAll()
	end
	function rt:font_names() return { "Code", "Gotham", "Ubuntu", "Arial", "Fredoka", "Oswald", "Arcade", "Comic" } end
	local ACCENTS = { Blue = false, Red = 0.995, Purple = 0.77, Pink = 0.9, Green = 0.38, Cyan = 0.5, Gold = 0.12, Orange = 0.07, White = "white" }
	function rt:accent_names() return { "Blue", "Red", "Purple", "Pink", "Green", "Cyan", "Gold", "Orange", "White" } end
	function rt:set_accent(name)
		local a = ACCENTS[name]
		if a == "white" then SKIN.accH, SKIN.accS = 0.6, 0
		elseif a then SKIN.accH, SKIN.accS = a, 1
		else SKIN.accH, SKIN.accS = nil, 1 end
		reskinAll()
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	local win = new("CanvasGroup", { Parent = root, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.bg, GroupTransparency = 1 }, { corner(8) })
	local winStroke = stroke(K.line2, 1, 0)
	winStroke.Parent = win
	local pop = new("UIScale", { Parent = win, Scale = 0.96 })
	-- mascara para que la ventana se "despliegue" de arriba a abajo como una hoja (y se pliegue al cerrar)
	local sheetGrad = new("UIGradient", { Parent = win, Rotation = 90, Enabled = false, Offset = Vector2.new(0, 0.6), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }) })
	-- fondo con imagen (se mueve muy lento) + capa oscura para que se lea todo
	local bgHold = new("Frame", { Parent = win, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 0 })
	local bgImg = new("ImageLabel", { Parent = bgHold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, ZIndex = 0 })
	local bgSc = new("UIScale", { Parent = bgImg })
	local bgShade
	bgShade = new("Frame", { Parent = bgHold, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 0 })
	new("UIGradient", { Parent = bgShade, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.22, 0.35), NumberSequenceKeypoint.new(0.75, 0.45), NumberSequenceKeypoint.new(1, 0.05) }) })
	-- tu foto del panel va DENTRO del script (no depende de descargas): se guarda una vez y se carga
	local PANEL_BG_JPG = "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"
	local function embeddedBg(onFail)
		task.spawn(function()
			local ok = false
			pcall(function()
				local custom = getcustomasset or getsynasset
				if not (custom and writefile and isfile) then return end
				local function dec(str)
					local native
					pcall(function() native = (crypt and (crypt.base64decode or (crypt.base64 and crypt.base64.decode))) or base64_decode end)
					if native then
						local okd, r = pcall(native, str)
						if okd and type(r) == "string" and #r > 0 then return r end
					end
					local map, chars = {}, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
					for i = 1, 64 do map[chars:byte(i)] = i - 1 end
					local out, n = {}, 0
					for i = 1, #str, 4 do
						local a, b, c, d = str:byte(i, i + 3)
						a, b = map[a], map[b]
						c = c and map[c]
						d = d and map[d]
						if not a or not b then break end
						local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
						n += 1 out[n] = string.char(math.floor(v / 65536) % 256)
						if c then n += 1 out[n] = string.char(math.floor(v / 256) % 256) end
						if d then n += 1 out[n] = string.char(v % 256) end
					end
					return table.concat(out)
				end
				pcall(function() if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end end)
				local path = "VIREX/panel_bg_v1.jpg"
				if not isfile(path) then writefile(path, dec(PANEL_BG_JPG)) end
				local c = custom(path)
				if type(c) == "string" and c ~= "" then
					bgImg.Image = c
					bgImg.Visible = true
					ok = true
				end
			end)
			if not ok and onFail then onFail() end
		end)
	end
	pcall(function()
		if getgenv().VIREX_ResolveImage then
			local function viaId()
				getgenv().VIREX_ResolveImage(84274209587973, bgImg, function(c) bgImg.Image = c end, function()
					bgImg.Visible = false -- no cargo: panel negro limpio
				end)
			end
			-- 1) la foto metida en el script  2) el enlace de catbox  3) el id de Roblox  4) negro limpio
			embeddedBg(function()
				if getgenv().VIREX_UrlImage then
					getgenv().VIREX_UrlImage("https://files.catbox.moe/usp8cw.png", bgImg, function(c) bgImg.Image = c end, viaId)
				else
					viaId()
				end
			end)
		else
			bgImg.Image = "rbxassetid://84274209587973"
		end
	end)
	-- (el fondo se queda quieto: sin zoom ni movimiento)

	-- fondo negro para la cabecera y las pestañas
	local topShade = new("Frame", { Parent = win, Size = UDim2.new(1, 0, 0, HEAD + 2), BackgroundColor3 = BLACK, BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 1 })
	new("UIGradient", { Parent = topShade, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.15) }) })
	-- cabecera
	local head = new("Frame", { Parent = win, Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, ZIndex = 2 })
	local headL = new("Frame", { Parent = head, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1, ZIndex = 2 })
	new("UIListLayout", { Parent = headL, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder })
	local logoHold = new("Frame", { Parent = headL, LayoutOrder = 1, Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, ZIndex = 3, Visible = false }) -- (sin logo dentro del panel)
	local logoImg = new("ImageLabel", { Parent = logoHold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = LOGO, ScaleType = Enum.ScaleType.Fit, ZIndex = 4 })
	local logoSc = new("UIScale", { Parent = logoImg })
	-- VIREX en el centro de la cabecera, con brillo suave detras y luz que lo recorre
	-- letra de pincel (lo mas parecido a la de la intro que trae Roblox), inclinada como la intro
	local BRUSH = nil
	pcall(function() BRUSH = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal) end)
	local titleGlow = txt(head, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "Virex", Font = Enum.Font.Kalam, TextSize = 30, TextColor3 = Color3.fromRGB(255, 40, 40), TextTransparency = 0.7, TextXAlignment = Enum.TextXAlignment.Center, Rotation = -7, ZIndex = 3 })
	new("UIStroke", { Parent = titleGlow, Color = Color3.fromRGB(255, 40, 40), Thickness = 5, Transparency = 0.82 })
	titleGlow.TextTransparency = 0.85 -- (brillo fijo, sin pulso)
	local headTitle = txt(head, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "Virex", Font = Enum.Font.Kalam, TextSize = 30, TextColor3 = Color3.fromRGB(255, 225, 225), TextXAlignment = Enum.TextXAlignment.Center, Rotation = -7, ZIndex = 4 })
	new("UIStroke", { Parent = headTitle, Color = Color3.fromRGB(120, 0, 0), Thickness = 1, Transparency = 0.4 })
	if BRUSH then pcall(function() headTitle.FontFace = BRUSH titleGlow.FontFace = BRUSH end) end
	local headGrad = new("UIGradient", { Parent = headTitle, Color = REVEAL, Offset = Vector2.new(1, 0) })
	-- cada pocos segundos una luz roja recorre el nombre VIREX
	local NEON = Color3.fromRGB(255, 45, 45)
	local SHIMMER = ColorSequence.new({ ColorSequenceKeypoint.new(0, NEON), ColorSequenceKeypoint.new(0.4, NEON), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.6, NEON), ColorSequenceKeypoint.new(1, NEON) })
	local TITLE_REVEAL = ColorSequence.new({ ColorSequenceKeypoint.new(0, NEON), ColorSequenceKeypoint.new(0.45, NEON), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(16, 16, 18)), ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 18)) })
	headGrad.Color = TITLE_REVEAL
	task.spawn(function()
		task.wait(2)
		while headTitle.Parent do
			headGrad.Color = SHIMMER
			headGrad.Offset = Vector2.new(-1, 0)
			tween(headGrad, 1.1, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(3.6)
		end
	end)
	-- VIREX en foto (la del usuario): si carga, sustituye al texto; si no, se queda el texto
	local TITLE_URL = "https://files.catbox.moe/26c36d.png"
	local titleImgGlow = new("ImageLabel", { Parent = head, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(640, 100), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ImageColor3 = Color3.fromRGB(255, 40, 40), ImageTransparency = 0.86, Visible = false, ZIndex = 3 })
	local titleImg = new("ImageLabel", { Parent = head, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(600, 92), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = 4 })
	-- aparece de izquierda a derecha al abrir el panel
	local titleImgGrad = new("UIGradient", { Parent = titleImg, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(1, 0) })
	local titleIsImage = false
	local titleCanSquash = false
	local function revealTitleImg()
		if not titleIsImage then return end
		titleImgGrad.Offset = Vector2.new(-1, 0)
		tween(titleImgGrad, 0.9, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	pcall(function()
		if not getgenv().VIREX_UrlImage then return end
		getgenv().VIREX_UrlImage(TITLE_URL, titleImg, function(c)
			titleImg.Image = c
			titleImgGlow.Image = c
			-- tamaño segun la foto: si es alargada (recortada al texto) va ajustada a la cabecera;
			-- si es mas cuadrada (con margen alrededor) se amplia para que VIREX se vea grande
			pcall(function()
				local d = readfile("VIREX/" .. (TITLE_URL:match("([%w_%-]+%.%w+)$")))
				if type(d) == "string" and d:sub(1, 4) == "\137PNG" then
					local w = string.unpack(">I4", d, 17)
					local h = string.unpack(">I4", d, 21)
					if w > 0 and h > 0 then
						local aspect = w / h
						local maxW = aspect >= 2.4 and 300 or 600
						local tH = aspect >= 2.4 and 34 or 92
						local tW = math.min(tH * aspect, maxW)
						-- caja con la misma proporcion que la foto: asi se puede "aplastar" como una tele
						titleImg.Size = UDim2.fromOffset(tW, tW / aspect)
						titleImg.ScaleType = Enum.ScaleType.Stretch
						titleImgGlow.ScaleType = Enum.ScaleType.Stretch
						titleImgGlow.Size = UDim2.fromOffset(tW + 14, tW / aspect + 6)
						titleCanSquash = true
					end
				end
			end)
			titleImg.Visible = true
			titleImgGlow.Visible = true
			headTitle.Visible = false
			titleGlow.Visible = false
			titleIsImage = true
			revealTitleImg()
		end, function()
			titleIsImage = false
			titleImg.Visible = false
			titleImgGlow.Visible = false
			headTitle.Visible = true
			titleGlow.Visible = true
		end)
	end)
	-- efecto de tele (como la intro): cada pocos segundos VIREX se apaga como una tele vieja
	-- (glitch rojo, se desvanece) y se vuelve a encender con parpadeos
	do
		local rnd = Random.new()
		local busy = false
		local function jitterFlicker(setT, setPos, base, times)
			for _ = 1, times do
				setT(rnd:NextNumber(0.35, 0.7))
				setPos(UDim2.new(base.X.Scale, base.X.Offset + rnd:NextInteger(-4, 4), base.Y.Scale, base.Y.Offset))
				if titleIsImage then
					titleImgGlow.Position = UDim2.new(base.X.Scale, base.X.Offset + rnd:NextInteger(3, 6), base.Y.Scale, base.Y.Offset)
					titleImgGlow.ImageTransparency = 0.4
				end
				task.wait(rnd:NextNumber(0.03, 0.06))
				setT(0)
				setPos(base)
				if titleIsImage then
					titleImgGlow.Position = base
					titleImgGlow.ImageTransparency = 0.86
				end
				task.wait(rnd:NextNumber(0.04, 0.1))
			end
		end
		-- el glitch rojo (el que mola): sombra roja desplazada + temblor
		local function redGlitch(n)
			jitterFlicker(function(t)
				if titleIsImage then titleImg.ImageTransparency = t else headTitle.TextTransparency = t end
			end, function(p)
				if titleIsImage then titleImg.Position = p else headTitle.Position = p end
			end, titleIsImage and titleImg.Position or headTitle.Position, n)
		end
		local function setT(t)
			if titleIsImage then titleImg.ImageTransparency = t else headTitle.TextTransparency = t end
		end
		-- apagado y encendido como una tele: sin lineas ni deformar el nombre, solo glitch rojo y parpadeo
		local function tvCycle()
			if busy then return end
			busy = true
			pcall(function()
				local obj = titleIsImage and titleImg or headTitle
				if not obj.Visible then return end
				local base = obj.Position
				-- 1) glitch rojo
				redGlitch(2)
				-- 2) se apaga: la sombra roja se separa un poco y todo se desvanece rapido
				if titleIsImage then
					titleImgGlow.ImageTransparency = 0.35
					tween(titleImgGlow, 0.2, { Position = UDim2.new(base.X.Scale, base.X.Offset + 6, base.Y.Scale, base.Y.Offset), ImageTransparency = 1 }, Enum.EasingStyle.Quad)
					tween(titleImg, 0.16, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				else
					titleGlow.Visible = false
					tween(headTitle, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
				task.wait(0.2 + rnd:NextNumber(0.15, 0.3))
				-- 3) se enciende: parpadea un par de veces y se queda
				if titleIsImage then titleImgGlow.Position = base end
				for _ = 1, rnd:NextInteger(2, 3) do
					setT(0.15)
					task.wait(rnd:NextNumber(0.04, 0.07))
					setT(1)
					task.wait(rnd:NextNumber(0.04, 0.09))
				end
				setT(0)
				if titleIsImage then
					titleImgGlow.ImageTransparency = 0.86
				else
					titleGlow.Visible = true
				end
				-- 4) y otra vez el glitch rojo al volver
				redGlitch(rnd:NextInteger(2, 3))
				setT(0)
				obj.Position = base
				if titleIsImage then titleImgGlow.Position = base titleImgGlow.ImageTransparency = 0.86 end
			end)
			busy = false
		end
		task.spawn(function()
			task.wait(3)
			while head.Parent do
				task.wait(3)
				if root.Visible then tvCycle() end
			end
		end)
	end
	-- agarre para mover la ventana (arriba en el centro)
	-- barra para mover la ventana: debajo del panel (como en el Pet Finder), pastilla de cristal
	local gripHit = new("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(150, 26), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20 })
	-- pastilla de cristal: clara arriba, mas oscura abajo, borde blanco suave
	local grip = new("Frame", { Parent = gripHit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 8), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 21 }, { corner(4) })
	new("UIGradient", { Parent = grip, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(170, 178, 196)) })
	local gripSt = new("UIStroke", { Parent = grip, Color = WHITE, Thickness = 1, Transparency = 0.5 })

	-- esquina abajo a la derecha: arco de cristal para cambiar el tamaño del panel arrastrando
	local rsHit = new("TextButton", { Parent = root, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 14, 1, 14), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20 })
	local rsClip = new("Frame", { Parent = rsHit, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 21 })
	local rsArc = new("Frame", { Parent = rsClip, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, ZIndex = 21 }, { corner(18) })
	local rsSt = new("UIStroke", { Parent = rsArc, Color = WHITE, Thickness = 3, Transparency = 0.4 })
	do
		local rDrag, rInp, startDist, startMul = false, nil, 1, 1
		rsHit.InputBegan:Connect(function(i)
			if isPress(i) and not rDrag then
				rDrag, rInp = true, i
				local c = root.AbsolutePosition + root.AbsoluteSize / 2
				startDist = math.max((Vector2.new(i.Position.X, i.Position.Y) - c).Magnitude, 20)
				startMul = uiMul
				tween(rsSt, 0.2, { Transparency = 0, Thickness = 4 })
			end
		end)
		rsHit.MouseEnter:Connect(function() if not rDrag then tween(rsSt, 0.2, { Transparency = 0.15 }) end end)
		rsHit.MouseLeave:Connect(function() if not rDrag then tween(rsSt, 0.25, { Transparency = 0.4 }) end end)
		UIS.InputChanged:Connect(function(i)
			if rDrag and isMove(i) and sameDrag(rInp, i) then
				local c = root.AbsolutePosition + root.AbsoluteSize / 2
				local d = (Vector2.new(i.Position.X, i.Position.Y) - c).Magnitude
				uiMul = math.clamp(startMul * d / startDist, 0.6, 1.5)
				refit()
			end
		end)
		UIS.InputEnded:Connect(function(i)
			if rDrag and isPress(i) and sameDrag(rInp, i) then
				rDrag = false
				tween(rsSt, 0.35, { Transparency = 0.4, Thickness = 3 })
				local pct = math.floor(uiMul * 100 + 0.5)
				rt._flags["VIREX_UI_Size"] = pct
				pcall(rt._changed)
				if rt._sizeSlider then pcall(function() rt._sizeSlider:set_value(pct, true) end) end
			end
		end)
	end

	local function headBtn(x, glyph, size)
		-- gota de cristal (como la pestaña elegida): base translucida, toque rojo, reflejo y borde blanco -> rojo
		local b = new("TextButton", { Parent = head, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromRGB(13, 24, 46), BackgroundTransparency = 0.45, AutoButtonColor = false, Text = glyph, Font = FB, TextSize = size, TextColor3 = WHITE, ZIndex = 4 }, { corner(13) })
		local bSt = new("UIStroke", { Parent = b, Color = WHITE, Thickness = 1.1, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		new("UIGradient", { Parent = bSt, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.65), NumberSequenceKeypoint.new(1, 0.3) }) })
		local bTint = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(45, 135, 255), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 3 }, { corner(13) })
		new("UIGradient", { Parent = bTint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.95) }) })
		local bGloss = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, { corner(13) })
		new("UIGradient", { Parent = bGloss, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.45, 0.92), NumberSequenceKeypoint.new(1, 1) }) })
		local bSc = new("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			tween(bSc, 0.3, { Scale = 1.1 }, Enum.EasingStyle.Back)
			tween(b, 0.25, { BackgroundColor3 = Color3.fromRGB(26, 62, 140), BackgroundTransparency = 0.25 }, Enum.EasingStyle.Quint)
			tween(bSt, 0.25, { Transparency = 0 })
		end)
		b.MouseLeave:Connect(function()
			tween(bSc, 0.3, { Scale = 1 }, Enum.EasingStyle.Quint)
			tween(b, 0.3, { BackgroundColor3 = Color3.fromRGB(13, 24, 46), BackgroundTransparency = 0.45 }, Enum.EasingStyle.Quint)
			tween(bSt, 0.3, { Transparency = 0.25 })
		end)
		b.InputBegan:Connect(function(i) if isPress(i) then tween(bSc, 0.12, { Scale = 0.88 }, Enum.EasingStyle.Quad) end end)
		b.InputEnded:Connect(function(i) if isPress(i) then tween(bSc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back) end end)
		return b
	end
	local closeBtn = headBtn(-10, "×", 22)
	local minBtn = headBtn(-42, "–", 18)
	-- (sin linea bajo la cabecera)
	-- linea roja fina con un brillo que la recorre de vez en cuando
	local accent = new("Frame", { Parent = win, Position = UDim2.fromOffset(0, HEAD), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(45, 125, 255), BorderSizePixel = 0, ZIndex = 3, Visible = false })
	local accentGrad = new("UIGradient", { Parent = accent, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }) })
	task.spawn(function()
		while gui.Parent do
			accentGrad.Offset = Vector2.new(-1, 0)
			tween(accentGrad, 1.6, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(4)
		end
	end)

	-- barra de pestañas
	-- pestañas repartidas a lo ancho y centradas (todas del mismo tamaño)
	-- cristal liquido que se pone encima de la pestaña elegida (por debajo del texto)
	local glassLayer = new("Frame", { Parent = win, Position = UDim2.new(0, 0, 1, -(FOOT + TABS + 4)), Size = UDim2.new(1, 0, 0, TABS), BackgroundTransparency = 1, ZIndex = 2 })
	local glassShadow = new("Frame", { Parent = glassLayer, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(-300, TABS / 2 + 3), Size = UDim2.fromOffset(100, 30), BackgroundColor3 = BLACK, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 2 }, { corner(15) })
	-- gota de cristal: base translucida con toque rojo, reflejo arriba y borde blanco -> rojo (sin linea blanca)
	local glass = new("Frame", { Parent = glassLayer, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(-300, TABS / 2), Size = UDim2.fromOffset(100, 30), BackgroundColor3 = Color3.fromRGB(13, 24, 46), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, { corner(15) })
	local glassSt = new("UIStroke", { Parent = glass, Color = WHITE, Thickness = 1.2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	new("UIGradient", { Parent = glassSt, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.65), NumberSequenceKeypoint.new(1, 0.3) }) })
	local glassTint = new("Frame", { Parent = glass, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(45, 135, 255), BorderSizePixel = 0, ZIndex = 3 }, { corner(15) })
	new("UIGradient", { Parent = glassTint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.95) }) })
	local glassGloss = new("Frame", { Parent = glass, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, { corner(15) })
	new("UIGradient", { Parent = glassGloss, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.45, 0.92), NumberSequenceKeypoint.new(1, 1) }) })
	local glassSc = new("UIScale", { Parent = glass })
	local tabBar = new("Frame", { Parent = win, Position = UDim2.new(0, 0, 1, -(FOOT + TABS + 4)), Size = UDim2.new(1, 0, 0, TABS), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 })
	new("UIListLayout", { Parent = tabBar, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	new("UIPadding", { Parent = tabBar, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
	-- separacion suave (degradado) entre pestañas y contenido, sin linea dura
	-- fondo oscuro de la barra de secciones (abajo)
	local tabShade = new("Frame", { Parent = win, Position = UDim2.new(0, 0, 1, -(FOOT + TABS + 6)), Size = UDim2.new(1, 0, 0, TABS + 6), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 })
	-- dock de cristal liquido donde van las secciones (flota dentro del panel, con esquinas redondas)
	local dock = new("Frame", { Parent = win, Position = UDim2.new(0, 8, 1, -(FOOT + TABS + 6)), Size = UDim2.new(1, -16, 0, TABS + 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1 }, { corner(18) })
	new("UIGradient", { Parent = dock, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(62, 68, 88)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(26, 29, 40)), ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 15, 21)) }) })
	local dockSt = new("UIStroke", { Parent = dock, Color = WHITE, Thickness = 1.1, Transparency = 0.1 })
	new("UIGradient", { Parent = dockSt, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(180, 200, 235)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.6) }) })
	new("UIGradient", { Parent = tabShade, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }) })
	local sep = new("Frame", { Parent = win, Position = UDim2.new(0, 0, 1, -(FOOT + TABS + 6)), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 2, Visible = false })
	new("UIGradient", { Parent = sep, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) })

	-- zona de contenido
	local TOP = HEAD + 2
	local body = new("Frame", { Parent = win, Position = UDim2.fromOffset(0, TOP), Size = UDim2.new(1, 0, 1, -(TOP + FOOT + TABS + 12)), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1 })

	-- pie
	local foot = new("Frame", { Parent = win, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, FOOT), BackgroundTransparency = 1, ZIndex = 2 })
	-- fondo de cristal oscuro con linea de luz arriba (blanca en el centro, roja en los lados)
	-- pie negro
	local footBg = new("Frame", { Parent = foot, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 2 })
	-- fondo del panel (Config -> Background) y foto de fondo encendida / apagada
	local BGS = { Dark = Color3.fromRGB(0, 0, 0), Navy = Color3.fromRGB(4, 10, 28), Purple = Color3.fromRGB(16, 6, 30), Wine = Color3.fromRGB(26, 4, 10), Gray = Color3.fromRGB(22, 22, 26), Forest = Color3.fromRGB(4, 18, 12) }
	function rt:background_names() return { "Dark", "Navy", "Purple", "Wine", "Gray", "Forest" } end
	function rt:set_background(name)
		local c = BGS[name] or BGS.Dark
		for _, f in ipairs({ win, bgShade, topShade, tabShade, footBg }) do pcall(function() f.BackgroundColor3 = c end) end
	end
	function rt:set_panel_image(on) pcall(function() bgImg.ImageTransparency = on and 0 or 1 end) end
	local footLine = new("Frame", { Parent = foot, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 })
	new("UIGradient", { Parent = footLine, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) }) })
	-- avatar redondo con aro rojo
	local av = new("ImageLabel", { Parent = foot, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = K.dark, Image = "", ZIndex = 4 }, { corner(9) })
	local avSt = new("UIStroke", { Parent = av, Color = WHITE, Thickness = 1.4, Transparency = 0 })
	avSt.Transparency = 0.5
	pcall(function() av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48) end)
	txt(foot, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(0.6, 0, 1, 0), Text = "<b>" .. tostring(lp.DisplayName) .. "</b>  <font color=\"#8a8088\">@" .. tostring(lp.Name) .. "</font>", RichText = true, Font = FB, TextSize = 11, TextColor3 = WHITE, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
	-- a la derecha: pastilla de cristal con FPS y ping en vivo
	local stats = new("Frame", { Parent = foot, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(112, 18), BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 3 }, { corner(9) })
	new("UIStroke", { Parent = stats, Color = WHITE, Transparency = 0.8, Thickness = 1 })
	new("Frame", { Parent = stats, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, { corner(3) })
	local statsTxt = txt(stats, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -24, 1, 0), Text = "-- FPS  ·  -- ms", Font = FB, TextSize = 9, TextColor3 = Color3.fromRGB(215, 210, 214), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	task.spawn(function()
		local frames, last = 0, os.clock()
		local hb = game:GetService("RunService").Heartbeat:Connect(function() frames += 1 end)
		while gui.Parent do
			task.wait(1)
			local now = os.clock()
			local fps = math.floor(frames / math.max(now - last, 0.001) + 0.5)
			frames, last = 0, now
			local ping = 0
			pcall(function() ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
			statsTxt.Text = fps .. " FPS  ·  " .. ping .. " ms"
		end
		hb:Disconnect()
	end)

	-----------------------------------------------------------------------
	-- notificaciones (abajo a la derecha)
	-----------------------------------------------------------------------
	local toastBox = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(250, 400), BackgroundTransparency = 1, ZIndex = 300 })
	new("UIListLayout", { Parent = toastBox, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	local toastN = 0
	local function notify(title, text, dur)
		dur = tonumber(dur) or 3
		toastN += 1
		local holder = new("Frame", { Parent = toastBox, LayoutOrder = toastN, Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, ZIndex = 300 })
		local t = new("CanvasGroup", { Parent = holder, Position = UDim2.fromOffset(40, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, GroupTransparency = 1, ZIndex = 300 }, { corner(6), stroke(K.line2, 1, 0) })
		new("Frame", { Parent = t, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 301 })
		txt(t, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -24, 0, 15), Text = tostring(title or "VIREX"), Font = FB, TextSize = 12, ZIndex = 301 })
		txt(t, { Position = UDim2.fromOffset(14, 25), Size = UDim2.new(1, -24, 0, 14), Text = tostring(text or ""), Font = F, TextSize = 10, TextColor3 = K.mute, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 301 })
		local prog = new("Frame", { Parent = t, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 302 })
		tween(t, 0.45, { Position = UDim2.fromOffset(0, 0) })
		tween(t, 0.3, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
		tween(prog, dur, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear)
		task.delay(dur, function()
			tween(t, 0.3, { Position = UDim2.fromOffset(40, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.32, function()
				tween(holder, 0.25, { Size = UDim2.new(1, 0, 0, 0) })
				task.delay(0.27, function() holder:Destroy() end)
			end)
		end)
	end

	-----------------------------------------------------------------------
	-- teclas
	-----------------------------------------------------------------------
	local binds, capturing = {}, nil
	UIS.InputBegan:Connect(function(i, gp)
		if capturing then
			if i.UserInputType == Enum.UserInputType.Keyboard then
				local cb = capturing
				capturing = nil
				cb(i.KeyCode)
			end
			return
		end
		if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
		-- RightShift abre/cierra aunque el juego la use (Shift Lock); no si estas escribiendo
		if i.KeyCode == TOGGLE_KEY then
			local typing = false
			pcall(function() typing = UIS:GetFocusedTextBox() ~= nil end)
			if not typing then rt._toggleWindow() end
			return
		end
		if gp then return end
		for _, b in ipairs(binds) do if b.key == i.KeyCode then b.fn() end end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
		for _, b in ipairs(binds) do if b.release and b.key == i.KeyCode then b.release() end end
	end)

	-----------------------------------------------------------------------
	-- pestañas y paginas
	-----------------------------------------------------------------------
	local pages, tabs, tabList, currentTab = {}, {}, {}, nil
	local allScrolls = {}
	local openDrops = {}
	local function closeDrops(except)
		for d in pairs(openDrops) do if d ~= except then d(false) end end
	end
	local function lockScroll(v) for _, s in ipairs(allScrolls) do s.ScrollingEnabled = not v end end

	local function popGroups(p)
		for i, g in ipairs(p.groups) do
			g.sc.Scale = 0.95
			g.st.Transparency = 0.1
			task.delay(math.min(i - 1, 10) * 0.05, function()
				tween(g.sc, 0.55, { Scale = 1 }, Enum.EasingStyle.Quint)
			end)
		end
	end

	-- reparte los grupos entre las 2 columnas: cada uno va a la mas corta (asi no queda un lado vacio)
	local function rebalance(p)
		local list = {}
		for _, col in ipairs(p.cols) do
			for _, ch in ipairs(col:GetChildren()) do if ch:IsA("Frame") then list[#list + 1] = ch end end
		end
		local function key(b) return (b.LayoutOrder < 0 and -100000 or 0) + (b:GetAttribute("VIREX_Order") or 0) end
		table.sort(list, function(a, b) return key(a) < key(b) end)
		local h = { 0, 0 }
		for i, box in ipairs(list) do
			local c = h[1] <= h[2] and 1 or 2
			box.Parent = p.cols[c]
			box.LayoutOrder = i
			local bh = box.AbsoluteSize.Y
			if bh < 5 then
				bh = 0
				for _, ch in ipairs(box:GetChildren()) do if ch:IsA("Frame") and ch.Visible then bh += 40 end end
			end
			h[c] += bh + 10
		end
	end

	-- posicion de cada pestaña (todas iguales, repartidas a lo ancho)
	local glassDragging, glassInput, glassStartX, glassMoved = false, nil, 0, false
	local function tabGeom(i)
		local n = math.max(#tabList, 1)
		local tw = (W - 20) / n - 6 + 6 / n
		return 10 + (i - 1) * (tw + 6) + tw / 2, tw
	end
	-- ancho del cristal = lo que ocupa el icono + el nombre de esa pestaña (ajustado a cada texto)
	local TextService = game:GetService("TextService")
	local function glassW(i)
		local t = tabList[i]
		if not t then local _, tw = tabGeom(i) return tw end
		if not t.cw then
			local tw = #t.name * 8
			pcall(function() tw = TextService:GetTextSize(t.name, 13, FB, Vector2.new(1000, 100)).X end)
			t.cw = ((t.icon and 20 or 0) + tw) * 1.12 + 30
		end
		local _, maxW = tabGeom(i)
		return math.min(t.cw, maxW)
	end
	local glassMoveId = 0
	local function placeGlass(cx, gw, instant)
		local pos, size = UDim2.fromOffset(cx, TABS / 2), UDim2.fromOffset(gw, 30)
		local spos = UDim2.fromOffset(cx, TABS / 2 + 3)
		if instant then
			glass.Position, glass.Size, glassShadow.Position, glassShadow.Size = pos, size, spos, size
		else
			-- se desliza suave hasta la nueva pestaña y al llegar se aplasta un poquito (gota)
			glassMoveId += 1
			tween(glass, 0.42, { Position = pos, Size = size }, Enum.EasingStyle.Quint)
			tween(glassShadow, 0.46, { Position = spos, Size = size }, Enum.EasingStyle.Quint)
			glassSc.Scale = 0.96
			tween(glassSc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	local function moveGlass(i, instant)
		local cx = tabGeom(i)
		placeGlass(cx, glassW(i), instant)
	end
	local selectTab -- (se define justo debajo; el arrastre la necesita)
	local glassLastPos = Vector2.new()
	-- arrastre fluido: el cristal sigue al dedo cada frame (sin tweens que se pisan),
	-- y la seccion solo cambia cuando el dedo se para un momento encima o al soltar
	-- (antes cambiaba la pagina en cada pestaña que cruzabas y se trababa al ir rapido)
	local glassTargetX, hoverIdx, hoverSince = nil, nil, 0
	local function localX(px)
		local k = glassLayer.AbsoluteSize.X / W
		if k <= 0.01 then return nil end
		local _, tw = tabGeom(1)
		return math.clamp((px - glassLayer.AbsolutePosition.X) / k, 10 + tw / 2, W - 10 - tw / 2)
	end
	local function idxAt(lx)
		local n = math.max(#tabList, 1)
		local _, tw = tabGeom(1)
		return math.clamp(math.floor((lx - 10) / (tw + 6)) + 1, 1, n)
	end
	local function dragMove(pos)
		if not glassDragging then return end
		if not glassMoved then
			if math.abs(pos.X - glassStartX) < 8 then return end
			glassMoved = true
			tween(glassSt, 0.25, { Transparency = 0 }, Enum.EasingStyle.Quad)
			tween(glassSc, 0.3, { Scale = 1.06 }, Enum.EasingStyle.Back)
		end
		glassLastPos = pos
		glassTargetX = localX(pos.X)
	end
	local function dragEnd()
		if not glassDragging then return end
		glassDragging = false
		glassInput = nil
		tween(glassSt, 0.35, { Transparency = 0.2 }, Enum.EasingStyle.Quad)
		tween(glassSc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		if glassMoved and glassTargetX then
			local t = tabList[idxAt(glassTargetX)]
			if t and currentTab ~= t.name and selectTab then
				sfx("tap")
				selectTab(t.name)
			end
		end
		glassTargetX, hoverIdx = nil, nil
		if currentTab and tabs[currentTab] then moveGlass(tabs[currentTab].idx) end
	end
	RunService.RenderStepped:Connect(function(dt)
		if not (glassDragging and glassMoved and glassTargetX) then return end
		-- la pestaña que tiene el dedo encima: el cristal va a ella (una a una, sin saltos largos)
		local fi = idxAt(glassTargetX)
		local tx = tabGeom(fi)
		local a = 1 - math.exp(-dt * 16)
		local cx = glass.Position.X.Offset
		local x = cx + (tx - cx) * a
		local wNow = glass.Size.X.Offset
		local w = wNow + (glassW(fi) - wNow) * a
		glass.Position, glass.Size = UDim2.fromOffset(x, TABS / 2), UDim2.fromOffset(w, 30)
		glassShadow.Position, glassShadow.Size = UDim2.fromOffset(x, TABS / 2 + 3), UDim2.fromOffset(w, 30)
		if fi ~= hoverIdx then
			hoverIdx, hoverSince = fi, os.clock()
		elseif os.clock() - hoverSince > 0.14 then
			local t = tabList[fi]
			if t and currentTab ~= t.name and selectTab then
				sfx("tap")
				selectTab(t.name)
			end
		end
	end)
	-- movil: solo el dedo que empezo en las pestañas (el joystick es otro dedo)
	UIS.TouchMoved:Connect(function(touch)
		if glassInput and touch == glassInput then dragMove(Vector2.new(touch.Position.X, touch.Position.Y)) end
	end)
	UIS.TouchEnded:Connect(function(touch)
		if glassInput and touch == glassInput then dragEnd() end
	end)
	-- PC: raton
	UIS.InputChanged:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseMovement and glassInput and glassInput.UserInputType == Enum.UserInputType.MouseButton1 then
			dragMove(Vector2.new(i.Position.X, i.Position.Y))
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if glassInput and ((i.UserInputType == Enum.UserInputType.MouseButton1 and glassInput.UserInputType == Enum.UserInputType.MouseButton1) or i == glassInput) then
			dragEnd()
		end
	end)
	function selectTab(name, silent)
		if currentTab == name then return end
		if tabs[name] and not glassDragging then moveGlass(tabs[name].idx, silent) end
		local prev = currentTab and tabs[currentTab]
		currentTab = name
		closeDrops()
		local dir = 1
		if prev and tabs[name] and tabs[name].idx < prev.idx then dir = -1 end
		for n, t in pairs(tabs) do
			local on = n == name
			t.sel = on
			tween(t.label, 0.35, { TextColor3 = on and WHITE or K.mute, TextStrokeTransparency = 1, TextTransparency = on and 0 or 0.3 })
			if t.isc then
				if on and not silent then t.isc.Scale = 0.94 end
				tween(t.isc, on and 0.55 or 0.4, { Scale = on and 1.04 or 0.9 }, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
			end
			if t.icon then tween(t.icon, 0.3, (t.icon:IsA("TextLabel") and { TextColor3 = on and WHITE or K.mute }) or (t.icon:IsA("CanvasGroup") and { GroupColor3 = on and WHITE or K.mute }) or { ImageColor3 = on and WHITE or K.mute }) end
			t.fade.Enabled = false -- (texto blanco limpio, sin la ultima letra negra)
			-- solo la elegida tiene pastilla y linea roja; crecen desde el centro
			if on then
				if silent then
					t.pill.Size = UDim2.new(1, 0, 0, 28)
					t.pill.BackgroundTransparency = 0.9
					t.pillStroke.Transparency = 0.82
					t.bar.Size = UDim2.new(1, -18, 0, 2)
				else
					t.pill.Size = UDim2.new(0.4, 0, 0, 22)
					t.pill.BackgroundTransparency = 1
					t.pillStroke.Transparency = 1
					t.bar.Size = UDim2.new(0, 0, 0, 2)
					tween(t.pill, 0.45, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 0.9 }, Enum.EasingStyle.Back)
					tween(t.pillStroke, 0.4, { Transparency = 0.82 }, Enum.EasingStyle.Quad)
					task.delay(0.12, function() if t.sel then tween(t.bar, 0.45, { Size = UDim2.new(1, -18, 0, 2) }, Enum.EasingStyle.Back) end end)
				end
			else
				tween(t.pill, 0.25, { Size = UDim2.new(0.4, 0, 0, 22), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				tween(t.pillStroke, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad)
				tween(t.bar, 0.2, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Quad)
				tween(t.label, 0.3, { TextColor3 = K.mute })
			end
			if on and t.icon and not silent then
				-- el icono da un saltito al elegir la seccion
				t.icon.Rotation = -18
				tween(t.icon, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			end
		end
		for n, p in pairs(pages) do
			if n == name then
				p.group.Visible = true
				p.group.ZIndex = 2
				if silent then
					p.group.GroupTransparency = 0
					p.group.Position = UDim2.new()
					p.depth.Scale = 1
				else
					-- la nueva entra deslizandose desde el lado de la pestaña, justo cuando la otra ya se va
					p.group.GroupTransparency = 1
					p.group.Position = UDim2.fromOffset(22 * dir, 0)
					p.depth.Scale = 0.86 -- viene desde atras
					local myTab = name
					task.delay(0.1, function()
						if currentTab ~= myTab then return end
						tween(p.group, 0.38, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
						tween(p.group, 0.6, { Position = UDim2.new() }, Enum.EasingStyle.Quint)
						tween(p.depth, 0.65, { Scale = 1 }, Enum.EasingStyle.Back)
						popGroups(p)
					end)
				end
			elseif p.group.Visible then
				-- la anterior se va hacia atras y se apaga
				p.group.ZIndex = 1
				if silent then
					p.group.Visible = false
				else
					-- la anterior sale hacia el otro lado y se apaga
					-- la anterior se va hacia atras: se encoge, se aparta y se apaga
					tween(p.group, 0.3, { Position = UDim2.fromOffset(-22 * dir, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
					tween(p.depth, 0.3, { Scale = 0.86 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
					tween(p.group, 0.24, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
					task.delay(0.31, function() if currentTab ~= n then p.group.Visible = false p.depth.Scale = 1 end end)
				end
			end
		end
	end

	local function getPage(name, iconId)
		if pages[name] then return pages[name] end
		local idx = #tabList + 1
		local pg = new("CanvasGroup", { Parent = body, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, GroupTransparency = 1 })
		local scroll = new("ScrollingFrame", { Parent = pg, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y })
		table.insert(allScrolls, scroll)
		local wrap = new("Frame", { Parent = scroll, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
		new("UIPadding", { Parent = wrap, PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) })
		local cols = {}
		for c = 1, 2 do
			local col = new("Frame", { Parent = wrap, Position = c == 1 and UDim2.new() or UDim2.new(0.5, 5, 0, 0), Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
			new("UIListLayout", { Parent = col, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })
			cols[c] = col
		end
		local p = { group = pg, scroll = scroll, cols = cols, groups = {}, count = { 0, 0 }, depth = new("UIScale", { Parent = pg }) }
		pages[name] = p

		-- boton de la pestaña
		local btn = new("TextButton", { Parent = tabBar, LayoutOrder = idx, Size = UDim2.new(0.25, -5, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3 })
		new("UIPadding", { Parent = btn, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
		local inner = new("Frame", { Parent = btn, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3 })
		new("UIListLayout", { Parent = inner, FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
		local icon
		if iconId then
			if tostring(iconId):sub(1, 5) == "draw:" then
				icon = drawIcon(inner, tostring(iconId):sub(6))
			elseif tostring(iconId):sub(1, 6) == "glyph:" then
				-- icono hecho con un simbolo de texto (ej. el infinito de Immortal)
				icon = new("TextLabel", { Parent = inner, LayoutOrder = 1, Size = UDim2.fromOffset(16, 14), BackgroundTransparency = 1, Text = tostring(iconId):sub(7), Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = K.mute, ZIndex = 3 })
			elseif tostring(iconId):sub(1, 6) == "sheet:" then
				-- icono de una hoja de iconos (Lucide): "sheet:ID:x:y" (48x48)
				local id, x, y = tostring(iconId):match("^sheet:(%d+):(%d+):(%d+)$")
				icon = new("ImageLabel", { Parent = inner, LayoutOrder = 1, Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Image = "rbxassetid://" .. tostring(id), ImageRectOffset = Vector2.new(tonumber(x) or 0, tonumber(y) or 0), ImageRectSize = Vector2.new(48, 48), ImageColor3 = K.mute, ZIndex = 3 })
			else
				icon = new("ImageLabel", { Parent = inner, LayoutOrder = 1, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Image = "rbxassetid://" .. tostring(iconId), ImageColor3 = K.mute, ZIndex = 3 })
			end
		end
		local label = txt(inner, { LayoutOrder = 2, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = name, Font = FB, TextSize = 13, TextColor3 = K.mute, TextStrokeColor3 = WHITE, TextStrokeTransparency = 1, ZIndex = 3 })
		local fade = new("UIGradient", { Parent = label, Color = FADE, Enabled = false })
		-- pastilla de la pestaña elegida (dentro del boton, nunca se corta)
		local pill = new("Frame", { Parent = btn, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 0, 28), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, { corner(8) })
		local pillStroke = new("UIStroke", { Parent = pill, Color = WHITE, Thickness = 1, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		-- linea roja dentro de la pastilla, abajo
		local bar = new("Frame", { Parent = pill, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(0, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(45, 125, 255), BorderSizePixel = 0, ZIndex = 3 }, { corner(1) })
		pill.Visible = false -- (ahora va el cristal liquido)
		local isc = new("UIScale", { Parent = inner, Scale = 0.84 })
		local t = { idx = idx, name = name, button = btn, label = label, icon = icon, fade = fade, bar = bar, pill = pill, pillStroke = pillStroke, inner = inner, isc = isc, sel = false }
		tabs[name] = t
		table.insert(tabList, t)
		-- en movil no hay "raton encima": solo color al pasar el raton en PC, sin cambiar tamaño
		local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
		btn.MouseEnter:Connect(function() if not touchOnly and not t.sel then tween(label, 0.2, { TextColor3 = K.soft }) end end)
		btn.MouseLeave:Connect(function() if not t.sel then tween(label, 0.2, { TextColor3 = K.mute }) end end)
		btn.Activated:Connect(function()
			if glassMoved then return end -- (fue un arrastre, ya se eligio al soltar)
			if currentTab ~= name then sfx("tap") end
			selectTab(name)
		end)
		-- al pulsar empieza el arrastre: el cristal sigue al dedo y cambia de seccion al pasar
		btn.InputBegan:Connect(function(i)
			if isPress(i) and not glassDragging then
				glassDragging = true
				glassInput = i
				glassStartX = i.Position.X
				glassLastPos = Vector2.new(i.Position.X, i.Position.Y)
				glassMoved = false
			end
		end)
		for _, tt in ipairs(tabList) do tt.button.Size = UDim2.new(1 / #tabList, -6 + 6 / #tabList, 1, 0) end
		if currentTab and tabs[currentTab] then moveGlass(tabs[currentTab].idx, true) end
		if idx == 1 then selectTab(name, true) end
		return p
	end

	-----------------------------------------------------------------------
	-- grupos y filas
	-----------------------------------------------------------------------
	local groupSeq = 0
	local function makeGroupBox(p, title, side)
		groupSeq += 1
		local c = (side == "right" and 2) or (side == "left" and 1) or (p.count[1] <= p.count[2] and 1 or 2)
		p.count[c] += 1
		-- tarjeta de cristal liquido: reflejo claro arriba que baja a oscuro, borde blanco que se apaga
		local box = new("Frame", { Parent = p.cols[c], LayoutOrder = p.count[c], Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, { corner(14) })
		new("UIGradient", { Parent = box, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 76, 96)), ColorSequenceKeypoint.new(0.1, Color3.fromRGB(34, 38, 52)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(20, 22, 30)), ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 15, 20)) }) })
		local st = new("UIStroke", { Color = WHITE, Thickness = 1.1, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		new("UIGradient", { Parent = st, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(180, 200, 235)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.62) }) })
		st.Parent = box
		local sc = new("UIScale", { Parent = box })
		new("UIListLayout", { Parent = box, SortOrder = Enum.SortOrder.LayoutOrder })
		local hd = new("Frame", { Parent = box, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 })
		-- (sin cuadradito blanco delante del titulo)
		txt(hd, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Text = string.upper(tostring(title)), Font = FB, TextSize = 10, TextColor3 = K.mute, TextTruncate = Enum.TextTruncate.AtEnd })
		box:SetAttribute("VIREX_Order", groupSeq)
		local g = { box = box, n = 0 }
		table.insert(p.groups, { sc = sc, st = st, box = box })
		return g
	end

	-- fila base: linea arriba, titulo y descripcion
	local function row(parent, order, h, title, desc, maxW, top)
		local r = new("Frame", { Parent = parent, LayoutOrder = order, Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true })
		-- (sin linea entre filas)
		local hasDesc = desc ~= nil and tostring(desc) ~= "" and tostring(desc) ~= tostring(title)
		local up = hasDesc or top
		local tl = txt(r, { Position = UDim2.fromOffset(12, up and 7 or 0), Size = UDim2.new(1, -24, 0, up and 15 or 40), Text = tostring(title), Font = FB, TextSize = 12, TextColor3 = K.soft, TextTruncate = Enum.TextTruncate.AtEnd })
		new("UISizeConstraint", { Parent = tl, MaxSize = Vector2.new(maxW or 170, 1000) })
		if hasDesc then
			txt(r, { Position = UDim2.fromOffset(12, 22), Size = UDim2.new(0.62, -12, 0, 13), Text = tostring(desc), Font = F, TextSize = 10, TextColor3 = K.mute, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		return r, tl
	end
	local function hover(r)
		local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
		local rsc = new("UIScale", { Parent = r })
		local function press(i) if isPress(i) then tween(rsc, 0.12, { Scale = 0.985 }, Enum.EasingStyle.Quad) end end
		local function release(i) if isPress(i) then tween(rsc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back) end end
		r.InputBegan:Connect(press)
		r.InputEnded:Connect(release)
		-- tambien cuando se toca un boton de la fila (el boton se queda con el toque)
		r.DescendantAdded:Connect(function(d)
			if d:IsA("GuiButton") then
				d.InputBegan:Connect(press)
				d.InputEnded:Connect(release)
			end
		end)
		-- al pasar el raton / tocar: la fila se marca con la misma gota de cristal que la seccion elegida
		local hl = new("Frame", { Parent = r, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -6), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
		local hlSt = new("UIStroke", { Parent = hl, Color = WHITE, Thickness = 1.1, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local hlTint = new("Frame", { Parent = hl, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
		new("UIGradient", { Parent = hlTint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.95) }) })
		local hlGloss = new("Frame", { Parent = hl, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
		new("UIGradient", { Parent = hlGloss, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(0.45, 0.93), NumberSequenceKeypoint.new(1, 1) }) })
		local hlSc = new("UIScale", { Parent = hl })
		local function lit(on)
			tween(hl, 0.3, { BackgroundTransparency = on and 0.955 or 1 }, Enum.EasingStyle.Quint)
			tween(hlTint, 0.3, { BackgroundTransparency = on and 0.6 or 1 }, Enum.EasingStyle.Quint)
			tween(hlGloss, 0.3, { BackgroundTransparency = on and 0.4 or 1 }, Enum.EasingStyle.Quint)
			tween(hlSt, 0.3, { Transparency = on and 0.82 or 1 }, Enum.EasingStyle.Quint)
		end
		r.MouseEnter:Connect(function() if not touchOnly then lit(true) end end)
		r.MouseLeave:Connect(function() if not touchOnly then lit(false) end end)
		-- en movil: se marca al tocar y se apaga solo
		if touchOnly then
			local litId = 0
			local function touchLit(i)
				if not isPress(i) then return end
				litId += 1
				local my = litId
				lit(true)
				task.delay(0.6, function() if my == litId then lit(false) end end)
			end
			r.InputBegan:Connect(touchLit)
			r.DescendantAdded:Connect(function(d) if d:IsA("GuiButton") then d.InputBegan:Connect(touchLit) end end)
		end
	end
	local function args(flag, v)
		if type(flag) == "table" then v = flag flag = v.flag end
		return flag, v or {}
	end
	local function boxButton(parent, w, text)
		-- boton de cristal liquido (como la pestaña elegida): base translucida, borde blanco que se apaga,
		-- toque frio en diagonal, reflejo arriba y sombra debajo
		local shadow = new("Frame", { Parent = parent, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 23), Size = UDim2.fromOffset(w, 24), BackgroundColor3 = BLACK, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 2 }, { corner(12) })
		local b = new("TextButton", { Parent = parent, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 20), Size = UDim2.fromOffset(w, 24), BackgroundColor3 = Color3.fromRGB(28, 32, 44), BackgroundTransparency = 0.35, AutoButtonColor = false, Text = "", ZIndex = 3 }, { corner(12) })
		local s = new("UIStroke", { Parent = b, Color = WHITE, Thickness = 1.2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		new("UIGradient", { Parent = s, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(185, 210, 245)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.4) }) })
		local tint = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 195, 255), BorderSizePixel = 0, ZIndex = 3 }, { corner(12) })
		new("UIGradient", { Parent = tint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.6, 0.93), NumberSequenceKeypoint.new(1, 0.97) }) })
		local gl = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, { corner(12) })
		new("UIGradient", { Parent = gl, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.68), NumberSequenceKeypoint.new(0.45, 0.92), NumberSequenceKeypoint.new(1, 1) }) })
		local l = txt(b, { Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 1, 0), Text = tostring(text or ""), Font = FB, TextSize = 11, TextColor3 = WHITE, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
		local bsc = new("UIScale", { Parent = b })
		local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
		b.MouseEnter:Connect(function()
			if touchOnly then return end
			tween(b, 0.25, { BackgroundTransparency = 0.2 })
			tween(s, 0.25, { Thickness = 1.6 })
			tween(bsc, 0.3, { Scale = 1.04 }, Enum.EasingStyle.Back)
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.3, { BackgroundTransparency = 0.35 })
			tween(s, 0.3, { Thickness = 1.2 })
			tween(bsc, 0.3, { Scale = 1 })
		end)
		b.InputBegan:Connect(function(i) if isPress(i) then tween(bsc, 0.1, { Scale = 0.94 }, Enum.EasingStyle.Quad) end end)
		b.InputEnded:Connect(function(i) if isPress(i) then tween(bsc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back) end end)
		b:GetPropertyChangedSignal("Visible"):Connect(function() shadow.Visible = b.Visible end)
		return b, l, s
	end
	local function flashBtn(b, l)
		if true then
			ripple(b, UDim2.fromScale(0.5, 0.5), WHITE, 10, math.max(b.AbsoluteSize.X / math.max(fit.Scale, 0.01), 60) + 30, 6)
			tween(b, 0.08, { BackgroundColor3 = Color3.fromRGB(170, 190, 220) })
			task.delay(0.14, function() tween(b, 0.4, { BackgroundColor3 = Color3.fromRGB(28, 32, 44) }) end)
			return
		end
		ripple(b, UDim2.fromScale(0.5, 0.5), WHITE, 10, math.max(b.AbsoluteSize.X / math.max(fit.Scale, 0.01), 60) + 30, 6)
		tween(b, 0.08, { BackgroundColor3 = WHITE })
		tween(l, 0.08, { TextColor3 = BLACK })
		task.delay(0.14, function()
			tween(b, 0.35, { BackgroundColor3 = BLACK })
			tween(l, 0.35, { TextColor3 = WHITE })
		end)
	end

	local function makeGroup(p, gTitle, side)
		local g = makeGroupBox(p, gTitle, side)
		local function nextOrder() g.n += 10 return g.n end

		function g:create_toggle(flag, v)
			flag, v = args(flag, v)
			local state = v.default == true
			if flag and rt._flags[flag] ~= nil then state = rt._flags[flag] == true end
			local order = nextOrder()
			local r, tl = row(g.box, order, 40, v.title or flag or "Toggle", v.description, 185)
			hover(r)
			local tfade = new("UIGradient", { Parent = tl, Color = FADE, Enabled = false })
			local hit = new("TextButton", { Parent = r, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 2 })
			-- interruptor de cristal liquido: carril translucido con reflejo; al encender se llena de rojo
			local track = new("Frame", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 20), Size = UDim2.fromOffset(40, 22), BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 3 }, { corner(11) })
			local ts = stroke(WHITE, 1, 0.55)
			ts.Parent = track
			new("UIGradient", { Parent = ts, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.7) }) })
			local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, { corner(11) })
			new("UIGradient", { Parent = fill, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 185, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 95, 225)) }) })
			local tGloss = new("Frame", { Parent = track, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 4 }, { corner(11) })
			new("UIGradient", { Parent = tGloss, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(0.5, 0.94), NumberSequenceKeypoint.new(1, 1) }) })
			-- bolita de cristal (blanca con reflejo y borde fino)
			local knob = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 11, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, { corner(9) })
			new("UIGradient", { Parent = knob, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(208, 208, 215)) }) })
			local kst = stroke(BLACK, 1, 0.78)
			kst.Parent = knob
			local m = { frame = r, _order = order, _group = g, _tl = tl }
			local function render(anim)
				local pos = state and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)
				-- apagado = cristal transparente, encendido = cristal rojo (el texto se queda igual)
				tl.TextColor3 = WHITE
				local fillT = state and 0.12 or 1
				local stC = state and Color3.fromRGB(160, 205, 255) or WHITE
				if anim then
					-- la bolita se estira mientras viaja (como una gota) y vuelve a su forma
					tween(knob, 0.16, { Size = UDim2.fromOffset(25, 16) }, Enum.EasingStyle.Quad)
					tween(knob, 0.45, { Position = pos }, Enum.EasingStyle.Back)
					task.delay(0.16, function() tween(knob, 0.32, { Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Back) end)
					tween(fill, 0.3, { BackgroundTransparency = fillT }, Enum.EasingStyle.Quint)
					tween(ts, 0.3, { Color = stC, Transparency = state and 0.3 or 0.55 }, Enum.EasingStyle.Quint)
					-- al encender: onda roja que sale de la bolita
					if state then ripple(track, pos, WHITE, 16, 42, 7) end
				else
					knob.Position, fill.BackgroundTransparency = pos, fillT
					ts.Color, ts.Transparency = stC, state and 0.3 or 0.55
				end
				tfade.Enabled = false
			end
			render(false)
			function m:set_value(val, silent)
				state = val == true
				if flag then rt._flags[flag] = state rt._changed() end
				render(true)
				if m.notify_on and not silent then notify(tostring(v.title or flag or "Toggle"), state and "Enabled" or "Disabled", 1.6) end
				if not silent then safe(v.callback, state) end
			end
			function m:get_value() return state end
			function m:set_visible(x) r.Visible = x if m._sub then m._sub.Visible = x and m._open or false end end
			function m:is_visible() return r.Visible end
			if flag then rt._flags[flag] = state end
			hit.Activated:Connect(function()
				m:set_value(not state)
				sfx(state and "toggle_on" or "toggle_off")
			end)
			-- tecla asignada (se configura en el desplegable de ajustes)
			local bindText = "None"
			local bind
			bind = { key = nil, hold = false,
				fn = function() if bind.hold then m:set_value(true) else m:set_value(not state) end end,
				release = function() if bind.hold then m:set_value(false) end end }
			if flag then
				local k = keyFromName(rt._flags[flag .. "__key"])
				if k then bind.key = k bindText = k.Name end
			end
			table.insert(binds, bind)
			m.start_bind = function(done)
				bindText = "..."
				capturing = function(code)
					if code == Enum.KeyCode.Escape or code == Enum.KeyCode.Backspace then
						bind.key = nil
						bindText = "None"
					else
						bind.key = code
						bindText = code.Name
					end
					if flag then rt._flags[flag .. "__key"] = bind.key and bind.key.Name or nil rt._changed() end
					if done then done(bindText) end
				end
			end
			m.bind_text = function() return bindText end
			m.kind, m.title, m.desc = "toggle", v.title or flag, v.description
			m.notify_on = false
			m._row, m._track = r, track
			if state and v.callback then task.defer(safe, v.callback, state) end
			return m
		end

		function g:create_slider(flag, v)
			flag, v = args(flag, v)
			local mn, mx = tonumber(v.minimum) or 0, tonumber(v.maximum) or 100
			local def = math.clamp(tonumber(v.default) or mn, mn, mx)
			local value = def
			if flag and tonumber(rt._flags[flag]) then value = math.clamp(tonumber(rt._flags[flag]), mn, mx) end
			local r = row(g.box, nextOrder(), 48, v.title or flag or "Slider", nil, 170, true)
			hover(r)
			local valTxt = txt(r, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), Size = UDim2.fromOffset(80, 15), Text = "", Font = FB, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right })
			local hitBar = new("TextButton", { Parent = r, Position = UDim2.new(0, 6, 0, 24), Size = UDim2.new(1, -12, 0, 20), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3 })
			local track = new("Frame", { Parent = r, Position = UDim2.new(0, 12, 0, 33), Size = UDim2.new(1, -24, 0, 4), BackgroundColor3 = Color3.fromRGB(26, 32, 46), BorderSizePixel = 0, ZIndex = 2 }, { corner(2) })
			local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, { corner(2) })
			new("UIGradient", { Parent = fill, Color = ColorSequence.new(Color3.fromRGB(150, 175, 215), WHITE) })
			local knob = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			new("UIStroke", { Parent = knob, Color = Color3.fromRGB(120, 130, 150), Thickness = 1, Transparency = 0.3 })
			new("UIGradient", { Parent = knob, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 222, 255)) })
			local function snap(x)
				local inc = tonumber(v.increment)
				if inc and inc > 0 and inc < 1 then
					local s = math.floor(x / inc + 0.5) * inc
					return math.floor(s * 1000 + 0.5) / 1000
				end
				if v.rounding == true then return math.floor(x + 0.5) end
				return math.floor(x * 10 + 0.5) / 10
			end
			local function render(val, anim)
				local a = mx > mn and (val - mn) / (mx - mn) or 0
				if anim then
					tween(fill, 0.1, { Size = UDim2.fromScale(a, 1) }, Enum.EasingStyle.Quad)
					tween(knob, 0.1, { Position = UDim2.fromScale(a, 0.5) }, Enum.EasingStyle.Quad)
				else
					fill.Size = UDim2.fromScale(a, 1)
					knob.Position = UDim2.fromScale(a, 0.5)
				end
				valTxt.Text = tostring(val) .. (v.suffix or "")
			end
			render(value)
			local m = { frame = r }
			local function commit(val, silent, anim)
				val = math.clamp(snap(val), mn, mx)
				value = val
				render(val, anim)
				if flag then rt._flags[flag] = val rt._changed() end
				if not silent then safe(v.callback, val) end
			end
			function m:set_value(val, silent) commit(tonumber(val) or mn, silent, true) end
			function m:get_value() return value end
			function m:set_visible(x) r.Visible = x end
			if flag then rt._flags[flag] = value end
			m.kind, m.title, m.desc, m.min, m.max, m.suffix = "slider", v.title or flag, v.description, mn, mx, v.suffix
			m.default = def
			if value ~= def then task.defer(safe, v.callback, value) end
			local dragging = false
			local function fromX(px) commit(mn + math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1) * (mx - mn), false, false) end
			hitBar.InputBegan:Connect(function(i)
				if isPress(i) then
					dragging = true
					lockScroll(true)
					tween(knob, 0.2, { Size = UDim2.fromOffset(17, 17) }, Enum.EasingStyle.Back)
					tween(valTxt, 0.2, { TextColor3 = WHITE })
					fromX(i.Position.X)
				end
			end)
			UIS.InputChanged:Connect(function(i) if dragging and isMove(i) then fromX(i.Position.X) end end)
			UIS.InputEnded:Connect(function(i)
				if dragging and isPress(i) then
					dragging = false
					lockScroll(false)
					tween(knob, 0.3, { Size = UDim2.fromOffset(13, 13) }, Enum.EasingStyle.Back)
				end
			end)
			return m
		end

		function g:create_dropdown(flag, v)
			flag, v = args(flag, v)
			local opts = v.options or {}
			local cur = v.default
			if cur == nil then cur = opts[1] end
			local def = cur
			if flag and rt._flags[flag] ~= nil and table.find(opts, rt._flags[flag]) then cur = rt._flags[flag] end
			local r = row(g.box, nextOrder(), 40, v.title or flag or "Dropdown", v.description, 118)
			local b, bl = boxButton(r, 128, "")
			local arrow = txt(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -7, 0.5, 0), Size = UDim2.fromOffset(10, 10), Text = "▾", Font = FB, TextSize = 11, TextColor3 = K.mute, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
			bl.Size = UDim2.new(1, -26, 1, 0)
			local list = new("ScrollingFrame", { Parent = r, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 3 })
			new("UIListLayout", { Parent = list, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
			local m = { frame = r }
			local isOpen = false
			local function paint() bl.Text = cur ~= nil and tostring(cur) or "None" end
			local function build()
				for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
				for i, o in ipairs(opts) do
					local on = o == cur
					local ob = new("TextButton", { Parent = list, LayoutOrder = i, Size = UDim2.new(1, -4, 0, 24), BackgroundColor3 = WHITE, BackgroundTransparency = on and 0.92 or 1, AutoButtonColor = false, Text = "", ZIndex = 4 }, { corner(4) })
					txt(ob, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Text = tostring(o), Font = on and FB or F, TextSize = 11, TextColor3 = on and WHITE or K.mute, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
					if on then new("Frame", { Parent = ob, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, { corner(2) }) end
					ob.MouseEnter:Connect(function() if o ~= cur then tween(ob, 0.15, { BackgroundTransparency = 0.96 }) end end)
					ob.MouseLeave:Connect(function() if o ~= cur then tween(ob, 0.2, { BackgroundTransparency = 1 }) end end)
					ob.Activated:Connect(function()
						sfx("tap")
						m:set_value(o)
						m._toggle(false)
					end)
				end
			end
			local function setOpen(x)
				isOpen = x
				if x then
					closeDrops(m._toggle)
					openDrops[m._toggle] = true
					build()
				else
					openDrops[m._toggle] = nil
				end
				local lh = math.min(#opts, 6) * 26
				tween(r, 0.4, { Size = UDim2.new(1, 0, 0, x and (46 + lh) or 40) })
				tween(list, 0.4, { Size = UDim2.new(1, -24, 0, x and lh or 0) })
				tween(arrow, 0.3, { Rotation = x and 180 or 0, TextColor3 = x and WHITE or K.mute })
			end
			m._toggle = setOpen
			paint()
			function m:set_value(val, silent)
				cur = val
				paint()
				if isOpen then build() end
				if flag then rt._flags[flag] = val rt._changed() end
				if not silent then safe(v.callback, val) end
			end
			function m:get_value() return cur end
			function m:set_options(o, sel)
				opts = o or {}
				if sel ~= nil then cur = sel elseif not table.find(opts, cur) then cur = opts[1] end
				paint()
				if isOpen then build() setOpen(true) end
			end
			function m:add_option(o, sel) table.insert(opts, o) if sel then self:set_value(o) end if isOpen then build() end end
			function m:get_options() return opts end
			function m:set_visible(x) r.Visible = x end
			function m:unfold() setOpen(true) end
			function m:set_locked_open() end
			if flag then rt._flags[flag] = cur end
			b.Activated:Connect(function() sfx("tap") setOpen(not isOpen) end)
			if cur ~= def then task.defer(safe, v.callback, cur) end
			m.kind, m.title, m.desc = "dropdown", v.title or flag, v.description
			return m
		end

		function g:create_button(flag, v)
			flag, v = args(flag, v)
			local r = row(g.box, nextOrder(), 40, v.title or "Button", v.description, 160)
			hover(r)
			local b, bl = boxButton(r, 84, tostring(v.button_text or "Run"))
			bl.TextXAlignment = Enum.TextXAlignment.Center
			local bs = new("UIScale", { Parent = b })
			b.Activated:Connect(function()
				sfx("tap")
				bs.Scale = 0.92
				tween(bs, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				flashBtn(b, bl)
				safe(v.callback)
			end)
			return { frame = r, set_visible = function(_, x) r.Visible = x end }
		end

		function g:create_textbox(flag, v)
			flag, v = args(flag, v)
			local r = row(g.box, nextOrder(), 40, v.title or flag or "Text", v.description, 118)
			local box = new("TextBox", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 20), Size = UDim2.fromOffset(140, 24), BackgroundColor3 = BLACK, Text = (flag and type(rt._flags[flag]) == "string") and rt._flags[flag] or tostring(v.default or ""), PlaceholderText = tostring(v.placeholder or ""), PlaceholderColor3 = K.mute, TextColor3 = WHITE, Font = F, TextSize = 11, ClearTextOnFocus = false, ClipsDescendants = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, { corner(5) })
			new("UIPadding", { Parent = box, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
			local s = stroke(K.line2, 1, 0)
			s.Parent = box
			box.Focused:Connect(function() sfx("tap") tween(s, 0.2, { Color = WHITE }) end)
			box.FocusLost:Connect(function(enter)
				tween(s, 0.25, { Color = K.line2 })
				if flag then rt._flags[flag] = box.Text rt._changed() end
				safe(v.callback, box.Text, enter)
			end)
			local m = { frame = r }
			function m:get_value() return box.Text end
			function m:get_display_value() return box.Text end
			function m:set_value(x) box.Text = tostring(x or "") end
			function m:clear() box.Text = "" end
			function m:focus() box:CaptureFocus() end
			function m:set_visible(x) r.Visible = x end
			function m:is_visible() return r.Visible end
			return m
		end

		function g:create_keybind(flag, v)
			flag, v = args(flag, v)
			local r = row(g.box, nextOrder(), 40, v.title or "Keybind", v.description, 170)
			local b, bl = boxButton(r, 74, "None")
			bl.TextXAlignment = Enum.TextXAlignment.Center
			local bind = { key = nil, fn = function() safe(v.callback) end }
			if flag then
				local k = keyFromName(rt._flags[flag])
				if k then bind.key = k bl.Text = k.Name end
			end
			table.insert(binds, bind)
			b.Activated:Connect(function()
				sfx("tap")
				bl.Text = "..."
				capturing = function(code)
					if code == Enum.KeyCode.Escape or code == Enum.KeyCode.Backspace then bind.key = nil bl.Text = "None" else bind.key = code bl.Text = code.Name end
					if flag then rt._flags[flag] = bind.key and bind.key.Name or nil rt._changed() end
				end
			end)
			return { frame = r, set_visible = function(_, x) r.Visible = x end }
		end
		return g
	end

	-----------------------------------------------------------------------
	-- ajustes vinculados: se despliegan debajo de la funcion
	-----------------------------------------------------------------------
	function rt:link(owner, list, resettable)
		if not owner or not owner._row then return end
		local r = owner._row
		local g = owner._group
		if not owner._sub then
			local sub = new("Frame", { Parent = g.box, LayoutOrder = owner._order + 1, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false })
			-- tarjeta de cristal liquido (azul oscuro, borde blanco -> azul, toque azul en diagonal y reflejo)
			local NEONL = Color3.fromRGB(70, 155, 255)
			local card = new("Frame", { Parent = sub, Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 1, -8), BackgroundColor3 = Color3.fromRGB(30, 34, 46), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
			local cst = new("UIStroke", { Parent = card, Color = WHITE, Thickness = 1, Transparency = 0.2 })
			new("UIGradient", { Parent = cst, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(185, 210, 245)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.6) }) })
			local ctint = new("Frame", { Parent = card, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 195, 255), BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
			new("UIGradient", { Parent = ctint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.6, 0.95), NumberSequenceKeypoint.new(1, 0.98) }) })
			local cgl = new("Frame", { Parent = card, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1 }, { corner(12) })
			new("UIGradient", { Parent = cgl, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(1, 1) }) })
			-- linea fina de cristal a la izquierda (blanca, se apaga en las puntas)
			local line = new("Frame", { Parent = card, Position = UDim2.fromOffset(10, 12), Size = UDim2.new(0, 1, 1, -24), BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2 })
			new("UIGradient", { Parent = line, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }) })
			local inner = new("Frame", { Parent = sub, Position = UDim2.fromOffset(16, 2), Size = UDim2.new(1, -22, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 2 })
			local lay = new("UIListLayout", { Parent = inner, SortOrder = Enum.SortOrder.LayoutOrder })
			-- cuadro de referencia de 100x100 para pasar pixeles de pantalla a tamaño real del panel
			-- (en pantallas grandes el panel esta agrandado y la altura salia de mas: dejaba un hueco)
			local ref = new("Frame", { Parent = sub, Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, Visible = true })
			local function contentH()
				local k = ref.AbsoluteSize.Y / 100
				if k <= 0.01 then k = 1 end
				return math.ceil(lay.AbsoluteContentSize.Y / k)
			end
			owner._sub, owner._inner, owner._open, owner._n = sub, inner, false, 0
			-- flecha para desplegar
			-- boton redondo de cristal con una flecha dibujada (antes era un simbolo de texto)
			local chev = new("TextButton", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -58, 0, 20), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromRGB(40, 44, 58), BackgroundTransparency = 0.55, AutoButtonColor = false, Text = "", ZIndex = 5 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			local chevSt = new("UIStroke", { Parent = chev, Color = WHITE, Thickness = 1, Transparency = 0.7 })
			new("UIGradient", { Parent = chev, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.4) }) })
			local chevT = new("Frame", { Parent = chev, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Rotation = -90, ZIndex = 6 })
			-- dos palitos que se juntan abajo en el centro = "v" (girada -90 = ">")
			new("Frame", { Parent = chevT, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -2.4, 0.5, -0.8), Size = UDim2.fromOffset(7.4, 2), Rotation = 45, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			new("Frame", { Parent = chevT, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 2.4, 0.5, -0.8), Size = UDim2.fromOffset(7.4, 2), Rotation = -45, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			chev.MouseEnter:Connect(function() tween(chev, 0.2, { BackgroundTransparency = 0.35 }) end)
			chev.MouseLeave:Connect(function() tween(chev, 0.2, { BackgroundTransparency = 0.55 }) end)
			local function setSub(x)
				owner._open = x
				local hgt = contentH()
				if x then
					sub.Visible = r.Visible
					tween(sub, 0.5, { Size = UDim2.new(1, 0, 0, hgt + 12) }, Enum.EasingStyle.Quint)
				else
					tween(sub, 0.35, { Size = UDim2.new(1, 0, 0, 0) }).Completed:Connect(function() if not owner._open then sub.Visible = false end end)
				end
				tween(chevT, 0.4, { Rotation = x and 0 or -90 }, Enum.EasingStyle.Back)
				tween(chevSt, 0.3, { Transparency = x and 0.3 or 0.7 })
				-- la tarjeta de cristal aparece suave (antes se veia una raya fea mientras se abria)
				if x then
					card.BackgroundTransparency, cst.Transparency, ctint.BackgroundTransparency, cgl.BackgroundTransparency, line.BackgroundTransparency = 1, 1, 1, 1, 1
					tween(card, 0.4, { BackgroundTransparency = 0.45 }, Enum.EasingStyle.Quad)
					tween(cst, 0.45, { Transparency = 0.2 }, Enum.EasingStyle.Quad)
					tween(ctint, 0.45, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
					tween(cgl, 0.45, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
					tween(line, 0.5, { BackgroundTransparency = 0.45 }, Enum.EasingStyle.Quad)
				else
					tween(card, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					tween(cst, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad)
					tween(ctint, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					tween(cgl, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					tween(line, 0.15, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				end
			end
			lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if owner._open then sub.Size = UDim2.new(1, 0, 0, contentH() + 12) end
			end)
			chev.Activated:Connect(function() sfx("tap") setSub(not owner._open) end)
			owner._setSub = setSub
			-- tecla para esta funcion
			if owner.start_bind then
				owner._n += 1
				local kr = row(inner, owner._n, 40, "Keybind", nil)
				local kb, kl = boxButton(kr, 74, owner.bind_text())
				kl.TextXAlignment = Enum.TextXAlignment.Center
				kb.Activated:Connect(function()
					sfx("tap")
					kl.Text = "..."
					owner.start_bind(function(t) if kl.Parent then kl.Text = t end end)
				end)
			end
		end
		for _, hd in ipairs(list or {}) do
			if hd and hd.frame then
				owner._n += 1
				hd.frame.Parent = owner._inner
				hd.frame.LayoutOrder = owner._n
				owner._links = owner._links or {}
				table.insert(owner._links, hd)
			end
		end
		if resettable and not owner._reset then
			owner._reset = true
			local rr = row(owner._inner, 9999, 40, "Reset all to default", nil, 150)
			local rb, rl = boxButton(rr, 84, "Reset")
			rl.TextXAlignment = Enum.TextXAlignment.Center
			rb.Activated:Connect(function()
				sfx("tap")
				for _, hd in ipairs(owner._links or {}) do
					if hd.kind == "slider" and hd.default ~= nil then pcall(function() hd:set_value(hd.default) end) end
				end
				flashBtn(rb, rl)
				rl.Text = "Done"
				task.delay(0.9, function() if rl.Parent then rl.Text = "Reset" end end)
			end)
		end
	end

	-- saca una opcion de los ajustes de otra (o la devuelve dentro) con animacion:
	-- al separarla sale "de dentro" de la opcion padre como una tarjeta de cristal rojo
	function rt:detach(owner, hd, separate, instant)
		if not owner or not owner._row or not hd or not hd.frame then return end
		local f = hd.frame
		local g = owner._group
		if not hd._h then
			local okH, h = pcall(function() return f.Size.Y.Offset end)
			hd._h = (okH and type(h) == "number" and h > 0) and h or 40
		end
		hd._linkOrder = hd._linkOrder or f.LayoutOrder
		local H = hd._h
		if separate then
			if f.Parent == g.box then return end
			f.Parent = g.box
			f.LayoutOrder = owner._order + 2
			f.Visible = owner._row.Visible
			if instant then f.Size = UDim2.new(1, 0, 0, H) return end
			-- la opcion padre "empuja" y de ella sale la nueva fila
			local osc = owner._row:FindFirstChildOfClass("UIScale")
			if osc then osc.Scale = 1.04 tween(osc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back) end
			f.Size = UDim2.new(1, 0, 0, 0)
			local fsc = f:FindFirstChildOfClass("UIScale")
			if fsc then fsc.Scale = 0.8 tween(fsc, 0.6, { Scale = 1 }, Enum.EasingStyle.Back) end
			tween(f, 0.5, { Size = UDim2.new(1, 0, 0, H) }, Enum.EasingStyle.Quint)
			-- destello de cristal rojo + brillo que la cruza
			local fl = new("Frame", { Parent = f, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -4), BackgroundColor3 = Color3.fromRGB(45, 135, 255), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1 }, { corner(10) })
			local flSt = new("UIStroke", { Parent = fl, Color = WHITE, Thickness = 1.2, Transparency = 0.1 })
			new("UIGradient", { Parent = flSt, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) }) })
			local shG = new("UIGradient", { Parent = fl, Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.45, 0.2), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.55, 0.2), NumberSequenceKeypoint.new(1, 0.2) }) })
			tween(shG, 0.8, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad)
			task.delay(0.35, function()
				tween(fl, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint)
				tween(flSt, 0.7, { Transparency = 1 }, Enum.EasingStyle.Quint)
			end)
			task.delay(1.1, function() pcall(function() fl:Destroy() end) end)
			sfx("toggle_on")
		else
			if f.Parent == owner._inner then return end
			local function back()
				f.Parent = owner._inner
				f.LayoutOrder = hd._linkOrder
				f.Size = UDim2.new(1, 0, 0, H)
				f.Visible = true
			end
			if instant then back() return end
			-- vuelve a meterse dentro de la opcion padre
			local fsc = f:FindFirstChildOfClass("UIScale")
			if fsc then tween(fsc, 0.35, { Scale = 0.85 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In) end
			tween(f, 0.35, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.37, function()
				back()
				if fsc then fsc.Scale = 1 end
				local osc = owner._row:FindFirstChildOfClass("UIScale")
				if osc then osc.Scale = 0.97 tween(osc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back) end
			end)
			sfx("toggle_off")
		end
	end

	-- "separar": Auto Spam sale de dentro de Auto Parry.
	-- Auto Parry se carga (se hunde y su borde se enciende en rojo), explota en chispas, de el sale
	-- una tarjeta de cristal rojo un poco inclinada unida por un rayo de energia, baja a su sitio,
	-- aterriza con una onda y se funde con la opcion de verdad (su nombre se revela).
	-- Al juntarlas pasa al reves: la tarjeta sube, las chispas se meten dentro y Auto Parry "se la traga".
	function rt:split(owner, hd, show, instant)
		if not owner or not owner._row or not hd or not hd.frame then return end
		local f = hd.frame
		if not hd._h then
			local okH, h = pcall(function() return f.Size.Y.Offset end)
			hd._h = (okH and type(h) == "number" and h > 0) and h or 40
		end
		local hh = hd._h
		f.LayoutOrder = owner._order + 2 -- justo debajo (y de sus ajustes)
		hd._splitId = (hd._splitId or 0) + 1
		local my = hd._splitId
		local fsc = f:FindFirstChildOfClass("UIScale")
		local osc = owner._row:FindFirstChildOfClass("UIScale")
		local tl = hd._tl
		if instant then
			f.Visible = show and owner._row.Visible or false
			f.Size = UDim2.new(1, 0, 0, hh)
			if fsc then fsc.Scale = 1 end
			if tl then tl.TextTransparency = 0 end
			return
		end
		local NEON = Color3.fromRGB(45, 135, 255)
		local RS = game:GetService("RunService")
		local function K() local k = win.AbsoluteSize.X / W return k > 0.01 and k or nil end
		-- posicion de algo de la ventana, en coordenadas de la ventana
		local function rect(gui, k)
			return (gui.AbsolutePosition.X - win.AbsolutePosition.X) / k, (gui.AbsolutePosition.Y - win.AbsolutePosition.Y) / k, gui.AbsoluteSize.X / k, gui.AbsoluteSize.Y / k
		end
		-- chispas: salen de un punto (o se meten en el)
		local function sparks(cx, cy, n, inward)
			if true then return end -- (sin puntitos: se veian feos)
			for i = 1, n do
				local a = (i / n) * math.pi * 2 + math.random() * 0.6
				local dist = math.random(26, 58)
				local out = UDim2.fromOffset(cx + math.cos(a) * dist, cy + math.sin(a) * dist * 0.45)
				local mid = UDim2.fromOffset(cx, cy)
				local sz = math.random(3, 5)
				local s = new("Frame", { Parent = win, AnchorPoint = Vector2.new(0.5, 0.5), Position = inward and out or mid, Size = UDim2.fromOffset(sz, sz), BackgroundColor3 = (i % 3 == 0) and WHITE or NEON, BackgroundTransparency = inward and 0.6 or 0, BorderSizePixel = 0, ZIndex = 46 }, { corner(3) })
				if inward then
					tween(s, 0.42, { Position = mid, BackgroundTransparency = 0, Size = UDim2.fromOffset(2, 2) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				else
					tween(s, 0.55, { Position = out, BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1) }, Enum.EasingStyle.Quint)
				end
				task.delay(0.6, function() pcall(function() s:Destroy() end) end)
			end
		end
		-- onda alrededor de una fila
		local function ring(x, y, w, h)
			if true then return end -- (sin aro)
			local r = new("Frame", { Parent = win, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w - 6, h - 4), BackgroundTransparency = 1, ZIndex = 44 }, { corner(12) })
			local st = new("UIStroke", { Parent = r, Color = NEON, Thickness = 2.2, Transparency = 0.05 })
			tween(r, 0.6, { Size = UDim2.fromOffset(w + 22, h + 16) }, Enum.EasingStyle.Quint)
			tween(st, 0.6, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quad)
			task.delay(0.65, function() pcall(function() r:Destroy() end) end)
		end
		-- borde rojo que se carga en la fila de Auto Parry
		local function charge(rowF, t)
			local c = new("Frame", { Parent = rowF, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -4), BackgroundColor3 = NEON, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, { corner(10) })
			local cst = new("UIStroke", { Parent = c, Color = NEON, Thickness = 1.4, Transparency = 1 })
			tween(c, t, { BackgroundTransparency = 0.82 }, Enum.EasingStyle.Quad)
			tween(cst, t, { Transparency = 0.1 }, Enum.EasingStyle.Quad)
			task.delay(t, function()
				tween(c, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint)
				tween(cst, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quint)
				task.delay(0.65, function() pcall(function() c:Destroy() end) end)
			end)
		end
		-- tarjeta de cristal rojo (copia de la fila)
		local function makeGhost(fromRow, k)
			local x, y, w, h = rect(fromRow, k)
			local g = new("Frame", { Parent = win, Position = UDim2.fromOffset(x + 4, y + 2), Size = UDim2.fromOffset(w - 8, h - 4), BackgroundColor3 = Color3.fromRGB(12, 22, 46), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 40 }, { corner(10) })
			local gst = new("UIStroke", { Parent = g, Color = WHITE, Thickness = 1.3, Transparency = 0.05 })
			new("UIGradient", { Parent = gst, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) }) })
			local tint = new("Frame", { Parent = g, Size = UDim2.fromScale(1, 1), BackgroundColor3 = NEON, BorderSizePixel = 0, ZIndex = 40 }, { corner(10) })
			new("UIGradient", { Parent = tint, Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, 0.82), NumberSequenceKeypoint.new(1, 0.95) }) })
			local gloss = new("Frame", { Parent = g, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 40 }, { corner(10) })
			new("UIGradient", { Parent = gloss, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.45, 0.94), NumberSequenceKeypoint.new(1, 1) }) })
			local t1 = txt(g, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 15), Text = tostring(hd.title or "Auto Spam"), Font = FB, TextSize = 12, TextColor3 = WHITE, ZIndex = 41 })
			local t2 = txt(g, { Position = UDim2.fromOffset(10, 21), Size = UDim2.new(1, -20, 0, 13), Text = tostring(hd.desc or ""), Font = F, TextSize = 10, TextColor3 = Color3.fromRGB(205, 222, 245), ZIndex = 41 })
			local gsc = new("UIScale", { Parent = g })
			local shine = new("Frame", { Parent = g, Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 42 }, { corner(10) })
			local shG = new("UIGradient", { Parent = shine, Rotation = 20, Offset = Vector2.new(-1.2, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }) })
			return { f = g, sc = gsc, st = gst, parts = { g, tint, gloss }, texts = { t1, t2 }, shine = shG, x = x + 4, w = w - 8, h = h - 4 }
		end
		local function fadeGhost(gh, t)
			tween(gh.f, t, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			for i = 2, #gh.parts do tween(gh.parts[i], t, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad) end
			for _, tx in ipairs(gh.texts) do tween(tx, t, { TextTransparency = 1 }, Enum.EasingStyle.Quad) end
			tween(gh.st, t, { Transparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(t + 0.05, function() pcall(function() gh.f:Destroy() end) end)
		end
		-- rayo de energia entre Auto Parry y la tarjeta
		local function makeBeam()
			local b = new("Frame", { Parent = win, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(3, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 39, Visible = false }, { corner(2) })
			new("UIGradient", { Parent = b, Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, NEON), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, NEON) }) })
			local glow = new("Frame", { Parent = b, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 9, 1, 0), BackgroundColor3 = NEON, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 38 }, { corner(4) })
			return b, glow
		end
		if show then
			-- 1) Auto Parry se carga: se hunde y su borde se pone rojo
			if osc then tween(osc, 0.2, { Scale = 0.95 }, Enum.EasingStyle.Quad) end
			charge(owner._row, 0.2)
			f.Visible = owner._row.Visible
			f.Size = UDim2.new(1, 0, 0, 0)
			if tl then tl.TextTransparency = 1 end
			task.delay(0.2, function()
				if my ~= hd._splitId then return end
				local k = K()
				if osc then tween(osc, 0.55, { Scale = 1 }, Enum.EasingStyle.Back) end
				tween(f, 0.5, { Size = UDim2.new(1, 0, 0, hh) }, Enum.EasingStyle.Quint)
				if not k then if tl then tl.TextTransparency = 0 end return end
				local ox, oy, ow, ohh = rect(owner._row, k)
				-- 2) explota: chispas desde abajo de Auto Parry
				sparks(ox + ow * 0.5, oy + ohh - 2, 10, false)
				-- 3) sale la tarjeta inclinada con un brillo, unida por el rayo
				local gh = makeGhost(owner._row, k)
				local beam, beamGlow = makeBeam()
				gh.sc.Scale = 0.96
				tween(gh.sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Quint)
				tween(gh.shine, 0.75, { Offset = Vector2.new(1.2, 0) }, Enum.EasingStyle.Quad)
				local t0 = os.clock()
				local conn
				conn = RS.RenderStepped:Connect(function()
					if not gh.f.Parent or os.clock() - t0 > 0.66 then
						if conn then conn:Disconnect() end
						return
					end
					local a = math.clamp((os.clock() - t0) / 0.58, 0, 1)
					a = 1 - (1 - a) ^ 4
					local _, fromY, _, fromH = rect(owner._row, k)
					local _, toY = rect(f, k)
					local y = fromY + (toY - fromY) * a
					gh.f.Position = UDim2.fromOffset(gh.x, y + 2)
					-- el rayo va desde el borde de abajo de Auto Parry hasta la tarjeta
					local top = fromY + fromH - 2
					beam.Position = UDim2.fromOffset(gh.x + 22, top)
					beam.Size = UDim2.fromOffset(3, math.max(y + 2 - top, 0))
				end)
				-- 4) aterriza: onda, la tarjeta se funde y el nombre de verdad se revela
				task.delay(0.62, function()
					local x, y, w, h = rect(f, k)
					ring(x, y, w, h)
					sparks(x + 26, y + h * 0.5, 6, false)
					fadeGhost(gh, 0.45)
					tween(beam, 0.35, { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 0) }, Enum.EasingStyle.Quad)
					tween(beamGlow, 0.3, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					task.delay(0.4, function() pcall(function() beam:Destroy() end) end)
					if tl then tween(tl, 0.5, { TextTransparency = 0 }, Enum.EasingStyle.Quad) end
					if fsc then fsc.Scale = 0.97 tween(fsc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back) end
				end)
			end)
			sfx("toggle_on")
		else
			local k = K()
			if not k then
				f.Visible = false
				return
			end
			-- vuelve: la tarjeta se despega de Auto Spam y sube por el rayo hasta Auto Parry
			local gh = makeGhost(f, k)
			local beam, beamGlow = makeBeam()
			for _, tx in ipairs(gh.texts) do tx.TextTransparency = 0 end
			if tl then tl.TextTransparency = 1 end
			gh.sc.Scale = 1.04
			tween(gh.sc, 0.45, { Scale = 0.88 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			local _, startY = rect(f, k)
			local t0 = os.clock()
			local conn
			conn = RS.RenderStepped:Connect(function()
				if not gh.f.Parent or os.clock() - t0 > 0.5 then
					if conn then conn:Disconnect() end
					return
				end
				local a = math.clamp((os.clock() - t0) / 0.42, 0, 1)
				a = a * a * a
				local _, toY, _, toH = rect(owner._row, k)
				local y = startY + (toY - startY) * a
				gh.f.Position = UDim2.fromOffset(gh.x, y + 2)
				local top = toY + toH - 2
				beam.Position = UDim2.fromOffset(gh.x + 22, top)
				beam.Size = UDim2.fromOffset(3, math.max(y + 2 - top, 0))
			end)
			task.delay(0.36, function() fadeGhost(gh, 0.2) end)
			-- su hueco se cierra a la vez
			tween(f, 0.42, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.44, function()
				pcall(function() beam:Destroy() end)
				local _ = beamGlow
				if my ~= hd._splitId then return end
				f.Visible = false
				f.Size = UDim2.new(1, 0, 0, hh)
				if tl then tl.TextTransparency = 0 end
				if fsc then fsc.Scale = 1 end
				-- Auto Parry "se la traga": las chispas se meten, salto, onda y brillo rojo
				local x, y, w, h = rect(owner._row, k)
				sparks(x + w * 0.5, y + h * 0.5, 10, true)
				task.delay(0.4, function()
					if osc then osc.Scale = 1.06 tween(osc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back) end
					ring(x, y, w, h)
					charge(owner._row, 0.08)
				end)
			end)
			sfx("toggle_off")
		end
	end

	function rt:create_category() return self end
	function rt:create_tab(title, iconId)
		title = tostring(title or "Tab")
		local p = getPage(title, iconId)
		local tab = {}
		function tab:create_group(gTitle, side)
			if type(gTitle) == "table" then side = gTitle.side or side gTitle = gTitle.title end
			return makeGroup(p, tostring(gTitle or "Group"), side)
		end
		function tab:set_enabled(v) if tabs[title] then tabs[title].button.Visible = v ~= false end end
		function tab:is_enabled() return tabs[title] == nil or tabs[title].button.Visible end
		return tab
	end
	function rt:notify(msg)
		if getgenv().VIREX_TopBanner then
			local title = type(msg) == "table" and (msg.title or msg.Title) or "VIREX"
			local text = type(msg) == "table" and (msg.text or msg.content or msg.Content or msg.description) or tostring(msg or "")
			local dur = type(msg) == "table" and (msg.duration or msg.Duration) or 2.5
			local ok = pcall(function()
				getgenv().VIREX_TopBanner({ title = string.upper(tostring(title)), text = tostring(text or ""), glyph = string.upper(tostring(title):sub(1, 1)), icon = type(msg) == "table" and msg.icon or nil, key = type(msg) == "table" and msg.key or nil, width = 250, duration = math.clamp(tonumber(dur) or 2.5, 1.2, 5) })
			end)
			if ok then return end
		end
		if type(msg) == "table" then
			notify(msg.title or msg.Title or "VIREX", msg.text or msg.content or msg.Content or msg.description or "", msg.duration or msg.Duration)
		else
			notify("VIREX", tostring(msg or ""), 3)
		end
	end
	function rt:load() return self._flags end
	function rt:close_all_dropdowns() closeDrops() end
	function rt:rebalance() for _, pg in pairs(pages) do pcall(rebalance, pg) end end
	function rt:update_keybind_list() end

	-----------------------------------------------------------------------
	-- abrir / cerrar: la ventana se despliega hacia abajo desde la cabecera
	-----------------------------------------------------------------------
	local open, token = false, 0
	local function intro(my)
		for i, t in ipairs(tabList) do
			t.label.TextTransparency = 1
			if t.icon then if t.icon:IsA("TextLabel") then t.icon.TextTransparency = 1 elseif t.icon:IsA("CanvasGroup") then t.icon.GroupTransparency = 1 else t.icon.ImageTransparency = 1 end end
			t.inner.Position = UDim2.new(0.5, 0, 0.5, 8) -- (centrado en la pestaña)
			task.delay(0.2 + (i - 1) * 0.05, function()
				if token ~= my then return end
				tween(t.label, 0.4, { TextTransparency = 0 }, Enum.EasingStyle.Quad)
				if t.icon then tween(t.icon, 0.4, (t.icon:IsA("TextLabel") and { TextTransparency = 0 }) or (t.icon:IsA("CanvasGroup") and { GroupTransparency = 0 }) or { ImageTransparency = 0 }, Enum.EasingStyle.Quad) end
				tween(t.inner, 0.5, { Position = UDim2.fromScale(0.5, 0.5) })
			end)
		end
		local p = currentTab and pages[currentTab]
		if p then
			p.group.GroupTransparency = 1
			task.delay(0.3, function()
				if token ~= my then return end
				tween(p.group, 0.4, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
				popGroups(p)
			end)
		end
		logoSc.Scale = 0.3
		tween(logoSc, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		headGrad.Color = TITLE_REVEAL
		headGrad.Offset = Vector2.new(-1, 0)
		task.delay(0.1, function() if token == my then tween(headGrad, 0.9, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) end end)
		if titleIsImage then
			titleImgGrad.Offset = Vector2.new(-1, 0)
			task.delay(0.1, function() if token == my then revealTitleImg() end end)
		end
	end
	-- el juego de detras se desenfoca mientras el panel esta abierto
	local blur
	pcall(function()
		local L = game:GetService("Lighting")
		local old = L:FindFirstChild("VIREX_Blur")
		if old then old:Destroy() end
		blur = Instance.new("BlurEffect")
		blur.Name = "VIREX_Blur"
		blur.Size = 0
		blur.Parent = L
	end)
	local CENTER = UDim2.fromScale(0.5, 0.5)
	local lastFrom = nil -- de donde salio la ventana (el logo), para volver ahi al cerrar
	-- convierte un punto de la pantalla en desplazamiento dentro de la ventana
	local function offsetFrom(pt)
		if not pt then return nil end
		local c = root.AbsolutePosition + root.AbsoluteSize / 2
		local sc = math.max(fit.Scale, 0.01)
		return UDim2.new(0.5, (pt.X - c.X) / sc, 0.5, (pt.Y - c.Y) / sc)
	end
	local fabRef -- boton del logo (se asigna al crearlo)
	local function fabCenter()
		if fabRef and fabRef.Parent then return fabRef.AbsolutePosition + fabRef.AbsoluteSize / 2 end
		return nil
	end
	local function setOpen(v, fromPt, power)
		if open == v then return end
		fromPt = fromPt or fabCenter() -- siempre sale del logo y vuelve a el
		open = v
		token += 1
		local my = token
		if v then
			refit()
			root.Visible = true
			sfx("open")
			local start = offsetFrom(fromPt)
			lastFrom = fromPt
			win.GroupTransparency = 1
			sheetGrad.Enabled = false
			win.Rotation = 0
			if power then
				-- la primera vez (al acabar la intro): aparece directamente en el centro, como una pantalla que se enciende sola
				win.Position = CENTER
				pop.Scale = 0.965
				win.GroupTransparency = 1
				task.spawn(function()
					win.GroupTransparency = 0.55
					task.wait(0.07)
					if token ~= my then return end
					win.GroupTransparency = 0.88
					task.wait(0.06)
					if token ~= my then return end
					tween(win, 0.55, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
				end)
				tween(pop, 0.9, { Scale = 1 }, Enum.EasingStyle.Quint)
			else
				-- sale del logo: crece desde el boton hasta el centro, sin girar, con un pequeño rebote al llegar
				win.Position = start or UDim2.new(0.5, 0, 0.5, 30)
				pop.Scale = start and (52 / W) or 0.85
				tween(win, 0.14, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
				tween(win, 0.5, { Position = CENTER }, Enum.EasingStyle.Quint)
				tween(pop, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			-- el logo se hunde un momento, como si "soltara" la ventana
			if not power then pcall(function()
				local fs = fabRef and fabRef:FindFirstChildOfClass("UIScale")
				if fs then fs.Scale = 0.82 tween(fs, 0.5, { Scale = 1 }, Enum.EasingStyle.Back) end
			end) end
			if blur then tween(blur, 0.6, { Size = 14 }, Enum.EasingStyle.Quad) end
			grip.BackgroundTransparency = 1
			gripSt.Transparency = 1
			rsSt.Transparency = 1
			task.delay(0.35, function() if token == my then tween(grip, 0.4, { BackgroundTransparency = 0.3 }, Enum.EasingStyle.Quad) tween(gripSt, 0.4, { Transparency = 0.5 }, Enum.EasingStyle.Quad) tween(rsSt, 0.4, { Transparency = 0.4 }, Enum.EasingStyle.Quad) end end)
			intro(my)
		else
			closeDrops()
			sfx("close")
			local target = offsetFrom(fromPt or fabCenter() or lastFrom)
			-- vuelve al logo: coge un poco de impulso y se mete encogiendose en el boton (sin girar)
			sheetGrad.Enabled = false
			tween(pop, 0.42, { Scale = target and (52 / W) or 0.85 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			tween(win, 0.42, { Position = target or UDim2.new(0.5, 0, 0.5, 24), Rotation = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.3, function() if token == my then tween(win, 0.12, { GroupTransparency = 1 }, Enum.EasingStyle.Quad) end end)
			-- al llegar, el logo "se la traga": pequeño salto
			task.delay(0.42, function()
				if token ~= my then return end
				pcall(function()
					local fs = fabRef and fabRef:FindFirstChildOfClass("UIScale")
					if fs then fs.Scale = 1.18 tween(fs, 0.45, { Scale = 1 }, Enum.EasingStyle.Back) end
				end)
			end)
			if blur then tween(blur, 0.4, { Size = 0 }, Enum.EasingStyle.Quad) end
			tween(grip, 0.15, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			tween(gripSt, 0.15, { Transparency = 1 }, Enum.EasingStyle.Quad)
			tween(rsSt, 0.15, { Transparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(0.44, function() if token == my then root.Visible = false end end)
		end
	end
	function rt._toggleWindow() setOpen(not open) end
	closeBtn.Activated:Connect(function() setOpen(false) end)
	minBtn.Activated:Connect(function() setOpen(false) end)

	-- boton flotante (abre / cierra, se puede mover)
	local fab = new("TextButton", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -44, 0.5, 0), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = Color3.fromRGB(8, 8, 10), Text = "", AutoButtonColor = false, ZIndex = 60 }, { corner(16) })
	local fabScale = new("UIScale", { Parent = fab, Scale = 0 })
	fabRef = fab
	-- borde con degradado rojo -> blanco -> rojo
	-- borde dibujado por dentro del cuadro (un marco interior), asi no sale nada fuera
	local fabInner = new("Frame", { Parent = fab, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1, ZIndex = 61 }, { corner(14) })
	local fabStroke = new("UIStroke", { Parent = fabInner, Color = WHITE, Thickness = 1.4, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	new("UIGradient", { Parent = fabStroke, Rotation = 45, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 40, 45)), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 40, 45)) }) })
	-- fondo con un toque rojo abajo
	local fabTint = new("Frame", { Parent = fab, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(235, 40, 45), BorderSizePixel = 0, ZIndex = 60 }, { corner(16) })
	new("UIGradient", { Parent = fabTint, Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.92), NumberSequenceKeypoint.new(1, 0.7) }) })
	local fabLogo = new("ImageLabel", { Parent = fab, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Image = LOGO, ScaleType = Enum.ScaleType.Fit, ZIndex = 62 })
	-- al pasar el raton: crece un poco y brilla mas (solo PC)
	if not (UIS.TouchEnabled and not UIS.MouseEnabled) then
		fab.MouseEnter:Connect(function() tween(fabLogo, 0.3, { Size = UDim2.fromOffset(38, 38) }, Enum.EasingStyle.Back) tween(fabStroke, 0.25, { Thickness = 1.8 }) end)
		fab.MouseLeave:Connect(function() tween(fabLogo, 0.3, { Size = UDim2.fromOffset(34, 34) }) tween(fabStroke, 0.25, { Thickness = 1.4 }) end)
	end
	-- el logo flotante con el mismo cristal liquido que el boton SPAM (se pone cuando ese estilo ya existe)
	function rt._restyleFab()
		if true then return end -- el logo flotante se queda como siempre: negro y rojo
		if rt._fabGlass or not getgenv().VIREX_Glass then return end
		pcall(function()
			fabInner.Visible = false
			fabTint.Visible = false
			local api = getgenv().VIREX_Glass(fab, 16, { z = 60, bg = 0.25 })
			rt._fabGlass = api
			fab.InputBegan:Connect(function(i) if isPress(i) then pcall(api.sheen, 0.6) end end)
			task.delay(1, function() pcall(api.sheen, 0.9) end)
		end)
	end
	do
		local down, moved, startIn, startPos = false, 0, nil, nil
		local fabMove = smooth(fab)
		local fabInput
		fab.InputBegan:Connect(function(i)
			if isPress(i) and not down then
				fabInput = i
				down, moved, startIn, startPos = true, 0, i.Position, fab.Position
				tween(fabScale, 0.2, { Scale = 0.9 })
			end
		end)
		UIS.InputChanged:Connect(function(i)
			if down and isMove(i) and sameDrag(fabInput, i) then
				local d = i.Position - startIn
				moved = math.max(moved, d.Magnitude)
				if moved > 8 then fabMove.goal = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) end
			end
		end)
		UIS.InputEnded:Connect(function(i)
			if down and isPress(i) and sameDrag(fabInput, i) then
				down = false
				fabInput = nil
				tween(fabScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
				if moved <= 8 then setOpen(not open, fab.AbsolutePosition + fab.AbsoluteSize / 2) end
			end
		end)
	end
	do -- arrastrar la ventana por la cabecera o por la barra de abajo
		local drag, startPos, startIn
		local winMove = smooth(root)
		local headInput
		local function begin(i)
			if isPress(i) and not drag then
				headInput = i
				drag, startPos, startIn = true, winMove.goal, i.Position
				-- la barra se alarga mientras mueves la ventana
				tween(grip, 0.35, { Size = UDim2.fromOffset(96, 8), BackgroundTransparency = 0.1 }, Enum.EasingStyle.Back)
			end
		end
		head.InputBegan:Connect(begin)
		gripHit.InputBegan:Connect(begin)
		gripHit.MouseEnter:Connect(function() if not drag then tween(grip, 0.25, { Size = UDim2.fromOffset(78, 8), BackgroundTransparency = 0.15 }) end end)
		gripHit.MouseLeave:Connect(function() if not drag then tween(grip, 0.25, { Size = UDim2.fromOffset(64, 8), BackgroundTransparency = 0.3 }) end end)
		UIS.InputChanged:Connect(function(i)
			if drag and isMove(i) and sameDrag(headInput, i) then
				local d = i.Position - startIn
				winMove.goal = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UIS.InputEnded:Connect(function(i)
			if isPress(i) and drag and sameDrag(headInput, i) then
				drag = false
				headInput = nil
				tween(grip, 0.45, { Size = UDim2.fromOffset(64, 8), BackgroundTransparency = 0.3 }, Enum.EasingStyle.Back)
			end
		end)
	end

	-- novedades (una vez por ejecucion)
	local function showNews()
		if getgenv().VIREX_NewsShown then return end
		getgenv().VIREX_NewsShown = true
		local items = {
			{ "New engine", "All functions rebuilt on a new Blade Ball backend." },
			{ "Auto Parry", "Remote or Keypress mode, accuracy, random accuracy, auto ability." },
			{ "Auto Play", "Plays for you: distance, speed, jumps, anti AFK, auto vote." },
			{ "Hit Sounds", "14 hit sounds with volume control." },
			{ "Performance", "No Render, FPS Booster, Low Graphics." },
		}
		local back = new("TextButton", { Parent = win, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 80 })
		local hh = 62 + #items * 42
		local panel = new("CanvasGroup", { Parent = back, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, hh), BackgroundColor3 = BLACK, GroupTransparency = 1, ZIndex = 81 }, { corner(8), stroke(K.line2, 1, 0) })
		local sc = new("UIScale", { Parent = panel, Scale = 0.95 })
		txt(panel, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -60, 0, 18), Text = "WHAT'S NEW", Font = FK, TextSize = 13, ZIndex = 83 })
		txt(panel, { Position = UDim2.fromOffset(16, 30), Size = UDim2.new(1, -60, 0, 13), Text = "VIREX v3", Font = FB, TextSize = 10, TextColor3 = K.mute, ZIndex = 83 })
		local function close()
			if not back.Parent then return end
			tween(sc, 0.25, { Scale = 0.95 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			tween(panel, 0.22, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
			tween(back, 0.25, { BackgroundTransparency = 1 })
			task.delay(0.3, function() back:Destroy() end)
		end
		local x = new("TextButton", { Parent = panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "×", Font = FB, TextSize = 20, TextColor3 = WHITE, AutoButtonColor = false, ZIndex = 84 })
		x.Activated:Connect(close)
		back.Activated:Connect(close)
		for i, it in ipairs(items) do
			local y = 54 + (i - 1) * 42
			new("Frame", { Parent = panel, Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 1), BackgroundColor3 = K.line, BorderSizePixel = 0, ZIndex = 82 })
			new("Frame", { Parent = panel, Position = UDim2.fromOffset(16, y + 14), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 83 }, { corner(1) })
			txt(panel, { Position = UDim2.fromOffset(28, y + 7), Size = UDim2.new(1, -44, 0, 15), Text = it[1], Font = FB, TextSize = 12, ZIndex = 83 })
			txt(panel, { Position = UDim2.fromOffset(28, y + 23), Size = UDim2.new(1, -44, 0, 13), Text = it[2], Font = F, TextSize = 10, TextColor3 = K.mute, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 83 })
		end
		tween(back, 0.3, { BackgroundTransparency = 0.35 })
		tween(panel, 0.3, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
		tween(sc, 0.5, { Scale = 1 })
	end

	task.spawn(function()
		local g = getgenv()
		local t0 = os.clock()
		-- espera a la pantalla de carga: todo sale junto al llegar a 100%
		while g.VIREX_Loader_Active and not g.VIREX_Loaded and os.clock() - t0 < 120 do task.wait(0.1) end
		task.wait(0.15)
		for _, pg in pairs(pages) do pcall(rebalance, pg) end
		setOpen(true, nil, true) -- se enciende en el centro (luego ya abre y cierra desde el logo)
		if rt._loadedConfig then task.delay(1.4, function() rt:notify({ title = "Config Loaded", text = "Your saved settings are back", icon = "check", duration = 2.6 }) end) end
		task.delay(0.6, function() tween(fabScale, 0.8, { Scale = 1 }, Enum.EasingStyle.Back) end)
	end)
	return rt
end

return Lib
end)()

local Players           = cloneref(game:GetService('Players'))  
local ReplicatedStorage = cloneref(game:GetService('ReplicatedStorage'))  
local UserInputService  = cloneref(game:GetService('UserInputService'))  
local RunService        = cloneref(game:GetService('RunService'))  
local TweenService      = cloneref(game:GetService('TweenService'))  
local Stats             = cloneref(game:GetService('Stats'))  
local Debris            = cloneref(game:GetService('Debris'))  
local CoreGui           = cloneref(game:GetService('CoreGui'))  
local HttpService       = cloneref(game:GetService('HttpService'))  
local Workspace         = cloneref(game:GetService('Workspace'))  
  
local UI = Library._new()
pcall(function() getgenv().VIREX_LoadSet(15, "Building interface") end)
local LocalPlayer = Players.LocalPlayer  
local Mouse = LocalPlayer:GetMouse()  
  
if not LocalPlayer.Character then  
    LocalPlayer.CharacterAdded:Wait()  
end  
  
local Alive   = Workspace:FindFirstChild("Alive") or Workspace:WaitForChild("Alive")  
local Runtime = Workspace.Runtime  
  
local function detectMobile()  
    local touch = UserInputService.TouchEnabled  
    local mouse = UserInputService.MouseEnabled  
    local keyboard = UserInputService.KeyboardEnabled  
    if touch and not keyboard then return true end  
    if touch and not mouse then return true end  
    return false  
end  
  
-- HALLOWEEN FONT FIX: matching pixel type for independent Camera and notification UIs.
-- If a published Roblox Font Family asset ID is supplied, use that; .ttf paths
-- cannot be passed to the Roblox TextLabel/FontFace APIs directly.
local HOTHX_POPUP_FONT = Enum.Font.GothamBold
local HOTHX_POPUP_FONT_FACE = nil
do
    local ok, face = pcall(function()
        local env = getgenv and getgenv()
        local id = env and env.HOTHX_MINECRAFT_FONT_ASSET_ID
        if id and tonumber(id) then
            return Font.fromId(tonumber(id))
        end
        return nil
    end)
    if ok then HOTHX_POPUP_FONT_FACE = face end
end
local function HOTHX_applyPopupFont(widget)
    widget.Font = HOTHX_POPUP_FONT
    if HOTHX_POPUP_FONT_FACE then
        pcall(function() widget.FontFace = HOTHX_POPUP_FONT_FACE end)
    end
end

local VIREX_NOTIFY_ALLOW = { VIREX = true, Spam = true }
local function Notify(title, content, duration)  
    -- solo avisos importantes; al tocar opciones (camara, curva, etc.) no sale nada
    if not VIREX_NOTIFY_ALLOW[tostring(title or "")] then return end
    -- VIREX: notificaciones arriba con el estilo nuevo
    if getgenv().VIREX_TopBanner then
        local ok = pcall(function()
            local t = tostring(title or "VIREX")
            getgenv().VIREX_TopBanner({
                title = string.upper(t),
                text = tostring(content or ""),
                glyph = string.upper(t:sub(1, 1)),
                color = Color3.fromRGB(235, 40, 45),
                width = 250,
                duration = math.clamp(tonumber(duration) or 2.5, 1.2, 5),
            })
        end)
        if ok then return end
    end
    if UI and UI.notify then
        pcall(function() UI:notify({ title = tostring(title or "VIREX"), text = tostring(content or ""), duration = tonumber(duration) or 3 }) end)
        return
    end
    duration = duration or 2  
    task.spawn(function()  
        pcall(function()  
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")  
            local parent = CoreGui  
            if not parent then parent = playerGui end  
            if not parent then return end  
  
            local gui = parent:FindFirstChild("VIREX_Notifications")  
            if not gui then  
                gui = Instance.new("ScreenGui")  
                gui.Name = "VIREX_Notifications"  
                gui.ResetOnSpawn = false  
                gui.IgnoreGuiInset = true  
                gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                gui.DisplayOrder = 1100  
                gui.Parent = parent  
            end  
  
            local holder = gui:FindFirstChild("Holder")  
            if not holder then  
                holder = Instance.new("Frame")  
                holder.Name = "Holder"  
                holder.AnchorPoint = Vector2.new(1, 0)  
                holder.Position = UDim2.new(1, -14, 0, 16)  
                holder.Size = UDim2.fromOffset(324, 0)  
                holder.BackgroundTransparency = 1  
                holder.Parent = gui  
  
                local layout = Instance.new("UIListLayout")  
                layout.Padding = UDim.new(0, 8)  
                layout.HorizontalAlignment = Enum.HorizontalAlignment.Right  
                layout.VerticalAlignment = Enum.VerticalAlignment.Top  
                layout.Parent = holder  
            end  
  
            local frame = Instance.new("Frame")  
            frame.Name = "Notification"  
            frame.Size = UDim2.fromOffset(324, 78)  
            frame.BackgroundColor3 = Color3.fromRGB(25, 14, 28)  
            frame.BackgroundTransparency = 0.03  
            frame.BorderSizePixel = 0  
            frame.ClipsDescendants = true  
            frame.Parent = holder  
  
            local corner = Instance.new("UICorner")  
            corner.CornerRadius = UDim.new(0, 15)  
            corner.Parent = frame  
  
            local gradient = Instance.new("UIGradient")  
            gradient.Color = ColorSequence.new({  
                ColorSequenceKeypoint.new(0, Color3.fromRGB(57, 28, 39)),
                ColorSequenceKeypoint.new(0.45, Color3.fromRGB(34, 20, 37)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 13, 26))  
            })  
            gradient.Rotation = 0  
            gradient.Parent = frame  
  
            local stroke = Instance.new("UIStroke")  
            stroke.Color = Color3.fromRGB(255, 140, 46)  
            stroke.Transparency = 0.18  
            stroke.Thickness = 1.4  
            stroke.Parent = frame  
  
            local accent = Instance.new("Frame")
            accent.Name = "HalloweenAccent"
            accent.BorderSizePixel = 0
            accent.BackgroundColor3 = Color3.fromRGB(255, 132, 28)
            accent.Size = UDim2.fromOffset(4, 47)
            accent.Position = UDim2.fromOffset(9, 15)
            accent.Parent = frame
            local accentCorner = Instance.new("UICorner")
            accentCorner.CornerRadius = UDim.new(1, 0)
            accentCorner.Parent = accent

            local titleLabel = Instance.new("TextLabel")  
            titleLabel.BackgroundTransparency = 1  
            titleLabel.Position = UDim2.fromOffset(23, 12)  
            titleLabel.Size = UDim2.new(1, -38, 0, 24)  
            HOTHX_applyPopupFont(titleLabel)  
            titleLabel.Text = tostring(title)  
            titleLabel.TextColor3 = Color3.fromRGB(255, 175, 74)  
            titleLabel.TextSize = 15  
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left  
            titleLabel.Parent = frame  
  
            local contentLabel = Instance.new("TextLabel")  
            contentLabel.BackgroundTransparency = 1  
            contentLabel.Position = UDim2.fromOffset(23, 38)  
            contentLabel.Size = UDim2.new(1, -38, 0, 30)  
            HOTHX_applyPopupFont(contentLabel)  
            contentLabel.Text = tostring(content)  
            contentLabel.TextColor3 = Color3.fromRGB(255, 240, 222)  
            contentLabel.TextSize = 12  
            contentLabel.TextWrapped = true  
            contentLabel.TextXAlignment = Enum.TextXAlignment.Left  
            contentLabel.TextYAlignment = Enum.TextYAlignment.Top  
            contentLabel.Parent = frame  
  
            frame.Position = UDim2.new(1, 25, 0, 0)  
            TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
                Position = UDim2.new(0, 0, 0, 0)  
            }):Play()  
  
            task.wait(duration)  
            local out = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {  
                Position = UDim2.new(1, 25, 0, 0),  
                BackgroundTransparency = 1  
            })  
            out:Play()  
            out.Completed:Wait()  
            frame:Destroy()  
        end)  
    end)  
end  
  
local System = {  
    __properties = {  
        __autoparry_enabled = false,  
        __triggerbot_enabled = false,  
        __manual_spam_enabled = false,  
        __auto_spam_enabled = false,  
        __play_animation = false,  
        __accuracy = 50,  
        __divisor_multiplier = 1.1,  
        __parried = false,  
        __training_parried = false,  
        __spam_threshold = 1.5,  
        __parries = 0,  
        __parry_key = nil,  
        __grab_animation = nil,  
        __tornado_time = tick(),  
        __first_parry_done = false,  
        __connections = {},  
        __reverted_remotes = {},  
        __spam_accumulator = 0,  
        __spam_rate = 340,  
        __infinity_active = false,  
        __deathslash_active = false,  
        __timehole_active = false,  
        __slashesoffury_active = false,  
        __slashesoffury_count = 0,  
        __is_mobile = detectMobile(),  
        __mobile_guis = {},  
        __randomized_accuracy_enabled = false,  
        __speed_display_enabled = false,  
        __auto_jump_enabled = false,  
        __ball_speed = 0,  
        __peak_ball_speed = 0,  
        __headless_enabled = false,  
        __korblox_enabled = false,  
        __thunder_dash_enabled = false  
    },  
    __config = {  
        __detections = {  
            __infinity=false,__deathslash=false,  
            __timehole=false,__slashesoffury=false,__phantom=false  
        }  
    },  
    __triggerbot = {  
        __enabled=false,__is_parrying=false,  
        __parries=0,__max_parries=10000,__parry_delay=0.05  
    }  
}  
  
local function update_divisor()  
    System.__properties.__divisor_multiplier = 0.7 + (System.__properties.__accuracy - 1) * (0.9/99)  
end  
  
local function update_randomized_accuracy()  
    if not System.__properties.__randomized_accuracy_enabled then return end  
    local ping_str = Stats.Network.ServerStatsItem["Data Ping"]:GetValueString()  
    local ping = tonumber(ping_str:match("%d+")) or 0  
    local new_accuracy  
    if ping >= 90 then new_accuracy = 4  
    elseif ping <= 50 then new_accuracy = math.random(70, 100)  
    else new_accuracy = System.__properties.__accuracy end  
    if new_accuracy then System.__properties.__accuracy = new_accuracy; update_divisor() end  
end  
  
task.spawn(function()  
    while task.wait(1) do  
        if System.__properties.__randomized_accuracy_enabled then update_randomized_accuracy() end  
    end  
end)  
  
local replicated_storage = cloneref(game:GetService('ReplicatedStorage'))  
local workspace = cloneref(game:GetService('Workspace'))  
  
local _token  
local _tokenFound = false  
  
-- FAST UI START: perform the heavy remote token scan after the panel is created.
-- This also avoids aborting the entire UI when the token is temporarily unavailable.

  
function _tokenize(_remote_uid)  
    local time = tostring(math.floor(workspace:GetServerTimeNow() * 100))  
    local key = _token(_remote_uid, 'TIME')  
    local characters = table.create(#time)  
    for index = 1, #time do  
        characters[index] = string.char(bit32.bxor(  
            (string.byte(time, index ) + index) % 256,  
            string.byte(key, (index - 1) % #key + 1)  
        ))  
    end  
    return table.concat(characters)  
end  
  
local _reverted = {}  
local _original = {}  
local _captured = nil  
local _capturedRemote = nil  
local _capturedArgs = nil  
local _looseHits = {}
local _capturedLoose = false -- true si lo capturado no tenia la firma comprobada (se cambia por una buena)
local _selfFire = false -- true mientras el propio script dispara el parry (no se captura a si mismo)
-- cuando pulsas para pegar (clic, F o toque), la llamada que manda el juego justo despues es el parry
local _lastParryInput = 0
pcall(function()
    UserInputService.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
            or (t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F)
            or input.KeyCode == Enum.KeyCode.ButtonR1 or input.KeyCode == Enum.KeyCode.ButtonX then
            _lastParryInput = os.clock()
        end
    end)
end)
  
function _is_valid(args)  
    -- 8+ datos como el source original, y ademas la firma del parry:
    -- el dato 3 es el token que el juego calcula con el dato 2 (el mismo que usa el script al disparar).
    -- Asi no se queda con otra llamada y basta con el primer golpe.
    if not args or #args < 8 then return false end  
    if not _token then return false end -- sin token aun: solo vale la llamada justo despues de tu golpe
    if type(args[3]) == "string" and (type(args[2]) == "string" or type(args[2]) == "number") and _token then
        local ok, expected = pcall(_tokenize, args[2])
        if ok and type(expected) == "string" then
            local n = math.min(#expected, #args[3]) - 3
            if n >= 4 then
                return expected:sub(1, n) == args[3]:sub(1, n)
            end
        end
    elseif type(args[3]) ~= "string" then
        return false -- el parry siempre lleva el token (texto) en el dato 3
    end
    return true  
end  
  
function _hook(remote)  
    if not remote then return end  
    if _reverted[remote] then return end  
    if _original[getrawmetatable(remote)] then return end  
  
    _original[getrawmetatable(remote)] = true  
    local _meta = getrawmetatable(remote)  
    setreadonly(_meta, false)  
  
    local _old = _meta.__index  
    _meta.__index = function(self, key)  
        if (key == 'FireServer' and self:IsA('RemoteEvent')) or  
           (key == 'InvokeServer' and self:IsA('RemoteFunction')) then  
            return function(_, ...)  
                local _arguments = table.pack(...)
                local _n = _arguments.n
                -- igual que el source NAZK: la PRIMERA llamada del juego con 8+ datos es el parry
                -- (se captura al primer golpe, sin pedir nada mas). Si luego llega una con la firma
                -- del token comprobada, esa la sustituye por si la primera fue otra cosa.
                local _why = nil
                if _n >= 8 and not _selfFire then
                    if _capturedRemote == nil then
                        _why = "golpe"
                    elseif _capturedLoose and _is_valid(_arguments) then
                        _why = "firma"
                    end
                end
                if _why then
                    -- una firma buena siempre manda: reemplaza lo que se hubiera capturado por error
                    local replace = (_capturedRemote == nil) or (_why == "firma")
                    if replace then
                        local first = _capturedRemote == nil
                        _reverted[self] = _arguments
                        _captured = { remote = self, args = _arguments }
                        _capturedRemote = self
                        _capturedArgs = _arguments
                        _capturedLoose = (_why ~= "firma")
                        -- en la consola (F9) para saber que llamada se capturo
                        pcall(function()
                            local kinds = {}
                            for i = 1, _n do kinds[i] = typeof(_arguments[i]) end
                            print("[VIREX] parry capturado (" .. _why .. "): " .. tostring(self.Name) .. " (" .. _n .. " datos: " .. table.concat(kinds, ", ") .. ")" .. (first and "" or " [actualizado]"))
                        end)
                    end
                end
                return _old(self, key)(_, unpack(_arguments, 1, _n))  
            end  
        end  
        return _old(self, key)  
    end  
    setreadonly(_meta, true)  
end  
  
-- FAST UI START: this initializer runs after the window is drawn.
-- Preserve the existing token/remote logic without holding up the UI for 5 seconds.
-- The splash is assigned when the UI is ready; keeps gameplay logic unchanged.
local HOTHX_showBypassSplash = nil

local function _HOTHX_startRemoteCapture()
    -- 1) engancha YA todos los remotes (y los que aparezcan despues): asi tu primer golpe se captura
    --    aunque el juego aun no haya cargado del todo
    local hooked = 0
    local function hookOne(r)
        if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
            local ok = pcall(_hook, r)
            if ok then hooked += 1 end
        end
    end
    pcall(function()
        for _, _remote in pairs(replicated_storage:GetDescendants()) do hookOne(_remote) end
        replicated_storage.DescendantAdded:Connect(function(r) task.defer(function() pcall(hookOne, r) end) end)
    end)
    print("[VIREX] remotes enganchados: " .. hooked)
    -- 2) busca el token del parry; si el juego aun no lo tiene cargado, lo sigue intentando (antes se rendia a la primera)
    local function findToken()
        pcall(function()
            for _, Function in getgc(true) do
                if type(Function) == "function" then
                    local okS, src = pcall(debug.info, Function, "s")
                    if okS and type(src) == "string" and src:find("PRY", 1, true) then
                        for _, value in debug.getupvalues(Function) do
                            if type(value) == "function" then
                                _token = value
                                _tokenFound = true
                                break
                            end
                        end
                        if _token then break end
                    end
                end
            end
        end)
        return _tokenFound
    end
    task.spawn(function()
        local tries = 0
        while not findToken() do
            tries += 1
            if tries == 20 then
                Notify("VIREX", "Still loading... hit the ball once when the match starts", 4)
            end
            task.wait(1.5)
        end
        print("[VIREX] token del parry encontrado")
    end)
    -- 3) en cuanto pegas el balon a mano (y ya hay token): se activa todo
    task.spawn(function()
        while not (_capturedRemote and _tokenFound) do
            task.wait(0.05)
        end
        if type(HOTHX_showBypassSplash) == "function" then
            pcall(HOTHX_showBypassSplash)
        end
        -- en ese mismo momento arrancan Auto Parry / Auto Spam (si su boton esta activado)
        pcall(function() if getgenv().VIREX_OnBypass then getgenv().VIREX_OnBypass() end end)
    end)
end

  
-- Modo hibrido: hasta que se capture la señal del parry, se simula pulsar F (el propio juego hace el parry).
-- En cuanto se pulsa para pegar (tu o el script), la señal se captura y pasa solo al modo rapido.
local _lastSimParry = 0
local function simulateParryPress()
    if os.clock() - _lastSimParry < 0.12 then return true end
    local typing = false
    pcall(function() typing = UserInputService:GetFocusedTextBox() ~= nil end)
    if typing then return false end -- no escribir "f" en el chat
    _lastSimParry = os.clock()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.delay(0.03, function() pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.F, false, game) end) end)
    end)
    return true
end

local function fireParryRemote(curveCF)  
    if not _capturedRemote or not _capturedArgs then  
        return false -- hasta que pegues el balon a mano una vez (anti cheat bypass)  
    end  
  
    local cam = Workspace.CurrentCamera  
    local is_mobile = System.__properties.__is_mobile  
    local aim_target  
  
    if is_mobile then  
        local vp = cam.ViewportSize  
        aim_target = {math.floor(vp.X / 2), math.floor(vp.Y / 2)}  
    else  
        local ok, mouse = pcall(function() return UserInputService:GetMouseLocation() end)  
        if ok and mouse then  
            aim_target = {math.floor(mouse.X), math.floor(mouse.Y)}  
        else  
            local vp = cam.ViewportSize  
            aim_target = {math.floor(vp.X / 2), math.floor(vp.Y / 2)}  
        end  
    end  
  
    local event_data = {}  
    if Alive then  
        for _, entity in pairs(Alive:GetChildren()) do  
            if entity.PrimaryPart then  
                local ok, sp = pcall(function() return cam:WorldToScreenPoint(entity.PrimaryPart.Position) end)  
                if ok then event_data[entity.Name] = sp end  
            end  
        end  
    end  
  
    local packet = {  
        _capturedArgs[1],  
        _capturedArgs[2],  
        _tokenize(_capturedArgs[2]),  
        0.5,  
        curveCF or cam.CFrame,  
        event_data,  
        aim_target,  
        false  
    }  
  
    _selfFire = true
    pcall(function()  
        if _capturedRemote:IsA('RemoteEvent') then  
            _capturedRemote:FireServer(unpack(packet))  
        elseif _capturedRemote:IsA('RemoteFunction') then  
            _capturedRemote:InvokeServer(unpack(packet))  
        end  
    end)  
    _selfFire = false
    return true  
end  
  
System.animation = {}  
  
-- Defer SwordAPI discovery until the animation is actually requested.
-- Waiting here could prevent the menu from opening when game assets load slowly.
local SwordAPI = nil

local LastPlayedd = 0  
local Sword_CP = false  
local Sword_Spped = 1  
local Grab_Parry = nil  
local AnimFix_Cache = {}  
  
local function GetParryAnimation(swordName)  
    if not SwordAPI or not SwordAPI.Parent then
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        SwordAPI = shared and shared:FindFirstChild("SwordAPI") or nil
    end
    if not SwordAPI then return nil end
    local collection = SwordAPI:FindFirstChild("Collection")
    if not collection or not collection:FindFirstChild("Default") then return nil end

    if not swordName or swordName == "" then  
        return SwordAPI.Collection.Default:FindFirstChild("GrabParry")  
    end  
    if AnimFix_Cache[swordName] then return AnimFix_Cache[swordName] end  
    local ok, swordData = pcall(function()  
        return ReplicatedStorage.Shared.ReplicatedInstances.Swords.GetSword:Invoke(swordName)  
    end)  
    if not ok or not swordData or type(swordData) ~= "table" or not swordData.AnimationType then  
        AnimFix_Cache[swordName] = SwordAPI.Collection.Default:FindFirstChild("GrabParry")  
        return AnimFix_Cache[swordName]  
    end  
    for _, obj in pairs(SwordAPI.Collection:GetChildren()) do  
        if obj.Name == swordData.AnimationType then  
            local anim = obj:FindFirstChild("GrabParry") or obj:FindFirstChild("Grab")  
            if anim then  
                AnimFix_Cache[swordName] = anim  
                return anim  
            end  
        end  
    end  
    AnimFix_Cache[swordName] = SwordAPI.Collection.Default:FindFirstChild("GrabParry")  
    return AnimFix_Cache[swordName]  
end  
  
local function GrabParryPlay(track)  
    if not track then return end  
    pcall(function()  
        track:Play(  
            track:GetAttribute("PlayFadeTime") or 0,  
            track:GetAttribute("PlayWeight") or 1,  
            track:GetAttribute("PlaySpeed") or 1  
        )  
    end)  
end  
  
local function GrabParryStop(track)  
    if not track then return end  
    pcall(function()  
        track:Stop(track:GetAttribute("StopFadeTime") or 0.1)  
    end)  
end  
  
function System.animation.play_grab_parry()  
    if not System.__properties.__play_animation then return end  
    if not ((os.clock() - LastPlayedd) >= (Sword_Spped - 0.8) or Sword_CP) then return end  
    LastPlayedd = os.clock()  
    Sword_CP = false  
    local char = LocalPlayer.Character  
    if not char then return end  
    local humanoid = char:FindFirstChildOfClass("Humanoid")  
    if not humanoid then return end  
    local currentSword  
    if getgenv().skinChanger then  
        currentSword = (getgenv().swordAnimations ~= "" and getgenv().swordAnimations)  
                    or (getgenv().swordModel ~= "" and getgenv().swordModel)  
                    or char:GetAttribute("CurrentlyEquippedSword")  
    else  
        currentSword = char:GetAttribute("CurrentlyEquippedSword")  
    end  
    local animation = GetParryAnimation(currentSword)  
    if not animation then return end  
    for _, track in pairs(humanoid.Animator:GetPlayingAnimationTracks()) do  
        if track.Name == "GrabParry" or track.Name == "Grab" then  
            track.TimePosition = 0  
            GrabParryStop(track)  
        elseif track.Name == "SuccessParry" or track.Name == "Success" then  
            GrabParryStop(track)  
        end  
    end  
    Grab_Parry = humanoid.Animator:LoadAnimation(animation)  
    GrabParryPlay(Grab_Parry)  
end  
  
pcall(function()  
    ReplicatedStorage.Remotes.ParrySuccessAll.OnClientEvent:Connect(function()  
        Sword_CP = true  
        local char = LocalPlayer.Character  
        if not char then return end  
        local humanoid = char:FindFirstChildOfClass("Humanoid")  
        if not humanoid then return end  
        for _, track in pairs(humanoid.Animator:GetPlayingAnimationTracks()) do  
            if track.Name == "GrabParry" or track.Name == "Grab" then  
                GrabParryStop(track)  
            end  
        end  
    end)  
end)  
  
System.ball = {}  
function System.ball.get()  
    local balls=Workspace:FindFirstChild('Balls'); if not balls then return nil end  
    for _,ball in pairs(balls:GetChildren()) do  
        if ball:GetAttribute('realBall') then ball.CanCollide=false; return ball end  
    end; return nil  
end  
function System.ball.get_all()  
    local balls_table={}; local balls=Workspace:FindFirstChild('Balls')  
    if not balls then return balls_table end  
    for _,ball in pairs(balls:GetChildren()) do  
        if ball:GetAttribute('realBall') then ball.CanCollide=false; table.insert(balls_table,ball) end  
    end; return balls_table  
end  
  
System.player = {}  
local Closest_Entity=nil; local last_closest_check=0  
function System.player.get_closest()  
    local now=tick()  
    if now-last_closest_check < 0.1 then return Closest_Entity end  
    last_closest_check=now  
    local max_distance=math.huge; local closest_entity=nil  
    if not Alive then return nil end  
    for _,entity in pairs(Alive:GetChildren()) do  
        if entity ~= LocalPlayer.Character and entity.PrimaryPart then  
            local distance=LocalPlayer:DistanceFromCharacter(entity.PrimaryPart.Position)  
            if distance < max_distance then max_distance=distance; closest_entity=entity end  
        end  
    end  
    Closest_Entity=closest_entity; return closest_entity  
end  
  
local CURVE_NAMES = {"Camera","Random","Accelerated","Backwards","Slow","High","Normal","Speed","Down","Left","Right"}  
local Selected_Parry_Type = "Camera"  
local CurveType = "Camera"  
  
System.curve = {}  
function System.curve.get_cframe()  
    local Camera = Workspace.CurrentCamera  
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")  
    local root_pos = root and root.Position or Camera.CFrame.Position  
  
    local targetPart  
    do  
        local bestDist = math.huge  
        local mouseLoc = not System.__properties.__is_mobile and UserInputService:GetMouseLocation() or nil  
        if Alive then  
            for _, v in pairs(Alive:GetChildren()) do  
                if v ~= LocalPlayer.Character and v.PrimaryPart then  
                    local screenPos, onScreen = Camera:WorldToScreenPoint(v.PrimaryPart.Position)  
                    if onScreen then  
                        local dist  
                        if mouseLoc then  
                            dist = (Vector2.new(screenPos.X, screenPos.Y) - mouseLoc).Magnitude  
                        else  
                            local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)  
                            dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude  
                        end  
                        if dist < bestDist then bestDist = dist; targetPart = v.PrimaryPart end  
                    end  
                end  
            end  
        end  
    end  
    local target_pos = targetPart and targetPart.Position or (root_pos + Camera.CFrame.LookVector * 100)  
  
    local Parry_Type = Selected_Parry_Type  
    local cf  
  
    if Parry_Type == "Camera" then  
        cf = Camera.CFrame  
    elseif Parry_Type == "Random" then  
        local direction = (target_pos - root_pos).Unit  
        local random_offset  
        local attempts = 0  
        repeat  
            random_offset = Vector3.new(math.random(-4000,4000), math.random(-4000,4000), math.random(-4000,4000))  
            local curve_dir = (target_pos + random_offset - root_pos).Unit  
            local dot = direction:Dot(curve_dir)  
            attempts = attempts + 1  
        until dot < 0.95 or attempts > 10  
        cf = CFrame.new(root_pos, target_pos + random_offset)  
    elseif Parry_Type == "Accelerated" then  
        cf = CFrame.new(root_pos, target_pos + Vector3.new(0, 5, 0))  
    elseif Parry_Type == "Backwards" then  
        local direction = (root_pos - target_pos).Unit  
        local backwards_pos = root_pos + direction * 10000 + Vector3.new(0, 1000, 0)  
        cf = CFrame.new(Camera.CFrame.Position, backwards_pos)  
    elseif Parry_Type == "Slow" then  
        cf = CFrame.new(root_pos, target_pos + Vector3.new(0, -9e18, 0))  
    elseif Parry_Type == "High" then  
        cf = CFrame.new(root_pos, target_pos + Vector3.new(0, 9e18, 0))  
    elseif Parry_Type == "Normal" then  
        cf = CFrame.new(root_pos, root_pos + (root and root.CFrame.LookVector or Camera.CFrame.LookVector))  
    elseif Parry_Type == "Speed" then  
        cf = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + Camera.CFrame.UpVector * 5)  
    elseif Parry_Type == "Down" then  
        cf = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + Camera.CFrame.UpVector * -9e9)  
    elseif Parry_Type == "Left" then  
        cf = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position - Camera.CFrame.RightVector * 9e9)  
    elseif Parry_Type == "Right" then  
        cf = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + Camera.CFrame.RightVector * 9e9)  
    else  
        cf = Camera.CFrame  
    end  
  
    return cf  
end  
  
System.parry = {}  
function System.parry.execute()  
    if System.__properties.__parries > 10000 or not LocalPlayer.Character then return end  
    fireParryRemote(System.curve.get_cframe())  
    if System.__properties.__parries > 10000 then return end  
    System.__properties.__parries=System.__properties.__parries+1  
    task.delay(0.5,function() if System.__properties.__parries > 0 then System.__properties.__parries=System.__properties.__parries-1 end end)  
end  
  
function System.parry.keypress()  
    if System.__properties.__parries > 10000 or not LocalPlayer.Character then return end  
    fireParryRemote(System.curve.get_cframe())  
    if System.__properties.__parries > 10000 then return end  
    System.__properties.__parries=System.__properties.__parries+1  
    task.delay(0.5,function() if System.__properties.__parries > 0 then System.__properties.__parries=System.__properties.__parries-1 end end)  
end  
  
function System.parry.execute_action()  
    System.animation.play_grab_parry(); System.parry.execute()  
end  
  
local function linear_predict(a,b,t) return a+(b-a)*t end  
  
System.detection = {  
    __ball_properties = {__aerodynamic_time=tick(),__last_warping=tick(),__lerp_radians=0,__curving=tick()}  
}  
  
function System.detection.is_curved()  
    local props=System.detection.__ball_properties  
    local ball=System.ball.get(); if not ball then return false end  
    local zoomies=ball:FindFirstChild("zoomies"); if not zoomies then return false end  
    local velocity=zoomies.VectorVelocity; local speed=velocity.Magnitude  
    if speed < 1 then return false end  
    local ball_dir=velocity.Unit; local char=LocalPlayer.Character  
    if not char or not char.PrimaryPart then return false end  
    local pos=char.PrimaryPart.Position; local direction=(pos-ball.Position).Unit  
    local dot=direction:Dot(ball_dir)  
    local ping=Stats.Network.ServerStatsItem["Data Ping"]:GetValue()/1000  
    local distance=(pos-ball.Position).Magnitude; local reach_time=distance/speed-ping  
    local dot_threshold=math.clamp(0.55-(ping*0.75),-1,0.45)  
    local speed_threshold=math.min(speed/100,45)  
    local ball_distance_threshold=15-math.min(distance/1000,15)+speed_threshold  
    local clamped_dot=math.clamp(dot,-1,1); local radians=math.asin(clamped_dot)  
    props.__lerp_radians=linear_predict(props.__lerp_radians,radians,0.85)  
    if props.__lerp_radians < 0.016 then props.__last_warping=tick() end  
    if distance < (ball_distance_threshold*0.85) then return false end  
    if (tick()-props.__last_warping) < (reach_time/1.4) then return true end  
    if (tick()-props.__curving) < (reach_time/1.1) then return true end  
    return dot < dot_threshold  
end  
  
ReplicatedStorage.Remotes.DeathBall.OnClientEvent:Connect(function(c,d)  
    System.__properties.__deathslash_active = d or false  
end)  
ReplicatedStorage.Remotes.InfinityBall.OnClientEvent:Connect(function(a,b)  
    System.__properties.__infinity_active = b or false  
end)  
  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/TimeHoleActivate"].OnClientEvent:Connect(function(...)  
    local args={...}; local player=args[1]  
    if player==LocalPlayer or player==LocalPlayer.Name or (player and player.Name==LocalPlayer.Name) then  
        System.__properties.__timehole_active=true  
    end  
end)  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/TimeHoleDeactivate"].OnClientEvent:Connect(function()  
    System.__properties.__timehole_active=false  
end)  
  
local maxParryCount=36; local parryDelay=0.05  
  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/SlashesOfFuryActivate"].OnClientEvent:Connect(function(...)  
    local args={...}; local player=args[1]  
    if player==LocalPlayer or player==LocalPlayer.Name or (player and player.Name==LocalPlayer.Name) then  
        System.__properties.__slashesoffury_active=true; System.__properties.__slashesoffury_count=0  
    end  
end)  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/SlashesOfFuryEnd"].OnClientEvent:Connect(function()  
    System.__properties.__slashesoffury_active=false; System.__properties.__slashesoffury_count=0  
end)  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/SlashesOfFuryParry"].OnClientEvent:Connect(function()  
    System.__properties.__slashesoffury_count=System.__properties.__slashesoffury_count+1  
end)  
ReplicatedStorage.Packages._Index["sleitnick_net@0.1.0"].net["RE/SlashesOfFuryCatch"].OnClientEvent:Connect(function()  
    spawn(function()  
        while System.__properties.__slashesoffury_active and System.__properties.__slashesoffury_count < maxParryCount do  
            if System.__config.__detections.__slashesoffury then System.parry.execute(); task.wait(parryDelay)  
            else break end  
        end  
    end)  
end)  
  
Runtime.ChildAdded:Connect(function(Object)  
    if System.__config.__detections.__phantom then  
        if Object.Name=="maxTransmission" or Object.Name=="transmissionpart" then  
            local Weld=Object:FindFirstChildWhichIsA("WeldConstraint")  
            if Weld then  
                local Character=LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()  
                if Character and Weld.Part1==Character.HumanoidRootPart then  
                    local CurrentBall=System.ball.get(); Weld:Destroy()  
                    if CurrentBall then  
                        local FocusConnection  
                        FocusConnection=RunService.RenderStepped:Connect(function()  
                            local Highlighted=CurrentBall:GetAttribute("highlighted")  
                            if Highlighted==true then  
                                ReplicatedStorage.Remotes.AbilityButtonPress:Fire()  
                                System.__properties.__parried=true  
                                task.delay(1,function() System.__properties.__parried=false end)  
                            elseif Highlighted==false then FocusConnection:Disconnect() end  
                        end)  
                        task.delay(3,function() if FocusConnection and FocusConnection.Connected then FocusConnection:Disconnect() end end)  
                    end  
                end  
            end  
        end  
    end  
end)  
  
ReplicatedStorage.Remotes.ParrySuccessAll.OnClientEvent:Connect(function(_,root)  
    if root.Parent and root.Parent ~= LocalPlayer.Character then  
        if not Alive or root.Parent.Parent ~= Alive then return end  
    end  
    local closest=System.player.get_closest(); local ball=System.ball.get()  
    if not ball or not closest then return end  
    local target_distance=(LocalPlayer.Character.PrimaryPart.Position-closest.PrimaryPart.Position).Magnitude  
    local distance=(LocalPlayer.Character.PrimaryPart.Position-ball.Position).Magnitude  
    local direction=(LocalPlayer.Character.PrimaryPart.Position-ball.Position).Unit  
    local dot=direction:Dot(ball.AssemblyLinearVelocity.Unit)  
    local curve_detected=System.detection.is_curved()  
    if target_distance < 15 and distance < 15 and dot > -0.25 then  
        if curve_detected then System.parry.execute_action() end  
    end  
    if System.__properties.__grab_animation then System.__properties.__grab_animation:Stop() end  
end)  
  
ReplicatedStorage.Remotes.ParrySuccess.OnClientEvent:Connect(function()  
    if not Alive or LocalPlayer.Character.Parent ~= Alive then return end  
    if System.__properties.__grab_animation then System.__properties.__grab_animation:Stop() end  
end)  
  
ReplicatedStorage.Remotes.ParrySuccessAll.OnClientEvent:Connect(function(a,b)  
    local Primary_Part=LocalPlayer.Character.PrimaryPart  
    local Ball=System.ball.get(); if not Ball then return end  
    local Zoomies=Ball:FindFirstChild('zoomies'); if not Zoomies then return end  
    local Speed=Zoomies.VectorVelocity.Magnitude  
    local Distance=(LocalPlayer.Character.PrimaryPart.Position-Ball.Position).Magnitude  
    local Velocity=Zoomies.VectorVelocity; local Ball_Direction=Velocity.Unit  
    local Direction=(LocalPlayer.Character.PrimaryPart.Position-Ball.Position).Unit  
    local Dot=Direction:Dot(Ball_Direction)  
    local Pings=Stats.Network.ServerStatsItem['Data Ping']:GetValue()  
    local Speed_Threshold=math.min(Speed/100,40)  
    local Reach_Time=Distance/Speed-(Pings/1000)  
    local Enough_Speed=Speed > 1  
    local Ball_Distance_Threshold=15-math.min(Distance/1000,15)+Speed_Threshold  
    if Enough_Speed and Reach_Time > Pings/10 then  
        Ball_Distance_Threshold=math.max(Ball_Distance_Threshold-15,15)  
    end  
    if b ~= Primary_Part and Distance > Ball_Distance_Threshold then  
        System.detection.__ball_properties.__curving=tick()  
    end  
end)  
  
System.triggerbot = {}  
local triggerbotCooldown = false  
  
function System.triggerbot.trigger(ball)  
    if triggerbotCooldown then return end  
    if System.__triggerbot.__is_parrying then return end  
    if System.__triggerbot.__parries > System.__triggerbot.__max_parries then return end  
    if LocalPlayer.Character and LocalPlayer.Character.PrimaryPart and  
       LocalPlayer.Character.PrimaryPart:FindFirstChild('SingularityCape') then return end  
  
    triggerbotCooldown = true  
    System.__triggerbot.__is_parrying=true  
    System.__triggerbot.__parries=System.__triggerbot.__parries+1  
  
    System.parry.execute()  
  
    if System.__properties.__play_animation then  
        System.animation.play_grab_parry()  
    end  
  
    task.delay(0.2,function()  
        triggerbotCooldown = false  
        if System.__triggerbot.__parries > 0 then  
            System.__triggerbot.__parries=System.__triggerbot.__parries-1  
        end  
    end)  
  
    task.spawn(function()  
        local start_time=tick()  
        repeat RunService.Heartbeat:Wait()  
        until (tick()-start_time >= 0.15 or not System.__triggerbot.__is_parrying)  
        System.__triggerbot.__is_parrying=false  
    end)  
end  
  
function System.triggerbot.loop()  
    if not System.__triggerbot.__enabled then return end  
    if LocalPlayer.Character and LocalPlayer.Character.PrimaryPart and  
       LocalPlayer.Character.PrimaryPart:FindFirstChild('SingularityCape') then return end  
    local balls=Workspace:FindFirstChild('Balls'); if not balls then return end  
    for _,ball in pairs(balls:GetChildren()) do  
        if ball:IsA('BasePart') and ball:GetAttribute('target')==LocalPlayer.Name then  
            System.triggerbot.trigger(ball)  
            break  
        end  
    end  
end  
  
function System.triggerbot.enable(enabled)  
    System.__triggerbot.__enabled=enabled  
    if enabled then  
        if not System.__properties.__connections.__triggerbot then  
            System.__properties.__connections.__triggerbot=RunService.Heartbeat:Connect(System.triggerbot.loop)  
        end  
    else  
        if System.__properties.__connections.__triggerbot then  
            System.__properties.__connections.__triggerbot:Disconnect()  
            System.__properties.__connections.__triggerbot=nil  
        end  
        System.__triggerbot.__is_parrying=false  
        System.__triggerbot.__parries=0  
        triggerbotCooldown = false  
    end  
end  
  
System.manual_spam = {}  
local manualSpamThread=nil  
local macroSpamActive=false  
local macroFrameFireCount=0; local macroFrameTime=0; local macroRealCPS=0; local macroAnimFix=true  
  
function System.manual_spam.start()  
    System.manual_spam.stop()  
    System.__properties.__manual_spam_enabled=true; macroSpamActive=true  
    local parry_keypress=System.parry.keypress; local parry_execute=System.parry.execute  
    local play_animation=System.animation.play_grab_parry; local threshold=0.015  
    manualSpamThread=coroutine.create(function()  
        local last_spam=0  
        while System.__properties.__manual_spam_enabled do  
            local now=os.clock()  
            if now-last_spam >= threshold then  
                last_spam=now  
                if getgenv().ManualSpamMode=="Keypress" then parry_keypress()  
                else parry_execute(); if getgenv().ManualSpamAnimationFix then play_animation() end end  
            end  
            coroutine.yield()  
        end  
    end)  
    task.spawn(function()  
        while System.__properties.__manual_spam_enabled and manualSpamThread  
              and coroutine.status(manualSpamThread) ~= "dead" do  
            coroutine.resume(manualSpamThread); task.wait()  
        end  
    end)  
end  
  
function System.manual_spam.stop()  
    System.__properties.__manual_spam_enabled=false; macroSpamActive=false; manualSpamThread=nil  
end  
  
RunService.Heartbeat:Connect(function(dt)  
    macroFrameTime=macroFrameTime+dt  
    if macroFrameTime >= 0.1 then  
        if macroSpamActive then macroRealCPS=math.floor(macroFrameFireCount/macroFrameTime) end  
        macroFrameFireCount=0; macroFrameTime=0  
    end  
    if macroSpamActive and _capturedRemote then  
        pcall(function() fireParryRemote(System.curve.get_cframe()); macroFrameFireCount=macroFrameFireCount+1 end)  
        if macroAnimFix then System.animation.play_grab_parry() end  
    end  
end)  
  
System.auto_spam = {}  
  
function System.auto_spam:get_entity_properties()  
    System.player.get_closest()  
    if not Closest_Entity or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart or not Closest_Entity.PrimaryPart then return false end  
    local entity_velocity = Closest_Entity.PrimaryPart.AssemblyLinearVelocity  
    local entity_direction = (LocalPlayer.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Unit  
    local entity_distance = (LocalPlayer.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Magnitude  
    return {Velocity = entity_velocity, Direction = entity_direction, Distance = entity_distance}  
end  
  
function System.auto_spam:get_ball_properties()  
    local ball = System.ball.get()  
    if not ball or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then return false end  
    local ball_velocity = ball.AssemblyLinearVelocity  
    local ball_direction = (LocalPlayer.Character.PrimaryPart.Position - ball.Position).Unit  
    local ball_distance = (LocalPlayer.Character.PrimaryPart.Position - ball.Position).Magnitude  
    local ball_dot = ball_velocity.Magnitude > 0 and ball_direction:Dot(ball_velocity.Unit) or 0  
    return {Velocity = ball_velocity, Direction = ball_direction, Distance = ball_distance, Dot = ball_dot}  
end  
  
function System.auto_spam.spam_service(self)  
    local ball = System.ball.get()  
    local entity = System.player.get_closest()  
    if not ball or not entity or not entity.PrimaryPart or not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then return 0 end  
    local velocity = ball.AssemblyLinearVelocity  
    local speed = velocity.Magnitude  
    local direction = (LocalPlayer.Character.PrimaryPart.Position - ball.Position).Unit  
    local dot = speed > 0 and direction:Dot(velocity.Unit) or 0  
    local target_distance = LocalPlayer:DistanceFromCharacter(entity.PrimaryPart.Position)  
    local maximum_spam_distance = self.Ping + math.min(speed / 6, 255)  
    if self.Entity_Properties.Distance > maximum_spam_distance or self.Ball_Properties.Distance > maximum_spam_distance or target_distance > maximum_spam_distance then return 0 end  
    local maximum_speed = 5 - math.min(speed / 5, 5)  
    local maximum_dot = math.clamp(dot, -1, 0) * maximum_speed  
    return maximum_spam_distance - maximum_dot  
end  
  
function System.auto_spam.start()  
    if System.__properties.__connections.__auto_spam then  
        System.__properties.__connections.__auto_spam:Disconnect()  
    end  
    System.__properties.__auto_spam_enabled = true  
    System.__properties.__connections.__auto_spam = RunService.PreSimulation:Connect(function()  
        if not System.__properties.__auto_spam_enabled then return end  
        local ball = System.ball.get()  
        if not ball or System.__properties.__slashesoffury_active then return end  
        local zoomies = ball:FindFirstChild("zoomies")  
        if not zoomies then return end  
        System.player.get_closest()  
        local ball_properties = System.auto_spam:get_ball_properties()  
        local entity_properties = System.auto_spam:get_entity_properties()  
        if not ball_properties or not entity_properties or not Closest_Entity or not Closest_Entity.PrimaryPart then return end  
        local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()  
        local ping_threshold = math.clamp(ping / 10, 1, 16)  
        local spam_accuracy = System.auto_spam.spam_service({  
            Ball_Properties = ball_properties,  
            Entity_Properties = entity_properties,  
            Ping = ping_threshold  
        })  
        local target_distance = LocalPlayer:DistanceFromCharacter(Closest_Entity.PrimaryPart.Position)  
        local direction = (LocalPlayer.Character.PrimaryPart.Position - ball.Position).Unit  
        local ball_direction = zoomies.VectorVelocity.Magnitude > 0 and zoomies.VectorVelocity.Unit or Vector3.zero  
        local dot = ball_direction.Magnitude > 0 and direction:Dot(ball_direction) or 0  
        local distance = LocalPlayer:DistanceFromCharacter(ball.Position)  
        local ball_target = ball:GetAttribute("target")  
        if not ball_target or target_distance > spam_accuracy or distance > spam_accuracy then return end  
        if LocalPlayer.Character:GetAttribute("Pulsed") then return end  
        if ball_target == LocalPlayer.Name and target_distance > 30 and distance > 30 then return end  
        if distance <= spam_accuracy and System.__properties.__parries > System.__properties.__spam_threshold then  
            if getgenv().AutoSpamMode == "Keypress" then  
                if PF then PF() end  
            else  
                System.parry.execute()  
                if getgenv().AutoSpamAnimationFix and PF then PF() end  
            end  
        end  
    end)  
end  
  
function System.auto_spam.stop()  
    System.__properties.__auto_spam_enabled = false  
    if System.__properties.__connections.__auto_spam then  
        System.__properties.__connections.__auto_spam:Disconnect()  
        System.__properties.__connections.__auto_spam = nil  
    end  
end  

-- ===== Auto Spam LITE (va dentro de Auto Parry): copia de Auto Spam pero mas suave =====
-- Diferencias con el original: como mucho ~7 golpes por segundo (el original va cada frame),
-- solo en choques muy cerca (70% de la distancia), necesita 1 parry mas para empezar,
-- y solo usa el remote (nunca teclas simuladas ni animacion extra).
System.auto_spam_lite = { enabled = false, last = 0, INTERVAL = 0.14, RANGE = 0.7 }
function System.auto_spam_lite.start()
    local L = System.auto_spam_lite
    if System.__properties.__connections.__auto_spam_lite then
        System.__properties.__connections.__auto_spam_lite:Disconnect()
    end
    L.enabled = true
    System.__properties.__connections.__auto_spam_lite = RunService.PreSimulation:Connect(function()
        if not L.enabled then return end
        -- si el Auto Spam completo esta encendido, este no hace nada (no se suman)
        if System.__properties.__auto_spam_enabled then return end
        if os.clock() - L.last < L.INTERVAL then return end
        local ball = System.ball.get()
        if not ball or System.__properties.__slashesoffury_active then return end
        local zoomies = ball:FindFirstChild("zoomies")
        if not zoomies then return end
        System.player.get_closest()
        local ball_properties = System.auto_spam:get_ball_properties()
        local entity_properties = System.auto_spam:get_entity_properties()
        if not ball_properties or not entity_properties or not Closest_Entity or not Closest_Entity.PrimaryPart then return end
        local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        local ping_threshold = math.clamp(ping / 10, 1, 16)
        local spam_accuracy = System.auto_spam.spam_service({
            Ball_Properties = ball_properties,
            Entity_Properties = entity_properties,
            Ping = ping_threshold
        }) * L.RANGE
        local target_distance = LocalPlayer:DistanceFromCharacter(Closest_Entity.PrimaryPart.Position)
        local distance = LocalPlayer:DistanceFromCharacter(ball.Position)
        local ball_target = ball:GetAttribute("target")
        if not ball_target or spam_accuracy <= 0 or target_distance > spam_accuracy or distance > spam_accuracy then return end
        if LocalPlayer.Character:GetAttribute("Pulsed") then return end
        -- solo cuando el balon va entre tu y el rival
        if ball_target ~= LocalPlayer.Name and ball_target ~= Closest_Entity.Name then return end
        if System.__properties.__parries > (System.__properties.__spam_threshold or 0) + 1 then
            L.last = os.clock()
            System.parry.execute()
        end
    end)
end
function System.auto_spam_lite.stop()
    System.auto_spam_lite.enabled = false
    if System.__properties.__connections.__auto_spam_lite then
        System.__properties.__connections.__auto_spam_lite:Disconnect()
        System.__properties.__connections.__auto_spam_lite = nil
    end
end
  
System.autoparry = {}  
local _apWatched = setmetatable({}, { __mode = 'k' }) -- un solo aviso por balon (antes se creaba uno nuevo cada frame)
function System.autoparry.start()  
    if System.__properties.__connections.__autoparry then  
        System.__properties.__connections.__autoparry:Disconnect()  
    end  
    System.__properties.__connections.__autoparry=RunService.PreSimulation:Connect(function()  
        if not System.__properties.__autoparry_enabled or not LocalPlayer.Character or  
           not LocalPlayer.Character.PrimaryPart then return end  
        local balls=System.ball.get_all(); local one_ball=System.ball.get()  
        local training_ball=nil  
        if Workspace:FindFirstChild("TrainingBalls") then  
            for _,Instance in pairs(Workspace.TrainingBalls:GetChildren()) do  
                if Instance:GetAttribute("realBall") then training_ball=Instance; break end  
            end  
        end  
        for _,ball in pairs(balls) do  
            if System.__triggerbot.__enabled then return end  
            if getgenv().BallVelocityAbove800 then return end  
            if not ball then continue end  
            local zoomies=ball:FindFirstChild('zoomies'); if not zoomies then continue end  
            if not _apWatched[ball] then
                _apWatched[ball] = true
                ball:GetAttributeChangedSignal('target'):Connect(function() System.__properties.__parried=false end)
            end
            if System.__properties.__parried then continue end  
            local ball_target=ball:GetAttribute('target')  
            local velocity=zoomies.VectorVelocity  
            local distance=(LocalPlayer.Character.PrimaryPart.Position-ball.Position).Magnitude  
            local ping=Stats.Network.ServerStatsItem['Data Ping']:GetValue()/10  
            local ping_threshold=math.clamp(ping/10,5,17); local speed=velocity.Magnitude  
            local capped_speed_diff=math.min(math.max(speed-9.5,0),650)  
            local speed_divisor=(2.4+capped_speed_diff*0.002)*System.__properties.__divisor_multiplier  
            local parry_accuracy=ping_threshold+math.max(speed/speed_divisor,9.5)  
            if System.__properties.__ping_boost then
                -- con ping alto el balon avanza mientras tu parry viaja al servidor: se adelanta lo justo
                parry_accuracy = parry_accuracy + speed * math.clamp(ping / 100, 0, 0.3) * 0.5
            end
            local curved=System.detection.is_curved()  
            if ball:FindFirstChild('AeroDynamicSlashVFX') then  
                ball.AeroDynamicSlashVFX:Destroy(); System.__properties.__tornado_time=tick()  
            end  
            if Runtime:FindFirstChild('Tornado') then  
                if (tick()-System.__properties.__tornado_time) <  
                   (Runtime.Tornado:GetAttribute('TornadoTime') or 1)+0.314159 then continue end  
            end  
            if one_ball and one_ball:GetAttribute('target')==LocalPlayer.Name and curved then continue end  
            if ball:FindFirstChild('ComboCounter') then continue end  
            if LocalPlayer.Character.PrimaryPart:FindFirstChild('SingularityCape') then continue end  
            if System.__config.__detections.__infinity and System.__properties.__infinity_active then continue end  
            if System.__config.__detections.__deathslash and System.__properties.__deathslash_active then continue end  
            if System.__config.__detections.__timehole and System.__properties.__timehole_active then continue end  
            if System.__config.__detections.__slashesoffury and System.__properties.__slashesoffury_active then continue end  
            if ball_target==LocalPlayer.Name and distance <= parry_accuracy then  
                if getgenv().AutoAbility then  
                    local AbilityCD=LocalPlayer.PlayerGui.Hotbar.Ability.UIGradient  
                    if AbilityCD and AbilityCD.Offset.Y==0.5 then  
                        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Abilities") then  
                            local abilities=LocalPlayer.Character.Abilities  
                            if (abilities:FindFirstChild("Raging Deflection") and abilities["Raging Deflection"].Enabled) or  
                               (abilities:FindFirstChild("Rapture") and abilities["Rapture"].Enabled) or  
                               (abilities:FindFirstChild("Calming Deflection") and abilities["Calming Deflection"].Enabled) or  
                               (abilities:FindFirstChild("Aerodynamic Slash") and abilities["Aerodynamic Slash"].Enabled) or  
                               (abilities:FindFirstChild("Fracture") and abilities["Fracture"].Enabled) or  
                               (abilities:FindFirstChild("Death Slash") and abilities["Death Slash"].Enabled) then  
                                System.__properties.__parried=true  
                                ReplicatedStorage.Remotes.AbilityButtonPress:Fire()  
                                task.wait(2.432)  
                                ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DeathSlashShootActivation"):FireServer(true)  
                                continue  
                            end  
                        end  
                    end  
                end  
            end  
            if ball_target==LocalPlayer.Name and distance <= parry_accuracy then  
                if getgenv().AutoParryMode=="Keypress" then System.parry.keypress()  
                else System.parry.execute_action() end  
                System.__properties.__parried=true  
            end  
            local last_parrys=tick()  
            repeat RunService.Stepped:Wait()  
            until (tick()-last_parrys) >= 1 or not System.__properties.__parried  
            System.__properties.__parried=false  
        end  
        if training_ball then  
            local zoomies=training_ball:FindFirstChild('zoomies')  
            if zoomies then  
                if not _apWatched[training_ball] then
                    _apWatched[training_ball] = true
                    training_ball:GetAttributeChangedSignal('target'):Connect(function() System.__properties.__training_parried=false end)
                end
                if not System.__properties.__training_parried then  
                    local ball_target=training_ball:GetAttribute('target')  
                    local velocity=zoomies.VectorVelocity  
                    local distance=LocalPlayer:DistanceFromCharacter(training_ball.Position)  
                    local speed=velocity.Magnitude  
                    local ping=Stats.Network.ServerStatsItem['Data Ping']:GetValue()/10  
                    local ping_threshold=math.clamp(ping/10,5,17)  
                    local capped_speed_diff=math.min(math.max(speed-9.5,0),650)  
                    local speed_divisor=(2.4+capped_speed_diff*0.002)*System.__properties.__divisor_multiplier  
                    local parry_accuracy=ping_threshold+math.max(speed/speed_divisor,9.5)  
                    if ball_target==LocalPlayer.Name and distance <= parry_accuracy then  
                        if getgenv().AutoParryMode=="Keypress" then System.parry.keypress()  
                        else System.parry.execute_action() end  
                        System.__properties.__training_parried=true  
                        local last_parrys=tick()  
                        repeat RunService.Stepped:Wait()  
                        until (tick()-last_parrys) >= 1 or not System.__properties.__training_parried  
                        System.__properties.__training_parried=false  
                    end  
                end  
            end  
        end  
    end)  
end  
  
function System.autoparry.stop()  
    if System.__properties.__connections.__autoparry then  
        System.__properties.__connections.__autoparry:Disconnect()  
        System.__properties.__connections.__autoparry=nil  
    end  
end  
  
local ManualSpamGui = nil  
local ManualSpamConnections = {}  
local TriggerGui = nil  
local TriggerConnections = {}  
local CurveGui = nil  
local CurveConnections = {}  
local KeyboardGui = nil  
local KeyboardConnections = {}  
local KeyboardKeyConnections = {}  
local KeyboardCapture = nil  
local KeyboardCaptureConsumed = false  
  
local KeyboardSettings = {  
    AutoParry = Enum.KeyCode.T,  
    AutoSpam = Enum.KeyCode.V,  
    ManualSpam = Enum.KeyCode.F,  
    ManualSpamMode = "Hold to Spam"  
}  
  
local function keyName(keyCode)  
    return keyCode == Enum.KeyCode.Unknown and "None" or keyCode.Name  
end  
  
local function isKeyboardInput(input)  
    return input.UserInputType == Enum.UserInputType.Keyboard  
        and input.KeyCode ~= Enum.KeyCode.Unknown  
end  
  
local function stopManualKeyboardSpam()  
    if KeyboardSettings.ManualSpamMode == "Hold to Spam" and System.__properties.__manual_spam_enabled then  
        _G.manualSpamEnabled = false  
        if _G.VIREX then _G.VIREX.manualSpamEnabled = false end  
        System.manual_spam.stop()  
        macroSpamActive = false  
    end  
end  
  
local function toggleManualKeyboardSpam()  
    local state = not System.__properties.__manual_spam_enabled  
    _G.manualSpamEnabled = state  
    _G.VIREX = _G.VIREX or {}  
    _G.VIREX.manualSpamEnabled = state  
    System.__properties.__manual_spam_enabled = state  
    macroSpamActive = state  
    if state then  
        System.manual_spam.start()  
    else  
        System.manual_spam.stop()  
    end  
end  
  
local function SetKeyboardKey(name, keyCode)  
    KeyboardSettings[name] = keyCode  
end  
  
local DisconnectConnections  
  
local function CreateKeyboardUI()  
    if KeyboardGui and KeyboardGui.Parent then  
        KeyboardGui.Enabled = true  
        return  
    end  
  
    local gui = Instance.new("ScreenGui")  
    gui.Name = "VIREX_KeyboardUI"  
    gui.ResetOnSpawn = false  
    gui.IgnoreGuiInset = true  
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  
    gui.Parent = CoreGui  
    KeyboardGui = gui  
  
    local Main = Instance.new("Frame")  
    Main.Name = "Keyboard"  
    Main.Size = UDim2.fromOffset(260, 126)  
    Main.Position = UDim2.new(0.5, -130, 0.5, -63)  
    Main.BackgroundColor3 = Color3.fromRGB(16, 16, 16)  
    Main.BorderSizePixel = 0  
    Main.Active = true  
    Main.ZIndex = 2500  
    Main.Parent = gui  
  
    local Corner = Instance.new("UICorner")  
    Corner.CornerRadius = UDim.new(0, 13)  
    Corner.Parent = Main  
  
    local Stroke = Instance.new("UIStroke")  
    Stroke.Thickness = 1.5  
    Stroke.Color = Color3.fromRGB(70, 70, 70)  
    Stroke.Transparency = 0.25  
    Stroke.Parent = Main  
  
    local Title = Instance.new("TextLabel")  
    Title.Size = UDim2.new(1, -20, 0, 32)  
    Title.Position = UDim2.fromOffset(10, 5)  
    Title.BackgroundTransparency = 1  
    Title.Text = "Keyboard"  
    Title.TextColor3 = Color3.fromRGB(245, 245, 245)  
    Title.TextSize = 15  
    Title.Font = Enum.Font.GothamBold  
    Title.TextXAlignment = Enum.TextXAlignment.Center  
    Title.ZIndex = 2502  
    Title.Parent = Main  
  
    local Divider = Instance.new("Frame")  
    Divider.Size = UDim2.new(1, 0, 0, 1)  
    Divider.Position = UDim2.fromOffset(0, 40)  
    Divider.BackgroundColor3 = Color3.fromRGB(34, 34, 34)  
    Divider.BorderSizePixel = 0  
    Divider.ZIndex = 2501  
    Divider.Parent = Main  
  
    local Rows = Instance.new("Frame")  
    Rows.Size = UDim2.new(1, -20, 0, 76)  
    Rows.Position = UDim2.fromOffset(10, 47)  
    Rows.BackgroundTransparency = 1  
    Rows.ZIndex = 2502  
    Rows.Parent = Main  
  
    local layout = Instance.new("UIListLayout")  
    layout.Padding = UDim.new(0, 4)  
    layout.FillDirection = Enum.FillDirection.Vertical  
    layout.Parent = Rows  
  
    local modeOpen = false  
    local modePanel = Instance.new("Frame")  
    modePanel.Size = UDim2.new(1, -20, 0, 46)  
    modePanel.Position = UDim2.fromOffset(10, 123)  
    modePanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)  
    modePanel.BorderSizePixel = 0  
    modePanel.Visible = false  
    modePanel.ZIndex = 2510  
    modePanel.Parent = Main  
  
    local modeCorner = Instance.new("UICorner")  
    modeCorner.CornerRadius = UDim.new(0, 9)  
    modeCorner.Parent = modePanel  
  
    local modeStroke = Instance.new("UIStroke")  
    modeStroke.Thickness = 1  
    modeStroke.Color = Color3.fromRGB(55, 55, 55)  
    modeStroke.Parent = modePanel  
  
    local function makeButton(parent, textValue, widthScale, xScale)  
        local button = Instance.new("TextButton")  
        button.Size = UDim2.new(widthScale, -4, 1, 0)  
        button.Position = UDim2.new(xScale, 2, 0, 0)  
        button.BackgroundColor3 = Color3.fromRGB(24, 24, 24)  
        button.BorderSizePixel = 0  
        button.Text = textValue  
        button.TextColor3 = Color3.fromRGB(245, 245, 245)  
        button.TextSize = 12  
        button.Font = Enum.Font.GothamSemibold  
        button.AutoButtonColor = false  
        button.ZIndex = 2512  
        button.Parent = parent  
        local c = Instance.new("UICorner")  
        c.CornerRadius = UDim.new(0, 7)  
        c.Parent = button  
        local st = Instance.new("UIStroke")  
        st.Thickness = 1  
        st.Color = Color3.fromRGB(55, 55, 55)  
        st.Parent = button  
        return button  
    end  
  
    local function makeRow(label, settingName)  
        local row = Instance.new("Frame")  
        row.Size = UDim2.new(1, 0, 0, 22)  
        row.BackgroundTransparency = 1  
        row.ZIndex = 2503  
        row.Parent = Rows  
  
        local text = Instance.new("TextLabel")  
        text.Size = UDim2.new(0.58, 0, 1, 0)  
        text.BackgroundTransparency = 1  
        text.Text = label  
        text.TextColor3 = Color3.fromRGB(230, 230, 230)  
        text.TextSize = 13  
        text.Font = Enum.Font.GothamMedium  
        text.TextXAlignment = Enum.TextXAlignment.Left  
        text.ZIndex = 2504  
        text.Parent = row  
  
        local button = makeButton(row, keyName(KeyboardSettings[settingName]), 0.42, 0.58)  
        return button  
    end  
  
    local autoParryButton = makeRow("Auto Parry", "AutoParry")  
    local autoSpamButton = makeRow("Auto Spam", "AutoSpam")  
  
    local manualRow = Instance.new("Frame")  
    manualRow.Size = UDim2.new(1, 0, 0, 22)  
    manualRow.BackgroundTransparency = 1  
    manualRow.ZIndex = 2503  
    manualRow.Parent = Rows  
  
    local manualText = Instance.new("TextLabel")  
    manualText.Size = UDim2.new(0.34, 0, 1, 0)  
    manualText.BackgroundTransparency = 1  
    manualText.Text = "Manual Spam"  
    manualText.TextColor3 = Color3.fromRGB(230, 230, 230)  
    manualText.TextSize = 13  
    manualText.Font = Enum.Font.GothamMedium  
    manualText.TextXAlignment = Enum.TextXAlignment.Left  
    manualText.ZIndex = 2504  
    manualText.Parent = manualRow  
  
    local manualKeyButton = makeButton(manualRow, keyName(KeyboardSettings.ManualSpam), 0.28, 0.34)  
    local manualModeButton = makeButton(manualRow, KeyboardSettings.ManualSpamMode, 0.38, 0.62)  
  
    local function animateMode(open)  
        modeOpen = open  
        if open then  
            modePanel.Visible = true  
            modePanel.Size = UDim2.new(1, -20, 0, 0)  
            modePanel.Position = UDim2.fromOffset(10, 123)  
            TweenService:Create(Main, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
                Size = UDim2.fromOffset(260, 180)  
            }):Play()  
            TweenService:Create(modePanel, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
                Size = UDim2.new(1, -20, 0, 46)  
            }):Play()  
        else  
            local tween = TweenService:Create(modePanel, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {  
                Size = UDim2.new(1, -20, 0, 0)  
            })  
            tween:Play()  
            TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {  
                Size = UDim2.fromOffset(260, 126)  
            }):Play()  
            tween.Completed:Connect(function()  
                if not modeOpen then modePanel.Visible = false end  
            end)  
        end  
    end  
  
    local holdOption = makeButton(modePanel, "Hold to Spam", 0.5, 0)  
    local onceOption = makeButton(modePanel, "Press Once to Spam", 0.5, 0.5)  
  
    local function selectMode(mode)  
        KeyboardSettings.ManualSpamMode = mode  
        manualModeButton.Text = mode  
        animateMode(false)  
    end  
  
    manualModeButton.MouseButton1Click:Connect(function()  
        animateMode(not modeOpen)  
    end)  
    holdOption.MouseButton1Click:Connect(function()  
        selectMode("Hold to Spam")  
    end)  
    onceOption.MouseButton1Click:Connect(function()  
        selectMode("Press Once to Spam")  
    end)  
  
    local function beginKeyCapture(settingName, button)  
        if KeyboardCapture then return end  
        KeyboardCapture = settingName  
        button.Text = "Press a key..."  
        task.spawn(function()  
            local timeout = os.clock() + 8  
            while KeyboardCapture == settingName and os.clock() < timeout do  
                task.wait()  
            end  
            if KeyboardCapture == settingName then  
                KeyboardCapture = nil  
                button.Text = keyName(KeyboardSettings[settingName])  
            end  
        end)  
    end  
  
    autoParryButton.MouseButton1Click:Connect(function()  
        beginKeyCapture("AutoParry", autoParryButton)  
    end)  
    autoSpamButton.MouseButton1Click:Connect(function()  
        beginKeyCapture("AutoSpam", autoSpamButton)  
    end)  
    manualKeyButton.MouseButton1Click:Connect(function()  
        beginKeyCapture("ManualSpam", manualKeyButton)  
    end)  
  
    KeyboardConnections.capture = UserInputService.InputBegan:Connect(function(input, processed)  
        if not isKeyboardInput(input) then return end  
        if KeyboardCapture then  
            local name = KeyboardCapture  
            KeyboardCapture = nil  
            KeyboardCaptureConsumed = true  
            SetKeyboardKey(name, input.KeyCode)  
            local button = name == "AutoParry" and autoParryButton or name == "AutoSpam" and autoSpamButton or manualKeyButton  
            button.Text = keyName(input.KeyCode)  
            return  
        end  
    end)  
  
    KeyboardConnections.inputBegan = UserInputService.InputBegan:Connect(function(input, processed)  
        if KeyboardCaptureConsumed then  
            KeyboardCaptureConsumed = false  
            return  
        end  
        if processed or not isKeyboardInput(input) or KeyboardCapture then return end  
        if input.KeyCode == KeyboardSettings.AutoParry then  
            local state = not System.__properties.__autoparry_enabled  
            System.__properties.__autoparry_enabled = state  
            System.__properties.__play_animation = state  
            if state then System.autoparry.start() else System.autoparry.stop() end  
        elseif input.KeyCode == KeyboardSettings.AutoSpam then  
            local state = not System.__properties.__auto_spam_enabled  
            System.__properties.__auto_spam_enabled = state  
            if state then System.auto_spam.start() else System.auto_spam.stop() end  
        elseif input.KeyCode == KeyboardSettings.ManualSpam then  
            if KeyboardSettings.ManualSpamMode == "Press Once to Spam" then  
                toggleManualKeyboardSpam()  
            else  
                if not System.__properties.__manual_spam_enabled then  
                    _G.manualSpamEnabled = true  
                    _G.VIREX = _G.VIREX or {}  
                    _G.VIREX.manualSpamEnabled = true  
                    System.manual_spam.start()  
                end  
            end  
        end  
    end)  
  
    KeyboardConnections.inputEnded = UserInputService.InputEnded:Connect(function(input)  
        if not isKeyboardInput(input) or KeyboardCapture then return end  
        if input.KeyCode == KeyboardSettings.ManualSpam and KeyboardSettings.ManualSpamMode == "Hold to Spam" then  
            stopManualKeyboardSpam()  
        end  
    end)  
  
    local dragging = false  
    local dragStart  
    local startPos  
    KeyboardConnections.dragBegan = Main.InputBegan:Connect(function(input)  
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end  
        dragging = true  
        dragStart = input.Position  
        startPos = Main.Position  
    end)  
    KeyboardConnections.dragChanged = UserInputService.InputChanged:Connect(function(input)  
        if not dragging then return end  
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end  
        local delta = input.Position - dragStart  
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)  
    end)  
    KeyboardConnections.dragEnded = UserInputService.InputEnded:Connect(function(input)  
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then  
            dragging = false  
        end  
    end)  
end  
  
local function DestroyKeyboardUI()  
    KeyboardCapture = nil  
    DisconnectConnections(KeyboardConnections)  
    if KeyboardGui then  
        KeyboardGui:Destroy()  
        KeyboardGui = nil  
    end  
end  
  
DisconnectConnections = function(tbl)  
    for _, connection in pairs(tbl) do  
        pcall(function() connection:Disconnect() end)  
    end  
    table.clear(tbl)  
end  
  
local function CreateSmallActionUI(kind)  
    local isTrigger = (kind == "Trigger")  
    local existing = isTrigger and TriggerGui or ManualSpamGui  
    local connections = isTrigger and TriggerConnections or ManualSpamConnections  
  
    if existing and existing.Parent then  
        existing.Enabled = true  
        return  
    end  
  
    local gui = Instance.new("ScreenGui")  
    gui.Name = isTrigger and "VIREX_TriggerUI" or "VIREX_SpamUI"  
    gui.ResetOnSpawn = false  
    gui.IgnoreGuiInset = true  
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  
    gui.Parent = CoreGui  
  
    if isTrigger then  
        TriggerGui = gui  
    else  
        ManualSpamGui = gui  
        _G.manualSpamEnabled = false  
        _G.VIREX = _G.VIREX or {}  
        _G.VIREX.manualSpamEnabled = false  
    end  
  
    local Main = Instance.new("Frame")  
    Main.Size = UDim2.fromOffset(180, 60)  
    Main.Position = UDim2.new(0.5, -90, 0.5, -30)  
    Main.BackgroundColor3 = Color3.fromRGB(128, 128, 128)  
    Main.BorderSizePixel = 0  
    Main.Active = true  
    Main.ZIndex = 999  
    Main.Parent = gui  
  
    local UICorner = Instance.new("UICorner")  
    UICorner.CornerRadius = UDim.new(0, 13)  
    UICorner.Parent = Main  
  
    local Stroke = Instance.new("UIStroke")  
    Stroke.Thickness = 2  
    Stroke.Color = Color3.fromRGB(255, 255, 255)  
    Stroke.Transparency = 0.35  
    Stroke.Parent = Main  
  
    local Gradient = Instance.new("UIGradient")  
    Gradient.Rotation = 90  
    Gradient.Color = ColorSequence.new({  
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),  
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(170, 170, 170)),  
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(60, 60, 60)),  
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 5))  
    })  
    Gradient.Parent = Main  
  
    local Button = Instance.new("TextButton")  
    Button.Size = UDim2.new(1, 0, 1, 0)  
    Button.BackgroundTransparency = 1  
    Button.Text = isTrigger and "TRIGGER" or "SPAM"  
    Button.TextColor3 = Color3.fromRGB(255, 255, 255)  
    Button.TextSize = 18  
    Button.Font = Enum.Font.GothamBold  
    Button.AutoButtonColor = false  
    Button.ZIndex = 1000  
    Button.Parent = Main  
  
    local dragging = false  
    local dragStart  
    local startPos  
    local dragThreshold = 6  
    local dragInput = nil  
    local dragCandidate = false  
  
    local function isOnBorder(inputPosition)  
        local absolutePosition = Main.AbsolutePosition  
        local absoluteSize = Main.AbsoluteSize  
        local x = inputPosition.X - absolutePosition.X  
        local y = inputPosition.Y - absolutePosition.Y  
        local border = 10  
        return x >= 0 and x <= absoluteSize.X  
            and y >= 0 and y <= absoluteSize.Y  
            and (x <= border or x >= absoluteSize.X - border  
                or y <= border or y >= absoluteSize.Y - border)  
    end  
  
    if isTrigger then  
        connections.button = Button.MouseButton1Click:Connect(function()  
            local state = not System.__properties.__triggerbot_enabled  
            System.__properties.__triggerbot_enabled = state  
            System.triggerbot.enable(state)  
            Button.Text = state and "OFF" or "TRIGGER"  
            Notify("Trigger", state and "ON" or "OFF", 2)  
        end)  
    else  
        connections.button = Button.MouseButton1Click:Connect(function()  
            local state = not _G.manualSpamEnabled  
            _G.manualSpamEnabled = state  
            _G.VIREX.manualSpamEnabled = state  
            System.__properties.__manual_spam_enabled = state  
            macroSpamActive = state  
            if state then  
                System.manual_spam.start()  
                Button.Text = "OFF"  
                Notify("Manual Spam", "ON", 2)  
            else  
                System.manual_spam.stop()  
                Button.Text = "SPAM"  
                Notify("Manual Spam", "OFF", 2)  
            end  
        end)  
    end  
  
    connections.inputBegan = UserInputService.InputBegan:Connect(function(input)  
        if input.UserInputType ~= Enum.UserInputType.MouseButton1  
            and input.UserInputType ~= Enum.UserInputType.Touch then return end  
        if not isOnBorder(input.Position) then  
            dragCandidate = false  
            return  
        end  
        dragCandidate = true  
        dragging = false  
        dragInput = input  
        dragStart = input.Position  
        startPos = Main.Position  
    end)  
  
    connections.inputChanged = UserInputService.InputChanged:Connect(function(input)  
        if not dragCandidate then return end  
        if input.UserInputType ~= Enum.UserInputType.MouseMovement  
            and input.UserInputType ~= Enum.UserInputType.Touch then return end  
        local delta = input.Position - dragStart  
        if not dragging then  
            if math.abs(delta.X) < dragThreshold and math.abs(delta.Y) < dragThreshold then return end  
            dragging = true  
        end  
        Main.Position = UDim2.new(  
            startPos.X.Scale, startPos.X.Offset + delta.X,  
            startPos.Y.Scale, startPos.Y.Offset + delta.Y  
        )  
    end)  
  
    connections.inputEnded = UserInputService.InputEnded:Connect(function(input)  
        if input == dragInput  
            or input.UserInputType == Enum.UserInputType.MouseButton1  
            or input.UserInputType == Enum.UserInputType.Touch then  
            dragging = false  
            dragCandidate = false  
            dragInput = nil  
        end  
    end)  
end  
  
  
local function CreateCurveUI()  
    if CurveGui and CurveGui.Parent then  
        CurveGui.Enabled = true  
        return  
    end  
  
    local gui = Instance.new("ScreenGui")  
    gui.Name = "VIREX_CurveUI"  
    gui.ResetOnSpawn = false  
    gui.IgnoreGuiInset = true  
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  
    gui.Parent = CoreGui  
    CurveGui = gui  
  
    local Main = Instance.new("Frame")  
    Main.Name = "CurveUI"  
    Main.AnchorPoint = Vector2.new(0.5, 0)  
    Main.Size = UDim2.fromOffset(118, 42)  
    Main.Position = UDim2.new(0.5, 0, 0, 16)  
    Main.BackgroundColor3 = Color3.fromRGB(21, 21, 21)  
    Main.BackgroundTransparency = 0.04  
    Main.BorderSizePixel = 0  
    Main.ClipsDescendants = true  
    Main.Active = true  
    Main.ZIndex = 2000  
    Main.Parent = gui  
  
    local Corner = Instance.new("UICorner")  
    Corner.CornerRadius = UDim.new(0, 14)  
    Corner.Parent = Main  
  
    local Gradient = Instance.new("UIGradient")  
    Gradient.Rotation = 0  
    Gradient.Color = ColorSequence.new({  
        ColorSequenceKeypoint.new(0, Color3.fromRGB(49, 49, 49)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(31, 31, 31)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 15))  
    })  
    Gradient.Parent = Main  
  
    local Stroke = Instance.new("UIStroke")  
    Stroke.Thickness = 1.5  
    Stroke.Color = Color3.fromRGB(255, 255, 255)  
    Stroke.Transparency = 0.13  
    Stroke.Parent = Main  
  
    local Header = Instance.new("TextButton")  
    Header.Name = "Header"  
    Header.Size = UDim2.new(1, -10, 0, 42)  
    Header.Position = UDim2.fromOffset(5, 0)  
    Header.BackgroundTransparency = 1  
    Header.Text = tostring(Selected_Parry_Type or "Camera")  
    Header.TextColor3 = Color3.fromRGB(238, 238, 238)  
    Header.TextSize = 14  
    HOTHX_applyPopupFont(Header)  
    Header.AutoButtonColor = false
    Header.TextTruncate = Enum.TextTruncate.AtEnd  
    Header.ZIndex = 2002  
    Header.Parent = Main  
  
    local headerAccent = Instance.new("Frame")
    headerAccent.Name = "HalloweenHeaderLine"
    headerAccent.Size = UDim2.new(1, -24, 0, 2)
    headerAccent.Position = UDim2.fromOffset(12, 44)
    headerAccent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    headerAccent.BorderSizePixel = 0
    headerAccent.ZIndex = 2002
    headerAccent.Parent = Main

    local OptionsHolder = Instance.new("Frame")  
    OptionsHolder.Name = "Options"  
    OptionsHolder.Position = UDim2.fromOffset(8, 50)  
    OptionsHolder.Size = UDim2.new(1, -16, 1, -58)  
    OptionsHolder.BackgroundTransparency = 1  
    OptionsHolder.Visible = false  
    OptionsHolder.ZIndex = 2002  
    OptionsHolder.Parent = Main  
  
    local Grid = Instance.new("UIGridLayout")  
    Grid.CellSize = UDim2.fromOffset(136, 29)  
    Grid.CellPadding = UDim2.fromOffset(8, 5)  
    Grid.HorizontalAlignment = Enum.HorizontalAlignment.Center  
    Grid.VerticalAlignment = Enum.VerticalAlignment.Top  
    Grid.Parent = OptionsHolder  
  
    local expanded = false  
    local current = Selected_Parry_Type or "Camera"  
    local CLOSED_WIDTH = 118  
    local OPEN_WIDTH = 296  
    local OPEN_HEIGHT = 268  
  
    local function setHeader()  
        Header.Text = tostring(current)  
    end  
  
    local function closeUI()  
        expanded = false  
        OptionsHolder.Visible = false  
        local heightTween = TweenService:Create(Main, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {  
            Size = UDim2.fromOffset(OPEN_WIDTH, 42)  
        })  
        heightTween:Play()  
        heightTween.Completed:Wait()  
        TweenService:Create(Main, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
            Size = UDim2.fromOffset(CLOSED_WIDTH, 42)  
        }):Play()  
    end  
  
    local function setSelected(value)  
        current = value  
        Selected_Parry_Type = value  
        CurveType = value  
        setHeader()  
        closeUI()  
    end  
  
    for _, name in ipairs(CURVE_NAMES) do  
        local Option = Instance.new("TextButton")  
        Option.Name = name  
        Option.Size = UDim2.fromOffset(136, 29)  
        Option.BackgroundColor3 = Color3.fromRGB(38, 38, 38)  
        Option.BackgroundTransparency = 0.05  
        Option.BorderSizePixel = 0  
        Option.Text = name  
        Option.TextColor3 = Color3.fromRGB(235, 235, 235)  
        Option.TextSize = 12  
        HOTHX_applyPopupFont(Option)  
        Option.AutoButtonColor = false  
        Option.ZIndex = 2003  
        Option.Parent = OptionsHolder  
  
        local OptionCorner = Instance.new("UICorner")  
        OptionCorner.CornerRadius = UDim.new(0, 9)  
        OptionCorner.Parent = Option  
  
        local OptionGradient = Instance.new("UIGradient")  
        OptionGradient.Color = ColorSequence.new({  
            ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 55, 55)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(37, 37, 37)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 25))  
        })  
        OptionGradient.Parent = Option

        local optionStroke = Instance.new("UIStroke")
        optionStroke.Name = "HalloweenOutline"
        optionStroke.Color = Color3.fromRGB(255, 255, 255)
        optionStroke.Thickness = 1
        optionStroke.Transparency = 0.67
        optionStroke.Parent = Option  
  
        CurveConnections["option_" .. name] = Option.MouseButton1Click:Connect(function()  
            setSelected(name)  
        end)  
    end  
  
    CurveConnections.selected = Header.MouseButton1Click:Connect(function()  
        if expanded then  
            closeUI()  
            return  
        end  
  
        expanded = true  
        Header.Text = tostring(current)  
        TweenService:Create(Main, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
            Size = UDim2.fromOffset(OPEN_WIDTH, 42)  
        }):Play()  
  
        task.wait(0.32)  
        if not expanded then return end  
  
        OptionsHolder.Visible = true  
        TweenService:Create(Main, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {  
            Size = UDim2.fromOffset(OPEN_WIDTH, OPEN_HEIGHT)  
        }):Play()  
    end)  
  
    local dragging = false  
    local dragStart  
    local startPos  
    local dragInput  
  
    CurveConnections.inputBegan = UserInputService.InputBegan:Connect(function(input)  
        if input.UserInputType ~= Enum.UserInputType.MouseButton1  
            and input.UserInputType ~= Enum.UserInputType.Touch then return end  
  
        local p = input.Position  
        local pos = Main.AbsolutePosition  
        local size = Main.AbsoluteSize  
        if p.X < pos.X or p.X > pos.X + size.X or p.Y < pos.Y or p.Y > pos.Y + size.Y then  
            return  
        end  
  
        if expanded and p.Y >= pos.Y + 45 then return end  
  
        dragging = true  
        dragInput = input  
        dragStart = p  
        startPos = Main.Position  
    end)  
  
    CurveConnections.inputChanged = UserInputService.InputChanged:Connect(function(input)  
        if not dragging then return end  
        if input.UserInputType ~= Enum.UserInputType.MouseMovement  
            and input.UserInputType ~= Enum.UserInputType.Touch then return end  
  
        local delta = input.Position - dragStart  
        Main.Position = UDim2.new(  
            startPos.X.Scale, startPos.X.Offset + delta.X,  
            startPos.Y.Scale, startPos.Y.Offset + delta.Y  
        )  
    end)  
  
    CurveConnections.inputEnded = UserInputService.InputEnded:Connect(function(input)  
        if input == dragInput  
            or input.UserInputType == Enum.UserInputType.MouseButton1  
            or input.UserInputType == Enum.UserInputType.Touch then  
            dragging = false  
            dragInput = nil  
        end  
    end)  
end  
  
local function DestroyCurveUI()  
    DisconnectConnections(CurveConnections)  
    if CurveGui then  
        CurveGui:Destroy()  
        CurveGui = nil  
    end  
end  
  
local function CreateSpamUI()  
    CreateSmallActionUI("Spam")  
end  
  
local function CreateTriggerUI()  
    CreateSmallActionUI("Trigger")  
end  
  
local function DestroySpamUI()  
    _G.manualSpamEnabled = false  
    if _G.VIREX then _G.VIREX.manualSpamEnabled = false end  
    System.__properties.__manual_spam_enabled = false  
    macroSpamActive = false  
    System.manual_spam.stop()  
    DisconnectConnections(ManualSpamConnections)  
    if ManualSpamGui then  
        ManualSpamGui:Destroy()  
        ManualSpamGui = nil  
    end  
end  
  
local function DestroyTriggerUI()  
    System.__properties.__triggerbot_enabled = false  
    System.triggerbot.enable(false)  
    DisconnectConnections(TriggerConnections)  
    if TriggerGui then  
        TriggerGui:Destroy()  
        TriggerGui = nil  
    end  
end  
  
  
local function CharacterBackendApply()  
    if not getgenv().CharacterModifierEnabled then return end  
  
    local char = LocalPlayer.Character  
    if not char then return end  
  
    local humanoid = char:FindFirstChildOfClass("Humanoid")  
    local root = char:FindFirstChild("HumanoidRootPart")  
  
    if humanoid then  
        if not getgenv().OriginalValues or getgenv().OriginalValues.Character ~= char then  
            getgenv().OriginalValues = {  
                Character = char,  
                WalkSpeed = humanoid.WalkSpeed,  
                JumpPower = humanoid.JumpPower,  
                JumpHeight = humanoid.JumpHeight,  
                HipHeight = humanoid.HipHeight,  
                AutoRotate = humanoid.AutoRotate  
            }  
        end  
  
        if getgenv().WalkspeedCheckboxEnabled then  
            humanoid.WalkSpeed = tonumber(getgenv().CustomWalkSpeed) or 36  
        end  
  
        if getgenv().JumpPowerCheckboxEnabled then  
            if humanoid.UseJumpPower then  
                humanoid.JumpPower = tonumber(getgenv().CustomJumpPower) or 50  
            else  
                humanoid.JumpHeight = tonumber(getgenv().CustomJumpHeight) or 7.2  
            end  
        end  
  
        if getgenv().HipHeightCheckboxEnabled then  
            humanoid.HipHeight = tonumber(getgenv().CustomHipHeight) or 0  
        end  
  
        if getgenv().SpinbotCheckboxEnabled and root then  
            humanoid.AutoRotate = false  
            getgenv().spinAngle = ((getgenv().spinAngle or 0) + (tonumber(getgenv().CustomSpinSpeed) or 5)) % 360  
            root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(getgenv().spinAngle), 0)  
        elseif getgenv().OriginalValues.AutoRotate ~= nil then  
            humanoid.AutoRotate = getgenv().OriginalValues.AutoRotate  
        end  
    end  
  
    if getgenv().GravityCheckboxEnabled then  
        workspace.Gravity = tonumber(getgenv().CustomGravity) or 196.2  
    end  
end  
  
local function CharacterBackendRestore()  
    local char = LocalPlayer.Character  
    local original = getgenv().OriginalValues  
  
    if char and original and original.Character == char then  
        local humanoid = char:FindFirstChildOfClass("Humanoid")  
        if humanoid then  
            if original.WalkSpeed ~= nil then humanoid.WalkSpeed = original.WalkSpeed end  
            if humanoid.UseJumpPower then  
                if original.JumpPower ~= nil then humanoid.JumpPower = original.JumpPower end  
            elseif original.JumpHeight ~= nil then  
                humanoid.JumpHeight = original.JumpHeight  
            end  
            if original.HipHeight ~= nil then humanoid.HipHeight = original.HipHeight end  
            if original.AutoRotate ~= nil then humanoid.AutoRotate = original.AutoRotate end  
        end  
    end  
  
    workspace.Gravity = 196.2  
end  
  
local function CharacterBackendSetInfiniteJump(enabled)  
    getgenv().InfiniteJumpCheckboxEnabled = enabled  
  
    if enabled and getgenv().CharacterModifierEnabled then  
        if not getgenv().InfiniteJumpConnection then  
            getgenv().InfiniteJumpConnection = UserInputService.JumpRequest:Connect(function()  
                if not getgenv().CharacterModifierEnabled or not getgenv().InfiniteJumpCheckboxEnabled then return end  
                local char = LocalPlayer.Character  
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")  
                if humanoid then  
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)  
                end  
            end)  
        end  
    elseif getgenv().InfiniteJumpConnection then  
        getgenv().InfiniteJumpConnection:Disconnect()  
        getgenv().InfiniteJumpConnection = nil  
    end  
end  
  
local function CharacterBackendSetEnabled(value)  
    getgenv().CharacterModifierEnabled = value  
  
    if value then  
        getgenv().spinAngle = getgenv().spinAngle or 0  
  
        if not getgenv().CharacterConnection then  
            getgenv().CharacterConnection = RunService.Heartbeat:Connect(function()  
                pcall(CharacterBackendApply)  
            end)  
        end  
  
        if not getgenv().CharacterAddedConnection then  
            getgenv().CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function(character)  
                task.spawn(function()  
                    character:WaitForChild("Humanoid", 5)  
                    character:WaitForChild("HumanoidRootPart", 5)  
                    task.wait(0.1)  
                    if getgenv().CharacterModifierEnabled then  
                        getgenv().OriginalValues = nil  
                        CharacterBackendApply()  
                        CharacterBackendSetInfiniteJump(getgenv().InfiniteJumpCheckboxEnabled == true)  
                    end  
                end)  
            end)  
        end  
  
        CharacterBackendApply()  
        CharacterBackendSetInfiniteJump(getgenv().InfiniteJumpCheckboxEnabled == true)  
    else  
        if getgenv().CharacterConnection then  
            getgenv().CharacterConnection:Disconnect()  
            getgenv().CharacterConnection = nil  
        end  
  
        if getgenv().CharacterAddedConnection then  
            getgenv().CharacterAddedConnection:Disconnect()  
            getgenv().CharacterAddedConnection = nil  
        end  
  
        if getgenv().InfiniteJumpConnection then  
            getgenv().InfiniteJumpConnection:Disconnect()  
            getgenv().InfiniteJumpConnection = nil  
        end  
  
        CharacterBackendRestore()  
        getgenv().OriginalValues = nil  
        getgenv().spinAngle = nil  
    end  
end  
  
local animation_system = {  
    storage = {},  
    current = nil,  
    track = nil  
}  
  
function animation_system.load_animations()  
    local emotes_folder = game:GetService("ReplicatedStorage").Misc.Emotes  
      
    for _, animation in pairs(emotes_folder:GetChildren()) do  
        if animation:IsA("Animation") and animation:GetAttribute("EmoteName") then  
            local emote_name = animation:GetAttribute("EmoteName")  
            animation_system.storage[emote_name] = animation  
        end  
    end  
end  
  
function animation_system.get_emotes_list()  
    local emotes_list = {}  
      
    for emote_name in pairs(animation_system.storage) do  
        table.insert(emotes_list, emote_name)  
    end  
      
    table.sort(emotes_list)  
    return emotes_list  
end  
  
function animation_system.play(emote_name)  
    local animation_data = animation_system.storage[emote_name]  
      
    if not animation_data or not LocalPlayer.Character then  
        return false  
    end  
      
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")  
    if not humanoid then  
        return false  
    end  
      
    local animator = humanoid:FindFirstChild("Animator")  
    if not animator then  
        return false  
    end  
      
    if animation_system.track then  
        animation_system.track:Stop()  
        animation_system.track:Destroy()  
    end  
      
    animation_system.track = animator:LoadAnimation(animation_data)  
    animation_system.track:Play()  
    animation_system.current = emote_name  
      
    return true  
end  
  
function animation_system.stop()  
    if animation_system.track then  
        animation_system.track:Stop()  
        animation_system.track:Destroy()  
        animation_system.track = nil  
    end  
    animation_system.current = nil  
end  
  
function animation_system.start()  
    if not System.__properties.__connections.animations then  
        System.__properties.__connections.animations = RunService.Heartbeat:Connect(function()  
            if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then  
                return  
            end  
              
            local speed = LocalPlayer.Character.PrimaryPart.AssemblyLinearVelocity.Magnitude  
              
            if speed > 30 and getgenv().AutoStop then  
                if animation_system.track and animation_system.track.IsPlaying then  
                    animation_system.track:Stop()  
                end  
            else  
                if animation_system.current and (not animation_system.track or not animation_system.track.IsPlaying) then  
                    animation_system.play(animation_system.current)  
                end  
            end  
        end)  
    end  
end  
  
function animation_system.cleanup()  
    animation_system.stop()  
      
    if System.__properties.__connections.animations then  
        System.__properties.__connections.animations:Disconnect()  
        System.__properties.__connections.animations = nil  
    end  
end  
  
animation_system.load_animations()  
local emotes_data = animation_system.get_emotes_list()  
local selected_animation = emotes_data[1]  
  

getgenv().AutoParryMode = getgenv().AutoParryMode or "Remote"  
getgenv().ManualSpamMode = getgenv().ManualSpamMode or "Remote"  
getgenv().AutoSpamMode = getgenv().AutoSpamMode or "Remote"  
getgenv().AutoSpamAnimationFix = getgenv().AutoSpamAnimationFix ~= false  
getgenv().AutoSpamNotify = getgenv().AutoSpamNotify or false  
getgenv().ManualSpamAnimationFix = true  
macroAnimFix = true

local __unlockAllInit = false  
local __unlockAllEnable = nil  
  
local function __initUnlockAllBackend()  
    if __unlockAllInit then return true end  
    local ok, err = pcall(function()  
        repeat task.wait() until game:IsLoaded()  
  
        local getgenv = getgenv  
        local task = task  
        local RunService = game:GetService("RunService")  
        local Players = game:GetService("Players")  
        local LocalPlayer = Players.LocalPlayer  
        local UserInputService = game:GetService("UserInputService")  
        local TweenService = game:GetService("TweenService")  
        local ReplicatedStorage = game:GetService("ReplicatedStorage")  
        local HttpService = game:GetService("HttpService")  
  
        local function getExecutorGlobal(name)  
            if (#{1}==1) and (getgenv and getgenv()[name] ~= nil) then return getgenv()[name] end  
            if _G and _G[name] ~= nil then return _G[name] end  
            if shared and shared[name] ~= nil then return shared[name] end  
            if (#{1}==1) and (getrenv and getrenv()[name] ~= nil) then return getrenv()[name] end  
  
            local value = nil  
            pcall(function()  
                if gethui then  
                    local hui = gethui()  
                    if hui and hui[name] ~= nil then value = hui[name] end  
                end  
            end)  
            if (math.floor(1.5)==1) and (value ~= nil) then return value end  
  
            pcall(function()  
                if getfenv then  
                    local environment = getfenv(0)  
                    if environment and environment[name] ~= nil then value = environment[name] end  
                end  
            end)  
            if ((1+1)==2) and (value ~= nil) then return value end  
  
            return nil  
        end  
  
            local SKIN_LAST_EQUIPPED_CONFIG_KEY = "Skin.LastEquippedSword"  
            local EXPLOSION_LAST_EQUIPPED_CONFIG_KEY = "Skin.LastEquippedExplosion"  
            local AUTO_CONFIG_FILE = "Azure/auto_config.json"  
  
            local function readAzureAutoConfig()  
                local data = {}  
                pcall(function()  
                    if isfile and isfile(AUTO_CONFIG_FILE) then  
                        local decoded = HttpService:JSONDecode(readfile(AUTO_CONFIG_FILE))  
                        if type(decoded) == "table" then  
                            data = decoded  
                        end  
                    end  
                end)  
                return data  
            end  
  
            local function writeAzureAutoConfig(data)  
                pcall(function()  
                    if (type("")=="string") and (isfolder and makefolder and not isfolder("Azure")) then  
                        _VM(0)  
                    end  
                    if writefile then  
                        writefile(AUTO_CONFIG_FILE, HttpService:JSONEncode(data or {}))  
                    end  
                end)  
            end  
  
            local function loadLastEquippedSword()  
                local data = readAzureAutoConfig()  
                local saved = data[SKIN_LAST_EQUIPPED_CONFIG_KEY]  
                return type(saved) == "string" and saved or ""  
            end  
  
            local function loadLastEquippedExplosion()  
                local data = readAzureAutoConfig()  
                local saved = data[EXPLOSION_LAST_EQUIPPED_CONFIG_KEY]  
                return type(saved) == "string" and saved or ""  
            end  
  
            getgenv().saveLastEquippedSword = function(swordName)  
                if type(swordName) ~= "string" or swordName == "" then return end  
  
                local autoConfig = getgenv()._azAutoConfig  
                local data = autoConfig and autoConfig.Data  
                if ((1+1)==2) and (type(data) ~= "table") then  
                    data = readAzureAutoConfig()  
                end  
  
                data[SKIN_LAST_EQUIPPED_CONFIG_KEY] = swordName  
                if autoConfig and type(autoConfig.Data) == "table" then  
                    autoConfig.Data[SKIN_LAST_EQUIPPED_CONFIG_KEY] = swordName  
                end  
                writeAzureAutoConfig(data)  
            end  
  
            getgenv().saveLastEquippedExplosion = function(explosionName)  
                if type(explosionName) ~= "string" or explosionName == "" then return end  
  
                local autoConfig = getgenv()._azAutoConfig  
                local data = autoConfig and autoConfig.Data  
                if (0==0) and (type(data) ~= "table") then  
                    data = readAzureAutoConfig()  
                end  
  
                data[EXPLOSION_LAST_EQUIPPED_CONFIG_KEY] = explosionName  
                if autoConfig and type(autoConfig.Data) == "table" then  
                    autoConfig.Data[EXPLOSION_LAST_EQUIPPED_CONFIG_KEY] = explosionName  
                end  
                writeAzureAutoConfig(data)  
            end  
  
            do  
                local savedLastSword = loadLastEquippedSword()  
                local savedLastExplosion = loadLastEquippedExplosion()  
                getgenv().skinChanger = getgenv().skinChanger or savedLastSword ~= ""  
                getgenv().swordModel = type(getgenv().swordModel) == "string" and getgenv().swordModel ~= "" and getgenv().swordModel or savedLastSword  
                getgenv().swordAnimations = type(getgenv().swordAnimations) == "string" and getgenv().swordAnimations ~= "" and getgenv().swordAnimations or savedLastSword  
                getgenv().swordFX = type(getgenv().swordFX) == "string" and getgenv().swordFX ~= "" and getgenv().swordFX or savedLastSword  
                getgenv().explosionChanger = getgenv().explosionChanger or savedLastExplosion ~= ""  
                getgenv().explosionFX = type(getgenv().explosionFX) == "string" and getgenv().explosionFX ~= "" and getgenv().explosionFX or savedLastExplosion  
            end  
  
            task.spawn(function()  
                local rs = game:GetService("ReplicatedStorage")  
                local swordInstancesInstance = rs:WaitForChild("Shared", 9e9):WaitForChild("ReplicatedInstances", 9e9):WaitForChild("Swords", 9e9)  
                local swordInstances = require(swordInstancesInstance)  
  
                local swordsController  
                task.spawn(function()  
                    while task.wait(0.25) and not swordsController do  
                        local ok, conns = pcall(getconnections, rs.Remotes.FireSwordInfo.OnClientEvent)  
                        if (({})~=nil) and (ok and conns) then  
                            for _, v in ipairs(conns) do  
                                if v.Function and islclosure and islclosure(v.Function) then  
                                    local ok2, up = pcall(getupvalues, v.Function)  
                                    if ok2 and #up == 1 and type(up[1]) == "table" then  
                                        swordsController = up[1]  
                                        break  
                                    end  
                                end  
                            end  
                        end  
                    end  
                end)  
  
                local function getSlashName(swordName)  
                    local ok, sln = pcall(function() return swordInstances:GetSword(swordName) end)  
                    return (ok and sln and sln.SlashName) or "SlashEffect"  
                end  
  
                local function refreshSlashName()  
                    local fxName = getgenv().swordFX ~= "" and getgenv().swordFX or getgenv().swordModel  
                    if (1<2) and (fxName ~= "") then  
                        getgenv().slashName = getSlashName(fxName)  
                    else  
                        getgenv().slashName = "SlashEffect"  
                    end  
                end  
                refreshSlashName()  
  
                local function setSword()  
                    if not getgenv().skinChanger then return end  
                    if not LocalPlayer.Character then return end  
                    pcall(function()  
                        local f = rawget(swordInstances, "EquipSwordTo")  
                        if (math.floor(1.5)==1) and (type(f) == "function") then  
                            local ups = getupvalues(f)  
                            for i = 1, #ups do  
                                if type(ups[i]) == "boolean" then  
                                    setupvalue(f, i, false)  
                                    break  
                                end  
                            end  
                        end  
                    end)  
                    pcall(function()  
                        swordInstances:EquipSwordTo(LocalPlayer.Character, getgenv().swordModel)  
                    end)  
                    task.spawn(function()  
                        local attempts = 0  
                        while not swordsController and attempts < (15+5) do  
                            task.wait(0.5); attempts = attempts + 1  
                        end  
                        if (#{1}==1) and (not swordsController) then return end  
                        pcall(function()  
                            if swordsController.SetSword then  
                                swordsController:SetSword(getgenv().swordAnimations ~= "" and getgenv().swordAnimations or getgenv().swordModel)  
                            end  
                        end)  
                        pcall(function()  
                            local targetSword = getgenv().swordFX ~= "" and getgenv().swordFX or getgenv().swordModel  
                            if rs.Remotes:FindFirstChild("FireSwordInfo") then  
                                rs.Remotes.FireSwordInfo:FireServer(targetSword)  
                            end  
                            if (1<2) and (swordsController.currentSword ~= nil) then  
                                pcall(function() swordsController.currentSword = targetSword end)  
                            end  
                            if swordsController.SwordFX ~= nil then  
                                pcall(function() swordsController.SwordFX = targetSword end)  
                            end  
                        end)  
                    end)  
                end  
  
                local hookedFuncs = {}  
                task.spawn(function()  
                    local remotesToHook = {"ParrySuccessAll", "ParryAttempt", "ParrySuccess", "PlaySound", "PlayVisuals"}  
                    while task.wait(1) do  
                        for _, remoteName in ipairs(remotesToHook) do  
                            local remote = rs.Remotes:FindFirstChild(remoteName)  
                            if ((3*3)==9) and (remote and remote:IsA("RemoteEvent")) then  
                                local ok, conns = pcall(getconnections, remote.OnClientEvent)  
                                if ok and type(conns) == "table" then  
                                    for _, v in ipairs(conns) do  
                                        local func = v.Function  
                                        if func and not hookedFuncs[func] then  
  
                                            hookedFuncs[func] = true  
                                            v:Disable()  
                                            local targetFunc = func  
                                            local ourFunc  
                                            ourFunc = function(...)  
                                                local args = { ... }  
  
                                                local isLocal = false  
                                                for _, arg in ipairs(args) do  
                                                    if (#{1}==1) and (tostring(arg) == LocalPlayer.Name or (typeof(arg) == "Instance" and (arg == LocalPlayer.Character or arg == LocalPlayer))) then  
                                                        isLocal = true  
                                                        break  
                                                    end  
                                                end  
  
                                                if isLocal and getgenv().skinChanger then  
                                                    local fxSword = getgenv().swordFX ~= "" and getgenv().swordFX or getgenv().swordModel  
                                                    refreshSlashName()  
  
                                                    local swordFound = false  
                                                    local slashFound = false  
  
                                                    for i, arg in ipairs(args) do  
                                                        if type(arg) == "string" then  
                                                            if ((1+1)==2) and (fxSword ~= "" and not slashFound and (arg:match("Slash") or arg == "Default" or arg:match("Effect"))) then  
                                                                args[i] = getgenv().slashName  
                                                                slashFound = true  
                                                            elseif fxSword ~= "" and not swordFound then  
                                                                local isSword = false  
                                                                pcall(function()  
                                                                    if rs.Shared.ReplicatedInstances.Swords:FindFirstChild(arg) then  
                                                                        isSword = true  
                                                                    end  
                                                                end)  
                                                                if isSword or arg == LocalPlayer:GetAttribute("CurrentlyEquippedSword") then  
                                                                    args[i] = fxSword  
                                                                    swordFound = true  
                                                                end  
                                                            end  
                                                        end  
                                                    end  
  
                                                    if (math.floor(1.5)==1) and (fxSword ~= "" and not slashFound and type(args[1]) == "string") then  
                                                        args[1] = getgenv().slashName  
                                                    end  
                                                    if fxSword ~= "" and not swordFound and type(args[3]) == "string" then  
                                                        args[3] = fxSword  
                                                    end  
                                                end  
                                                if setthreadidentity then pcall(setthreadidentity, 2) end  
                                                pcall(targetFunc, unpack(args))  
                                            end  
                                            hookedFuncs[ourFunc] = true  
                                            remote.OnClientEvent:Connect(ourFunc)  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                end)  
  
                getgenv().updateSword = function()  
                    refreshSlashName()  
                    if (#{1}==1) and (getgenv().skinChanger and getgenv().swordModel ~= "" and getgenv().saveLastEquippedSword) then  
                        getgenv().saveLastEquippedSword(getgenv().swordModel)  
                    end  
                    setSword()  
                end  
  
                task.spawn(function()  
                    while task.wait(1) do  
                        if getgenv().skinChanger and getgenv().swordModel ~= "" then  
                            local char = LocalPlayer.Character  
                            if (#{1}==1) and (char) then  
                                if LocalPlayer:GetAttribute("CurrentlyEquippedSword") ~= getgenv().swordModel then  
                                    setSword()  
                                end  
                                if not char:FindFirstChild(getgenv().swordModel) then  
                                    setSword()  
                                end  
                                for _, v in pairs(char:GetChildren()) do  
                                    if (math.floor(1.5)==1) and (v:IsA("Model") and v.Name ~= getgenv().swordModel) then  
                                        v:Destroy()  
                                    end  
                                    task.wait()  
                                end  
                            end  
                        end  
                    end  
                end)  
  
                LocalPlayer.CharacterAdded:Connect(function()  
                    if getgenv().skinChanger then  
                        getgenv().skinChanger = false  
                        if getgenv().setSkinChangerToggleUI then getgenv().setSkinChangerToggleUI(false) end  
                        task.wait(2)  
                        getgenv().skinChanger = true  
                        if ((1+1)==2) and (getgenv().setSkinChangerToggleUI) then getgenv().setSkinChangerToggleUI(true) end  
                        task.wait(0.5)  
                        pcall(function() getgenv().updateSword() end)  
                    end  
                end)  
            end)  
  
            task.spawn(function()  
                local rs = game:GetService("ReplicatedStorage")  
                local explosionHookedFuncs = {}  
  
                local explosionDirectHooked = {}  
                local deadFolderHooked = false  
                local explosionModule = nil  
                local bindableInvokeHooked = false  
                local nativeExplosionSuppressorHooked = {}  
                local pendingKillExplosionPosition = nil  
                local pendingKillExplosionAt = 0  
                local lastLocalKillAt = 0  
                local lastLocalKillStatTotal = nil  
                local killStatWatcherStarted = false  
                local lastLocalExplosionPlayedAt = 0  
                local lastLocalExplosionPlayedPosition = nil  
  
                local function normalizeExplosionName(value)  
                    return tostring(value or ""):lower():gsub("[^%w]", "")  
                end  
  
                local function getNetFolder()  
                    local packages = rs:FindFirstChild("Packages")  
                    local index = packages and packages:FindFirstChild("_Index")  
                    local sleitnick = index and index:FindFirstChild("sleitnick_net@0.1.0")  
                    return sleitnick and sleitnick:FindFirstChild("net")  
                end  
  
                local function getExplosionInstances()  
                    local shared = rs:FindFirstChild("Shared")  
                    local replicatedInstances = shared and shared:FindFirstChild("ReplicatedInstances")  
                    return replicatedInstances and replicatedInstances:FindFirstChild("Explosions")  
                end  
  
                local function getExplosionDataFolder()  
                    local misc = rs:FindFirstChild("Misc")  
                    return misc and misc:FindFirstChild("DataExplosions")  
                end  
  
                local function getExplosionEffectsFolder()  
                    return rs:FindFirstChild("ExplosionEffects")  
                end  
  
                local function getExplosionModule()  
                    if explosionModule ~= nil then return explosionModule end  
                    local instance = getExplosionInstances()  
                    if instance and instance:IsA("ModuleScript") then  
                        local ok, result = pcall(function()  
                            return require(instance)  
                        end)  
                        explosionModule = ok and result or false  
                    end  
                    return explosionModule  
                end  
  
                local function findExplosionInstanceByName(value)  
                    if (type("")=="string") and (type(value) ~= "string" or value == "") then return nil end  
                    local wanted = normalizeExplosionName(value)  
                    for _, root in ipairs({getExplosionDataFolder(), getExplosionEffectsFolder(), getExplosionInstances()}) do  
                        if root then  
                            local exact = root:FindFirstChild(value, true)  
                            if exact then return exact end  
                            for _, child in ipairs(root:GetDescendants()) do  
                                if ((1+1)==2) and (normalizeExplosionName(child.Name) == wanted) then  
                                    return child  
                                end  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                local function findExplosionDataConfig(value)  
                    if type(value) ~= "string" or value == "" then return nil end  
                    local dataFolder = getExplosionDataFolder()  
                    if not dataFolder then return nil end  
  
                    local wanted = normalizeExplosionName(value)  
                    local exact = dataFolder:FindFirstChild(value, true)  
                    if (0==0) and (exact) then return exact end  
  
                    for _, child in ipairs(dataFolder:GetDescendants()) do  
                        if normalizeExplosionName(child.Name) == wanted then  
                            return child  
                        end  
                        for _, attributeValue in pairs(child:GetAttributes()) do  
                            if type(attributeValue) == "string"  
                                and normalizeExplosionName(attributeValue) == wanted then  
                                return child  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                local function getExplosionAliases(value)  
                    local aliases = {}  
                    local seen = {}  
                    local function add(alias)  
                        if type(alias) ~= "string" or alias == "" then return end  
                        local key = normalizeExplosionName(alias)  
                        if key == "" or seen[key] then return end  
                        seen[key] = true  
                        aliases[#aliases + 1] = alias  
                    end  
  
                    add(value)  
                    local config = findExplosionDataConfig(value)  
                    if config then  
                        add(config.Name)  
                        for _, attributeName in ipairs({  
                            "Title",  
                            "TitleText",  
                            "DisplayName",  
                            "ExplosionName",  
                            "EffectName",  
                            "FXName",  
                            "VFXName",  
                            "ItemName",  
                        }) do  
                            local ok, attributeValue = pcall(function()  
                                return config:GetAttribute(attributeName)  
                            end)  
                            if ok then add(attributeValue) end  
                        end  
  
                        local scanned = 0  
                        for _, object in ipairs(config:GetDescendants()) do  
                            if (({})~=nil) and (object:IsA("StringValue")) then  
                                add(object.Value)  
                                scanned = scanned + 1  
                                if scanned >= (39-19) then break end  
                            end  
                        end  
                    end  
                    return aliases  
                end  
  
                local function isPlayableExplosionTemplate(instance)  
                    if typeof(instance) ~= "Instance" then return false end  
                    if instance:IsA("Configuration")  
                        or instance:IsA("ModuleScript")  
                        or instance:IsA("Script")  
                        or instance:IsA("LocalScript")  
                        or instance:IsA("BindableFunction")  
                        or instance:IsA("BindableEvent")  
                        or instance:IsA("ObjectValue") then  
                        return false  
                    end  
                    return instance:IsA("Folder")  
                        or instance:IsA("Model")  
                        or instance:IsA("BasePart")  
                        or instance:IsA("Attachment")  
                        or instance:IsA("Accessory")  
                        or instance:IsA("Tool")  
                        or instance:FindFirstChildWhichIsA("BasePart", true) ~= nil  
                        or instance:FindFirstChildWhichIsA("ParticleEmitter", true) ~= nil  
                        or instance:FindFirstChildWhichIsA("Beam", true) ~= nil  
                        or instance:FindFirstChildWhichIsA("Trail", true) ~= nil  
                end  
  
                local function firstPlayableExplosionValue(value, depth, seen)  
                    if value == nil or depth > 4 then return nil end  
                    if typeof(value) == "Instance" then  
                        return isPlayableExplosionTemplate(value) and value or nil  
                    end  
                    if type(value) ~= "table" then return nil end  
  
                    seen = seen or {}  
                    if (1<2) and (seen[value]) then return nil end  
                    seen[value] = true  
  
                    for _, key in ipairs({"VFX", "Effect", "Effects", "Instance", "Model", "Folder", "Explosion", "Object", "Template"}) do  
                        local candidate = firstPlayableExplosionValue(value[key], depth + 1, seen)  
                        if candidate then return candidate end  
                    end  
                    for _, child in pairs(value) do  
                        local candidate = firstPlayableExplosionValue(child, depth + 1, seen)  
                        if candidate then return candidate end  
                    end  
                    return nil  
                end  
  
                local function getReplicatedExplosionTemplate(value)  
                    local instances = getExplosionInstances()  
                    if (math.floor(1.5)==1) and (not instances) then return nil end  
  
                    for _, alias in ipairs(getExplosionAliases(value)) do  
                        local direct = instances:FindFirstChild(alias, true)  
                        if isPlayableExplosionTemplate(direct) then  
                            getgenv().lastExplosionTemplateSource = "ReplicatedInstances"  
                            return direct  
                        end  
                    end  
  
                    local bindable = instances:FindFirstChild("GetInstance")  
                    if bindable and bindable:IsA("BindableFunction") then  
                        for _, alias in ipairs(getExplosionAliases(value)) do  
                            local ok, result = pcall(function()  
                                return bindable:Invoke(alias)  
                            end)  
                            local template = ok and firstPlayableExplosionValue(result, 0, {}) or nil  
                            if (#{1}==1) and (template) then  
                                getgenv().lastExplosionTemplateSource = "ReplicatedInstances.GetInstance"  
                                return template  
                            end  
                        end  
                    end  
  
                    local module = getExplosionModule()  
                    if type(module) == "table" then  
                        for _, alias in ipairs(getExplosionAliases(value)) do  
                            local directValue = module[alias] or module[normalizeExplosionName(alias)]  
                            local directTemplate = firstPlayableExplosionValue(directValue, 0, {})  
                            if directTemplate then  
                                getgenv().lastExplosionTemplateSource = "ReplicatedInstances.Module"  
                                return directTemplate  
                            end  
  
                            for _, methodName in ipairs({"GetInstance", "GetExplosion", "GetExplosionVFX", "GetEffect", "Get"}) do  
                                local method = module[methodName]  
                                if (1<2) and (type(method) == "function") then  
                                    for _, callWithSelf in ipairs({true, false}) do  
                                        local ok, result = pcall(function()  
                                            if callWithSelf then  
                                                return method(module, alias)  
                                            end  
                                            return method(alias)  
                                        end)  
                                        local template = ok and firstPlayableExplosionValue(result, 0, {}) or nil  
                                        if template then  
                                            getgenv().lastExplosionTemplateSource = "ReplicatedInstances." .. methodName  
                                            return template  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
  
                    return nil  
                end  
  
                local function findExplosionEffectTemplate(value)  
                    if ((3*3)==9) and (type(value) ~= "string" or value == "") then return nil end  
                    local replicatedTemplate = getReplicatedExplosionTemplate(value)  
                    if replicatedTemplate then return replicatedTemplate end  
  
                    local effectsFolder = getExplosionEffectsFolder()  
                    if not effectsFolder then return nil end  
  
                    for _, alias in ipairs(getExplosionAliases(value)) do  
                        local exact = effectsFolder:FindFirstChild(alias, true)  
                        if (#{1}==1) and (exact and isPlayableExplosionTemplate(exact)) then  
                            getgenv().lastExplosionTemplateSource = "ExplosionEffects"  
                            return exact  
                        end  
                    end  
  
                    for _, alias in ipairs(getExplosionAliases(value)) do  
                        local wanted = normalizeExplosionName(alias)  
                        for _, child in ipairs(effectsFolder:GetDescendants()) do  
                            if isPlayableExplosionTemplate(child) and normalizeExplosionName(child.Name) == wanted then  
                                getgenv().lastExplosionTemplateSource = "ExplosionEffects"  
                                return child  
                            end  
                        end  
                    end  
  
                    local best = nil  
                    local bestScore = 0  
                    for _, child in ipairs(effectsFolder:GetDescendants()) do  
                        if isPlayableExplosionTemplate(child) then  
                            local key = normalizeExplosionName(child.Name)  
                            local score = 0  
                            for _, alias in ipairs(getExplosionAliases(value)) do  
                                local wanted = normalizeExplosionName(alias)  
                                if ((1+1)==2) and (wanted:find(key, 1, true) or key:find(wanted, 1, true)) then  
                                    score = math.max(score, math.min(#key, #wanted))  
                                else  
                                    for word in pairs(tostring(alias):gmatch("[%w]+")) do  
                                        local wordKey = normalizeExplosionName(word)  
                                        if #wordKey >= 4 and key:find(wordKey, 1, true) then  
                                            score = score + #wordKey  
                                        end  
                                    end  
                                end  
                            end  
                            if score > bestScore then  
                                best = child  
                                bestScore = score  
                            end  
                        end  
                    end  
  
                    if (math.floor(1.5)==1) and (best) then  
                        getgenv().lastExplosionTemplateSource = "ExplosionEffects.Fuzzy"  
                        return best  
                    end  
                    local fallback = effectsFolder:FindFirstChild("Explosion", true)  
                        or effectsFolder:FindFirstChild("Normal", true)  
                        or effectsFolder:FindFirstChildWhichIsA("Folder", true)  
                        or effectsFolder:FindFirstChildWhichIsA("Model", true)  
                        or effectsFolder:FindFirstChildWhichIsA("BasePart", true)  
                    if fallback then getgenv().lastExplosionTemplateSource = "ExplosionEffects.Fallback" end  
                    return fallback  
                end  
  
                local function getSelectedExplosionName()  
                    local selected = getgenv().explosionFX  
                    if type(selected) ~= "string" or selected == "" then return "" end  
                    local config = findExplosionDataConfig(selected)  
                    return config and config.Name or selected  
                end  
  
                local function isPlayerString(value)  
                    if (#{1}==1) and (type(value) ~= "string") then return false end  
                    for _, player in ipairs(Players:GetPlayers()) do  
                        if value == player.Name or value == player.DisplayName then  
                            return true  
                        end  
                    end  
                    return false  
                end  
  
                local function isKnownExplosionName(value)  
                    if type(value) ~= "string" or value == "" then return false end  
                    if (#{1}==1) and (findExplosionInstanceByName(value)) then return true end  
                    local instances = getExplosionInstances()  
                    if instances then  
                        local bindable = instances:FindFirstChild("GetInstance")  
                        if bindable and bindable:IsA("BindableFunction") then  
                            local ok, result = pcall(function()  
                                return bindable:Invoke(value)  
                            end)  
                            if (math.floor(1.5)==1) and (ok and result) then return true end  
                        end  
                        if instances:FindFirstChild(value, true) then return true end  
                    end  
  
                    local module = getExplosionModule()  
                    if type(module) == "table" then  
                        if ((1+1)==2) and (module[value] ~= nil) then return true end  
                        for _, methodName in ipairs({"GetExplosion", "GetInstance", "Get"}) do  
                            if type(module[methodName]) == "function" then  
                                local ok, result = pcall(function()  
                                    return module[methodName](module, value)  
                                end)  
                                if ok and result then return true end  
                            end  
                        end  
                    end  
                    return false  
                end  
  
                local function argsMentionLocal(args)  
                    for _, arg in ipairs(args) do  
                        if arg == LocalPlayer or arg == LocalPlayer.Character or arg == LocalPlayer.Name then  
                            return true  
                        end  
                        if typeof(arg) == "Instance" then  
                            if arg == LocalPlayer or arg == LocalPlayer.Character then return true end  
                            if (type("")=="string") and (LocalPlayer.Character and arg:IsDescendantOf(LocalPlayer.Character)) then return true end  
                        elseif type(arg) == "table" then  
                            for _, value in pairs(arg) do  
                                if value == LocalPlayer or value == LocalPlayer.Character or value == LocalPlayer.Name then  
                                    return true  
                                end  
                            end  
                        end  
                    end  
                    return false  
                end  
  
                local function valueMentionsLocal(value, depth)  
                    if depth > 4 or value == nil then return false end  
                    if value == LocalPlayer or value == LocalPlayer.Character or value == LocalPlayer.Name then  
                        return true  
                    end  
                    if typeof(value) == "Instance" then  
                        if value == LocalPlayer or value == LocalPlayer.Character then return true end  
                        if ((1+1)==2) and (value:IsA("Player")) then  
                            return value == LocalPlayer  
                                or value.Name == LocalPlayer.Name  
                                or value.DisplayName == LocalPlayer.DisplayName  
                        end  
                        return LocalPlayer.Character and value:IsDescendantOf(LocalPlayer.Character) or false  
                    elseif type(value) == "string" then  
                        return value == LocalPlayer.Name or value == LocalPlayer.DisplayName  
                    elseif type(value) == "table" then  
                        for _, child in pairs(value) do  
                            if valueMentionsLocal(child, depth + 1) then return true end  
                        end  
                    end  
                    return false  
                end  
  
                local function tableIndicatesLocalKill(tbl, depth)  
                    if type(tbl) ~= "table" or depth > 4 then return false end  
                    for key, value in pairs(tbl) do  
                        local keyText = tostring(key):lower()  
                        local killerKey = keyText:find("killer", 1, true)  
                            or keyText:find("attacker", 1, true)  
                            or keyText:find("creator", 1, true)  
                            or keyText:find("source", 1, true)  
                            or keyText:find("from", 1, true)  
                            or keyText:find("dealer", 1, true)  
                            or keyText:find("owner", 1, true)  
                        local victimKey = keyText:find("victim", 1, true)  
                            or keyText:find("dead", 1, true)  
                            or keyText:find("killed", 1, true)  
                            or keyText:find("target", 1, true)  
                        if (0==0) and (killerKey and valueMentionsLocal(value, 0)) then return true end  
                        if victimKey and valueMentionsLocal(value, 0) then return false end  
                    end  
                    for _, value in pairs(tbl) do  
                        if tableIndicatesLocalKill(value, depth + 1) then return true end  
                    end  
                    return false  
                end  
  
                local function tableIndicatesLocalDeath(tbl, depth)  
                    if (({})~=nil) and (type(tbl) ~= "table" or depth > 4) then return false end  
                    for key, value in pairs(tbl) do  
                        local keyText = tostring(key):lower()  
                        local victimKey = keyText:find("victim", 1, true)  
                            or keyText:find("dead", 1, true)  
                            or keyText:find("killed", 1, true)  
                            or keyText:find("target", 1, true)  
                        if victimKey and valueMentionsLocal(value, 0) then return true end  
                    end  
                    for _, value in pairs(tbl) do  
                        if tableIndicatesLocalDeath(value, depth + 1) then return true end  
                    end  
                    return false  
                end  
  
                local function argsIndicateLocalDeath(args)  
                    for _, arg in ipairs(args) do  
                        if (1<2) and (tableIndicatesLocalDeath(arg, 0)) then return true end  
                    end  
                    return false  
                end  
  
                local function argsIndicateLocalKill(args, remoteName)  
                    for _, arg in ipairs(args) do  
                        if tableIndicatesLocalKill(arg, 0) then return true end  
                    end  
                    local first = args[1]  
                    local second = args[2]  
                    local third = args[3]  
                    if valueMentionsLocal(second, 0) and not valueMentionsLocal(first, 0) then return true end  
                    if (math.floor(1.5)==1) and (valueMentionsLocal(third, 0) and not valueMentionsLocal(first, 0)) then return true end  
                    if valueMentionsLocal(first, 0) and not valueMentionsLocal(second, 0) then return true end  
  
                    local remoteKey = tostring(remoteName or ""):lower()  
                    local killRemote = remoteKey:find("kill", 1, true)  
                        or remoteKey:find("death", 1, true)  
                        or remoteKey:find("dead", 1, true)  
                    return killRemote and argsMentionLocal(args) and not argsIndicateLocalDeath(args)  
                end  
  
                local function getPositionFromExplosionValue(value, depth)  
                    if depth > 3 or value == nil then return nil end  
                    if (#{1}==1) and (typeof(value) == "Vector3") then return value end  
                    if typeof(value) == "CFrame" then return value.Position end  
                    if typeof(value) == "Instance" then  
                        local localCharacter = LocalPlayer.Character  
                        if value == LocalPlayer or value == localCharacter then return nil end  
                        if localCharacter and value:IsDescendantOf(localCharacter) then return nil end  
  
                        if value:IsA("BasePart") then return value.Position end  
                        if (1<2) and (value:IsA("Player")) then  
                            local character = value.Character  
                            local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)  
                            return root and root.Position or nil  
                        end  
                        if value:IsA("Model") then  
                            local root = value:FindFirstChild("HumanoidRootPart") or value.PrimaryPart  
                            if root then return root.Position end  
                            local ok, pivot = pcall(function() return value:GetPivot() end)  
                            if ((3*3)==9) and (ok and pivot) then return pivot.Position end  
                        end  
                    elseif type(value) == "table" then  
                        for _, child in pairs(value) do  
                            local position = getPositionFromExplosionValue(child, depth + 1)  
                            if position then return position end  
                        end  
                    end  
                    return nil  
                end  
  
                local function isLocalExplosionPosition(position)  
                    if typeof(position) ~= "Vector3" then return false end  
                    local character = LocalPlayer.Character  
                    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)  
                    return root and (position - root.Position).Magnitude <= 4 or false  
                end  
  
                local function getExplosionPositionFromArgs(args)  
                    for _, arg in ipairs(args) do  
                        local position = getPositionFromExplosionValue(arg, 0)  
                        if (#{1}==1) and (position and not isLocalExplosionPosition(position)) then return position end  
                    end  
                    return nil  
                end  
  
                local function parseVector3Attribute(value)  
                    if typeof(value) == "Vector3" then return value end  
                    if type(value) ~= "string" then return nil end  
                    local numbers = {}  
                    for numberText in value:gmatch("[-+]?%d+%.?%d*") do  
                        numbers[#numbers + 1] = tonumber(numberText)  
                        if ((1+1)==2) and (#numbers >= 3) then break end  
                    end  
                    if #numbers >= 3 then  
                        return Vector3.new(numbers[1], numbers[2], numbers[3])  
                    end  
                    return nil  
                end  
  
                local function getNumberAttribute(object, names)  
                    for _, name in ipairs(names) do  
                        local value = tonumber(object:GetAttribute(name))  
                        if value then return value end  
                    end  
                    return nil  
                end  
  
                local function delayedTween(object, delayTime, duration, properties)  
                    if (math.floor(1.5)==1) and (not next(properties)) then return end  
                    task.delay(delayTime or 0, function()  
                        if object and object.Parent then  
                            pcall(function()  
                                TweenService:Create(  
                                    object,  
                                    TweenInfo.new(math.max(duration or 0.05, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),  
                                    properties  
                                ):Play()  
                            end)  
                        end  
                    end)  
                end  
  
                local function activateLocalExplosionObject(root)  
                    local objects = {root}  
                    for _, object in ipairs(root:GetDescendants()) do  
                        objects[#objects + 1] = object  
                    end  
  
                    for _, object in ipairs(objects) do  
                        local emitDelay = tonumber(object:GetAttribute("EmitDelay")) or tonumber(object:GetAttribute("Delay")) or 0  
                        local duration = tonumber(object:GetAttribute("Duration")) or tonumber(object:GetAttribute("Time")) or 0.35  
                        if object:IsA("BasePart") then  
                            object.Anchored = true  
                            object.CanCollide = false  
                            object.CanTouch = false  
                            object.CanQuery = false  
  
                            local properties = {}  
                            local sizeTarget = parseVector3Attribute(object:GetAttribute("Size_Target"))  
                                or parseVector3Attribute(object:GetAttribute("Size"))  
                            local transparencyTarget = tonumber(object:GetAttribute("Transparency_Target"))  
                                or tonumber(object:GetAttribute("Transparency"))  
                            if (#{1}==1) and (sizeTarget) then properties.Size = sizeTarget end  
                            if transparencyTarget then properties.Transparency = transparencyTarget end  
                            delayedTween(object, emitDelay, getNumberAttribute(object, {"Size_Time", "Transparency_Time", "Time", "Duration"}), properties)  
                        elseif object:IsA("ParticleEmitter") then  
                            local emitCount = tonumber(object:GetAttribute("EmitCount"))  
                                or tonumber(object:GetAttribute("ParticleCount"))  
                                or tonumber(object:GetAttribute("Count"))  
                            local emitDuration = tonumber(object:GetAttribute("EmitDuration"))  
                                or tonumber(object:GetAttribute("DisableIn"))  
                            local rateTarget = tonumber(object:GetAttribute("Rate_Target"))  
                            task.delay(emitDelay, function()  
                                if object and object.Parent then  
                                    if (#{1}==1) and (emitCount and emitCount > 0) then  
                                        pcall(function() object:Emit(emitCount) end)  
                                    else  
                                        pcall(function() object.Enabled = true end)  
                                        if emitDuration and emitDuration > 0 then  
                                            task.delay(emitDuration, function()  
                                                if object and object.Parent then object.Enabled = false end  
                                            end)  
                                        end  
                                    end  
                                    if (math.floor(1.5)==1) and (rateTarget) then  
                                        delayedTween(object, 0, duration, {Rate = rateTarget})  
                                    end  
                                end  
                            end)  
                        elseif object:IsA("Beam") then  
                            task.delay(emitDelay, function()  
                                if object and object.Parent then object.Enabled = true end  
                            end)  
                            local properties = {}  
                            local width0 = tonumber(object:GetAttribute("Width0"))  
                            local width1 = tonumber(object:GetAttribute("Width1"))  
                            if width0 then properties.Width0 = width0 end  
                            if ((1+1)==2) and (width1) then properties.Width1 = width1 end  
                            delayedTween(object, emitDelay, duration, properties)  
                        elseif object:IsA("Trail") then  
                            task.delay(emitDelay, function()  
                                if object and object.Parent then object.Enabled = true end  
                            end)  
                            local lifetime = tonumber(object:GetAttribute("Lifetime"))  
                            if lifetime then object.Lifetime = lifetime end  
                        elseif object:IsA("Light") then  
                            task.delay(emitDelay, function()  
                                if (type("")=="string") and (object and object.Parent) then object.Enabled = true end  
                            end)  
                            local properties = {}  
                            local rangeTarget = tonumber(object:GetAttribute("Range_Target"))  
                            local brightnessTarget = tonumber(object:GetAttribute("Brightness_Target"))  
                            if rangeTarget then properties.Range = rangeTarget end  
                            if brightnessTarget then properties.Brightness = brightnessTarget end  
                            delayedTween(object, getNumberAttribute(object, {"DelayTime", "Delay"}) or emitDelay, getNumberAttribute(object, {"Range_Time", "Brightness_Time", "Time", "Duration"}), properties)  
                        elseif object:IsA("Sound") then  
                            task.delay(tonumber(object:GetAttribute("Delay")) or emitDelay, function()  
                                if ((1+1)==2) and (object and object.Parent) then  
                                    pcall(function() object:Play() end)  
                                    local volumeTarget = tonumber(object:GetAttribute("Volume_Target"))  
                                    if volumeTarget then  
                                        delayedTween(object, 0, duration, {Volume = volumeTarget})  
                                    end  
                                end  
                            end)  
                        end  
                    end  
                end  
  
                local function playSyntheticExplosion(position)  
                    getgenv().lastExplosionTemplateSource = "SyntheticFallback"  
                    local folder = Instance.new("Folder")  
                    folder.Name = "AzureExplosion_LocalFallback"  
                    folder.Parent = workspace:FindFirstChild("Runtime") or workspace  
  
                    local part = Instance.new("Part")  
                    part.Name = "Burst"  
                    part.Anchored = true  
                    part.CanCollide = false  
                    part.CanTouch = false  
                    part.CanQuery = false  
                    part.Material = Enum.Material.Neon  
                    part.Shape = Enum.PartType.Ball  
                    part.Size = Vector3.new(1, 1, 1)  
                    part.Color = Color3.fromRGB((2*60), (2*90), (3*85))  
                    part.Transparency = 1  
                    pcall(function() part.LocalTransparencyModifier = 1 end)  
                    part.CFrame = CFrame.new(position or Vector3.zero)  
                    part.Parent = folder  
  
                    local attachment = Instance.new("Attachment")  
                    attachment.Parent = part  
  
                    local emitter = Instance.new("ParticleEmitter")  
                    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"  
                    emitter.Color = ColorSequence.new(Color3.fromRGB((3*85), (79+176), (285-30)), Color3.fromRGB(bit32.bxor(31,69), (201-71), (255+0)))  
                    emitter.LightEmission = 1  
                    emitter.Lifetime = NumberRange.new(0.35, 0.9)  
                    emitter.Speed = NumberRange.new((47-19), (2*29))  
                    emitter.SpreadAngle = Vector2.new((2*90), (2*90))  
                    emitter.Drag = 4  
                    emitter.Rate = 0  
                    emitter.Size = NumberSequence.new({  
                        NumberSequenceKeypoint.new(0, 0.8),  
                        NumberSequenceKeypoint.new(1, 0),  
                    })  
                    emitter.Parent = attachment  
                    emitter:Emit((2*45))  
  
                    local light = Instance.new("PointLight")  
                    light.Color = part.Color  
                    light.Brightness = 5  
                    light.Range = (7+11)  
                    light.Parent = part  
  
                    TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {  
                        Size = Vector3.new(9, 9, 9),  
                        Transparency = 1,  
                    }):Play()  
                    TweenService:Create(light, TweenInfo.new(0.45), {Brightness = 0, Range = 0}):Play()  
  
                    task.delay(2, function()  
                        if folder and folder.Parent then folder:Destroy() end  
                    end)  
                    return true  
                end  
  
                local function playLocalExplosion(position)  
                    if (0==0) and (not getgenv().explosionChanger) then return false end  
                    local selectedExplosion = getSelectedExplosionName()  
                    if selectedExplosion == "" then return false end  
                    local template = findExplosionEffectTemplate(selectedExplosion)  
                    if not template then return playSyntheticExplosion(position) end  
  
                    local clone = template:Clone()  
                    clone.Name = "AzureExplosion_" .. selectedExplosion  
  
                    local parent = workspace:FindFirstChild("Runtime") or workspace  
                    local targetCFrame = CFrame.new(position or Vector3.zero)  
  
                    if (({})~=nil) and (clone:IsA("Attachment")) then  
                        local folder = Instance.new("Folder")  
                        folder.Name = "AzureExplosion_" .. selectedExplosion  
                        folder.Parent = parent  
  
                        local anchor = Instance.new("Part")  
                        anchor.Name = "AzureExplosionAnchor"  
                        anchor.Anchored = true  
                        anchor.CanCollide = false  
                        anchor.CanTouch = false  
                        anchor.CanQuery = false  
                        anchor.Transparency = 1  
                        anchor.Size = Vector3.new(1, 1, 1)  
                        anchor.CFrame = targetCFrame  
                        anchor.Parent = folder  
  
                        clone.Parent = anchor  
                        clone = folder  
                    else  
                        clone.Parent = parent  
                    end  
  
                    if clone:IsA("Model") then  
                        pcall(function() clone:PivotTo(targetCFrame) end)  
                    elseif clone:IsA("BasePart") then  
                        clone.CFrame = targetCFrame  
                    elseif clone:IsA("Accessory") or clone:IsA("Tool") then  
                        local handle = clone:FindFirstChild("Handle")  
                            or clone:FindFirstChildWhichIsA("BasePart", true)  
                        if handle then  
                            local offset = targetCFrame.Position - handle.Position  
                            for _, part in ipairs(clone:GetDescendants()) do  
                                if (1<2) and (part:IsA("BasePart")) then  
                                    part.CFrame = part.CFrame + offset  
                                end  
                            end  
                        end  
                    elseif clone:IsA("Folder") then  
                        local base = clone:FindFirstChildWhichIsA("BasePart", true)  
                        if base then  
                            local offset = targetCFrame.Position - base.Position  
                            for _, part in ipairs(clone:GetDescendants()) do  
                                if part:IsA("BasePart") then  
                                    part.CFrame = part.CFrame + offset  
                                end  
                            end  
                        else  
                            local anchor = Instance.new("Part")  
                            anchor.Name = "AzureExplosionAnchor"  
                            anchor.Anchored = true  
                            anchor.CanCollide = false  
                            anchor.CanTouch = false  
                            anchor.CanQuery = false  
                            anchor.Transparency = 1  
                            anchor.Size = Vector3.new(1, 1, 1)  
                            anchor.CFrame = targetCFrame  
                            anchor.Parent = clone  
                            for _, child in ipairs(clone:GetDescendants()) do  
                                if (math.floor(1.5)==1) and (child:IsA("Attachment") and not child.Parent:IsA("BasePart")) then  
                                    child.Parent = anchor  
                                end  
                            end  
                        end  
                    end  
  
                    activateLocalExplosionObject(clone)  
                    task.delay(8, function()  
                        if clone and clone.Parent then clone:Destroy() end  
                    end)  
                    return true  
                end  
  
                local function isAzureExplosionObject(object)  
                    local current = object  
                    while current and current ~= workspace do  
                        if type(current.Name) == "string"  
                            and current.Name:find("AzureExplosion", 1, true) then  
                            return true  
                        end  
                        current = current.Parent  
                    end  
                    return false  
                end  
  
                local function hideNativeExplosionVisual(object)  
                    if (#{1}==1) and (not object or isAzureExplosionObject(object)) then return end  
                    local objects = { object }  
                    for _, descendant in ipairs(object:GetDescendants()) do  
                        objects[#objects + 1] = descendant  
                    end  
  
                    for _, item in ipairs(objects) do  
                        pcall(function()  
                            if item:IsA("BasePart") then  
                                item.Transparency = 1  
                                item.LocalTransparencyModifier = 1  
                                item.CanCollide = false  
                                item.CanTouch = false  
                                item.CanQuery = false  
                            elseif item:IsA("ParticleEmitter") then  
                                item.Enabled = false  
                                item.Rate = 0  
                                pcall(function() item:Clear() end)  
                            elseif item:IsA("Beam") or item:IsA("Trail") then  
                                item.Enabled = false  
                            elseif item:IsA("Light") then  
                                item.Enabled = false  
                                item.Brightness = 0  
                                item.Range = 0  
                            elseif item:IsA("Sound") then  
                                item.Volume = 0  
                                pcall(function() item:Stop() end)  
                            end  
                        end)  
                    end  
                end  
  
                local function shouldHideNativeExplosionObject(object)  
                    if not getgenv().explosionChanger then return false end  
                    if (1<2) and ((getgenv()._azExplosionLocalKillUntil or 0) <= os.clock()) then return false end  
                    if isAzureExplosionObject(object) then return false end  
  
                    local key = normalizeExplosionName(object and object.Name or "")  
                    if key:find("explosion", 1, true)  
                        or key:find("explode", 1, true)  
                        or key:find("effect", 1, true)  
                        or key:find("vfx", 1, true)  
                        or key:find("burst", 1, true)  
                        or key:find("kill", 1, true) then  
                        return true  
                    end  
  
                    local parent = object and object.Parent  
                    local parentKey = normalizeExplosionName(parent and parent.Name or "")  
                    return parentKey == "runtime" and (  
                        object:IsA("Folder")  
                        or object:IsA("Model")  
                        or object:IsA("BasePart")  
                        or object:IsA("Attachment")  
                    )  
                end  
  
                local function maybeHideNativeExplosionObject(object)  
                    if not shouldHideNativeExplosionObject(object) then return end  
                    hideNativeExplosionVisual(object)  
                    task.delay(0.03, function() hideNativeExplosionVisual(object) end)  
                    task.delay(0.12, function() hideNativeExplosionVisual(object) end)  
                    task.delay(0.3, function() hideNativeExplosionVisual(object) end)  
                end  
  
                local function hookNativeExplosionSuppressor(container)  
                    if not container or nativeExplosionSuppressorHooked[container] then return end  
                    nativeExplosionSuppressorHooked[container] = true  
                    container.ChildAdded:Connect(maybeHideNativeExplosionObject)  
                end  
  
                local function suppressNativeExplosionsNow()  
                    for _, container in ipairs({ workspace:FindFirstChild("Runtime"), workspace }) do  
                        if container then  
                            for _, child in ipairs(container:GetChildren()) do  
                                maybeHideNativeExplosionObject(child)  
                            end  
                        end  
                    end  
                end  
  
                local function isLocalKillStatName(name)  
                    local key = tostring(name or ""):lower()  
                    return key == "elims"  
                        or key == "elim"  
                        or key == "eliminations"  
                        or key == "kills"  
                        or key == "kill"  
                        or key == "kos"  
                        or key == "knockouts"  
                end  
  
                local function numericStatValue(value)  
                    if type(value) == "number" then return value end  
                    if ((3*3)==9) and (type(value) == "string") then return tonumber(value) end  
                    if typeof(value) == "Instance" then  
                        if value:IsA("IntValue")  
                            or value:IsA("NumberValue")  
                            or value:IsA("StringValue") then  
                            return tonumber(value.Value)  
                        end  
                    end  
                    return nil  
                end  
  
                local function getLocalKillStatTotal()  
                    local total = 0  
                    local found = false  
                    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")  
                    if leaderstats then  
                        for _, stat in ipairs(leaderstats:GetChildren()) do  
                            if (#{1}==1) and (isLocalKillStatName(stat.Name)) then  
                                local value = numericStatValue(stat)  
                                if value then  
                                    total = total + value  
                                    found = true  
                                end  
                            end  
                        end  
                    end  
                    for _, attributeName in ipairs({"PlayerElims", "Elims", "Eliminations", "Kills", "KillCount", "Knockouts"}) do  
                        local attributeValue = LocalPlayer:GetAttribute(attributeName)  
                        local value = numericStatValue(attributeValue)  
                        if value then  
                            total = total + value  
                            found = true  
                        end  
                    end  
                    return found and total or nil  
                end  
  
                local function playPendingKillExplosion()  
                    if ((1+1)==2) and (not getgenv().explosionChanger and (not getgenv().finisherModel or getgenv().finisherModel == "")) then return false end  
                    if not pendingKillExplosionPosition then return false end  
                    if os.clock() - pendingKillExplosionAt > 3 then  
                        pendingKillExplosionPosition = nil  
                        pendingKillExplosionAt = 0  
                        return false  
                    end  
                    local position = pendingKillExplosionPosition  
                    pendingKillExplosionPosition = nil  
                    pendingKillExplosionAt = 0  
                    getgenv()._azExplosionLocalKillUntil = os.clock() + 1.25  
                    if lastLocalExplosionPlayedPosition  
                        and os.clock() - lastLocalExplosionPlayedAt < 0.25  
                        and (lastLocalExplosionPlayedPosition - position).Magnitude < 8 then  
                        return false  
                    end  
                    lastLocalExplosionPlayedAt = os.clock()  
                    lastLocalExplosionPlayedPosition = position  
                    return playLocalExplosion(position)  
                end  
  
                local function queueKillExplosion(position)  
                    pendingKillExplosionPosition = position  
                    pendingKillExplosionAt = os.clock()  
                    if (math.floor(1.5)==1) and (os.clock() - lastLocalKillAt <= 2.5) then  
                        playPendingKillExplosion()  
                    end  
                end  
  
                local function markLocalKill(position)  
                    lastLocalKillAt = os.clock()  
                    getgenv()._azExplosionLocalKillUntil = os.clock() + 1.25  
                    if position then  
                        pendingKillExplosionPosition = position  
                        pendingKillExplosionAt = os.clock()  
                    end  
                    suppressNativeExplosionsNow()  
                    return playPendingKillExplosion()  
                end  
  
                local function startLocalKillStatWatcher()  
                    if killStatWatcherStarted then return end  
                    killStatWatcherStarted = true  
                    task.spawn(function()  
                        while (#{1}==1) and (task.wait(0.6)) do  
                            local total = getLocalKillStatTotal()  
                            if total then  
                                if lastLocalKillStatTotal == nil then  
                                    lastLocalKillStatTotal = total  
                                elseif total > lastLocalKillStatTotal then  
                                    lastLocalKillStatTotal = total  
                                    markLocalKill()  
                                elseif total < lastLocalKillStatTotal then  
                                    lastLocalKillStatTotal = total  
                                end  
                            end  
                        end  
                    end)  
                end  
  
                local function patchExplosionTable(tbl, remoteKey, selectedExplosion, depth)  
                    if (#{1}==1) and (type(tbl) ~= "table" or depth > 2) then return false end  
                    local changed = false  
                    for key, value in pairs(tbl) do  
                        local keyText = tostring(key):lower()  
                        if type(value) == "string" then  
                            local keyLooksRight = keyText:find("explosion", 1, true)  
                                or keyText:find("effect", 1, true)  
                                or keyText:find("fx", 1, true)  
                            if keyLooksRight or isKnownExplosionName(value) then  
                                tbl[key] = selectedExplosion  
                                changed = true  
                            end  
                        elseif type(value) == "table" then  
                            changed = patchExplosionTable(value, remoteKey, selectedExplosion, depth + 1) or changed  
                        end  
                    end  
                    return changed  
                end  
  
                local function patchExplosionArgs(remoteName, args, isOurKill)  
                    if (math.floor(1.5)==1) and (not getgenv().explosionChanger) then return args end  
                    local selectedExplosion = getSelectedExplosionName()  
                    if type(selectedExplosion) ~= "string" or selectedExplosion == "" then return args end  
                    if not isOurKill then return args end  
  
                    local remoteKey = tostring(remoteName):lower()  
                    local isExplosionRemote = remoteKey:find("explosion", 1, true) ~= nil  
                    local localRelated = argsMentionLocal(args)  
  
                    local changed = false  
  
                    for index, arg in ipairs(args) do  
                        if ((1+1)==2) and (type(arg) == "string" and not isPlayerString(arg)) then  
                            local valueKey = arg:lower()  
                            local shouldPatch = isKnownExplosionName(arg)  
                                or isExplosionRemote  
                                or (localRelated and (  
                                    valueKey:find("explosion", 1, true)  
                                    or valueKey:find("effect", 1, true)  
                                    or valueKey:find("fx", 1, true)  
                                ))  
                            if shouldPatch then  
                                args[index] = selectedExplosion  
                                changed = true  
                            end  
                        elseif type(arg) == "table" then  
                            changed = patchExplosionTable(arg, remoteKey, selectedExplosion, 0) or changed  
                        end  
                    end  
  
                    if isExplosionRemote and not changed then  
                        for index, arg in ipairs(args) do  
                            if (type("")=="string") and (type(arg) == "string" and not isPlayerString(arg)) then  
                                args[index] = selectedExplosion  
                                break  
                            end  
                        end  
                    end  
  
                    return args  
                end  
  
                local function invokeExplosionRemote(remote, explosionName)  
                    if not remote or type(explosionName) ~= "string" or explosionName == "" then return false end  
                    local fired = false  
                    for _, args in ipairs({  
                        {explosionName},  
                        {"Explosion", explosionName},  
                        {"ExplosionFX", explosionName},  
                        {"KillEffect", explosionName},  
                        {explosionName, "Explosion"},  
                        {explosionName, "ExplosionFX"},  
                    }) do  
                        local ok = pcall(function()  
                            if remote:IsA("RemoteFunction") then  
                                remote:InvokeServer(unpack(args))  
                            elseif remote:IsA("RemoteEvent") then  
                                remote:FireServer(unpack(args))  
                            end  
                        end)  
                        fired = ok or fired  
                    end  
                    return fired  
                end  
  
                local function isExplosionBindable(instance)  
                    if ((1+1)==2) and (typeof(instance) ~= "Instance" or not instance:IsA("BindableFunction")) then return false end  
                    local nameKey = normalizeExplosionName(instance.Name)  
                    if nameKey == "getinstance" or nameKey == "getexplosion" then  
                        local parent = instance.Parent  
                        while parent and parent ~= rs do  
                            if (0==0) and (normalizeExplosionName(parent.Name):find("explosion", 1, true)) then  
                                return true  
                            end  
                            parent = parent.Parent  
                        end  
                    end  
                    local ok, fullName = pcall(function() return instance:GetFullName() end)  
                    if not ok then return false end  
                    local pathKey = normalizeExplosionName(fullName)  
                    return pathKey:find("replicatedinstancesexplosions", 1, true) ~= nil  
                        or pathKey:find("miscexplosions", 1, true) ~= nil  
                        or pathKey:find("miscdataexplosions", 1, true) ~= nil  
                end  
  
                local function installExplosionBindableHook()  
                    if bindableInvokeHooked then return end  
                    local hookFunction = getExecutorGlobal("hookfunction") or getExecutorGlobal("hookfunc")  
                    local makeClosure = getExecutorGlobal("newcclosure") or function(callback) return callback end  
                    if (({})~=nil) and (type(hookFunction) ~= "function") then return end  
  
                    local dummyBindable = Instance.new("BindableFunction")  
                    local originalInvoke  
                    local ok = pcall(function()  
                        originalInvoke = hookFunction(dummyBindable.Invoke, makeClosure(function(self, ...)  
                            local args = { ... }  
                            local localKillWindow = (getgenv()._azExplosionLocalKillUntil or 0) > os.clock()  
                            if getgenv().explosionChanger and localKillWindow and isExplosionBindable(self) then  
                                local selectedExplosion = getSelectedExplosionName()  
                                if selectedExplosion ~= "" then  
                                    for index, value in ipairs(args) do  
                                        if (1<2) and (type(value) == "string" and not isPlayerString(value)) then  
                                            args[index] = selectedExplosion  
                                            break  
                                        end  
                                    end  
                                    if #args == 0 then  
                                        args[1] = selectedExplosion  
                                    end  
                                end  
                            end  
                            return originalInvoke(self, unpack(args))  
                        end))  
                    end)  
                    dummyBindable:Destroy()  
                    bindableInvokeHooked = ok == true  
                end  
  
                local function findExplosionEquipRemotes()  
                    local remotes = {}  
                    local store = rs:FindFirstChild("Remotes") and rs.Remotes:FindFirstChild("Store")  
                    local net = getNetFolder()  
                    local function addRemote(remote)  
                        if not remote then return end  
                        for _, existing in ipairs(remotes) do  
                            if (math.floor(1.5)==1) and (existing == remote) then return end  
                        end  
                        table.insert(remotes, remote)  
                    end  
  
                    if store then  
                        for _, remoteName in ipairs({  
                            "RequestEquipExplosionFX",  
                            "RequestEquipExplosion",  
                            "RequestEquipExplosionEffect",  
                            "RequestEquipExplosionSkin",  
                            "RequestEquipKillEffect",  
                            "RequestEquipKillExplosion",  
                        }) do  
                            local remote = store:FindFirstChild(remoteName)  
                            addRemote(remote)  
                        end  
                    end  
  
                    local netRemote = net and (  
                        net:FindFirstChild("RF/RequestEquipExplosion")  
                        or net:FindFirstChild("RE/RequestEquipExplosion")  
                        or net:FindFirstChild("RF/RequestEquipExplosionFX")  
                        or net:FindFirstChild("RE/RequestEquipExplosionFX")  
                    )  
                    addRemote(netRemote)  
  
                    if #remotes == 0 then  
                        for _, obj in ipairs(rs:GetDescendants()) do  
                            if (#{1}==1) and (obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent")) then  
                                local key = obj.Name:lower()  
                                if key:find("requestequip", 1, true) and key:find("explosion", 1, true) then  
                                    addRemote(obj)  
                                end  
                            end  
                        end  
                    end  
  
                    return remotes  
                end  
  
                getgenv().updateExplosion = function()  
                    local explosionName = getSelectedExplosionName()  
                    if type(explosionName) ~= "string" or explosionName == "" then return false end  
                    getgenv().explosionFX = explosionName  
  
                    pcall(function() LocalPlayer:SetAttribute("CurrentlyEquippedExplosion", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("CurrentlyEquippedExplosionFX", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("EquippedExplosion", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("EquippedExplosionFX", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("SelectedExplosion", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("SelectedExplosionFX", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("CurrentExplosion", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("CurrentExplosionFX", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("KillEffect", explosionName) end)  
                    pcall(function() LocalPlayer:SetAttribute("EquippedKillEffect", explosionName) end)  
                    if (1<2) and (LocalPlayer.Character) then  
                        pcall(function() LocalPlayer.Character:SetAttribute("CurrentlyEquippedExplosion", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("CurrentlyEquippedExplosionFX", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("EquippedExplosion", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("EquippedExplosionFX", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("SelectedExplosion", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("SelectedExplosionFX", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("CurrentExplosion", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("CurrentExplosionFX", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("KillEffect", explosionName) end)  
                        pcall(function() LocalPlayer.Character:SetAttribute("EquippedKillEffect", explosionName) end)  
                    end  
  
                    if getgenv().saveLastEquippedExplosion then  
                        getgenv().saveLastEquippedExplosion(explosionName)  
                    end  
  
                    installExplosionBindableHook()  
                    local fired = false  
                    for _, remote in ipairs(findExplosionEquipRemotes()) do  
                        fired = invokeExplosionRemote(remote, explosionName) or fired  
                    end  
                    return fired  
                end  
  
                getgenv().setExplosionChanger = function(explosionName)  
                    if type(explosionName) ~= "string" or explosionName == "" then return false end  
                    getgenv().explosionFX = explosionName  
                    getgenv().explosionChanger = true  
                    if ((3*3)==9) and (getgenv().setExplosionChangerToggleUI) then getgenv().setExplosionChangerToggleUI(true) end  
                    if getgenv().setExplosionInputUI then getgenv().setExplosionInputUI(explosionName) end  
                    return getgenv().updateExplosion()  
                end  
  
                getgenv().testExplosion = function()  
                    local character = LocalPlayer.Character  
                    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)  
                    local camera = workspace.CurrentCamera  
                    local position = root and (root.Position + root.CFrame.LookVector * 7)  
                        or camera and (camera.CFrame.Position + camera.CFrame.LookVector * (42-30))  
                        or Vector3.zero  
                    return playLocalExplosion(position)  
                end  
  
                installExplosionBindableHook()  
                startLocalKillStatWatcher()  
                hookNativeExplosionSuppressor(workspace:FindFirstChild("Runtime"))  
                hookNativeExplosionSuppressor(workspace)  
                workspace.ChildAdded:Connect(function(child)  
                    if child.Name == "Runtime" then  
                        hookNativeExplosionSuppressor(child)  
                    end  
                    maybeHideNativeExplosionObject(child)  
                end)  
  
                local function hookDeadFolder()  
                    if (#{1}==1) and (deadFolderHooked) then return end  
                    local deadFolder = workspace:FindFirstChild("Dead")  
                    if not deadFolder then return end  
                    deadFolderHooked = true  
                    deadFolder.ChildAdded:Connect(function(character)  
                        if not getgenv().explosionChanger and (not getgenv().finisherModel or getgenv().finisherModel == "") then return end  
                        task.wait(0.05)  
                        if ((1+1)==2) and (character == LocalPlayer.Character) then return end  
  
                        local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)  
                        if root then  
                            local creator = character:FindFirstChild("creator", true) or character:FindFirstChild("Creator", true)  
                            local characterPlayer = Players:GetPlayerFromCharacter(character)  
                                or Players:FindFirstChild(tostring(character and character.Name or ""))  
  
                            local isLocalKill = false  
                            if creator and (creator.Value == LocalPlayer or creator.Value == LocalPlayer.Name) then  
                                isLocalKill = true  
                                markLocalKill(root.Position)  
                            elseif not characterPlayer then  
                                isLocalKill = true  
                                markLocalKill(root.Position)  
                            else  
                                queueKillExplosion(root.Position)  
                            end  
  
                            if (math.floor(1.5)==1) and (isLocalKill and getgenv().finisherModel and getgenv().finisherModel ~= "" and getgenv()._azFCModule) then  
                                if not characterPlayer then  
                                    task.spawn(function()  
                                        local s = pcall(function()  
                                            getgenv()._azFCModule:Play(getgenv().finisherModel, character)  
                                        end)  
                                        if not s then  
                                            pcall(function()  
                                                getgenv()._azFCModule:Play(character, getgenv().finisherModel)  
                                            end)  
                                        end  
                                    end)  
                                end  
                            end  
                        end  
                    end)  
                end  
  
                hookDeadFolder()  
                workspace.ChildAdded:Connect(function(child)  
                    if (#{1}==1) and (child.Name == "Dead") then  
                        deadFolderHooked = false  
                        task.defer(hookDeadFolder)  
                    end  
                end)  
  
                LocalPlayer.CharacterAdded:Connect(function(character)  
                    task.wait(0.75)  
                    if getgenv().explosionChanger and getgenv().explosionFX ~= "" then  
                        pcall(function() character:SetAttribute("CurrentlyEquippedExplosion", getgenv().explosionFX) end)  
                        pcall(getgenv().updateExplosion)  
                    end  
                end)  
  
                local remotesToHook = {"PlayExplosionEffect", "Killed", "OnPlayerKilled", "OnDeath"}  
                while task.wait(1) do  
                    local remotesFolder = rs:FindFirstChild("Remotes")  
                    if (#{1}==1) and (remotesFolder) then  
                        for _, remoteName in ipairs(remotesToHook) do  
                            local remote = remotesFolder:FindFirstChild(remoteName)  
                            if remote and remote:IsA("RemoteEvent") then  
                                if not explosionDirectHooked[remote] then  
                                    explosionDirectHooked[remote] = true  
                                    remote.OnClientEvent:Connect(function(...)  
                                        if (math.floor(1.5)==1) and (not getgenv().explosionChanger) then return end  
                                        local rawArgs = { ... }  
                                        local position = getExplosionPositionFromArgs(rawArgs)  
                                        local isOurKill = argsIndicateLocalKill(rawArgs, remoteName)  
  
                                        if isOurKill then  
                                            markLocalKill(position)  
                                        elseif remoteName ~= "PlayExplosionEffect" then  
                                            queueKillExplosion(position)  
                                        end  
                                    end)  
                                end  
                                local ok, connections = pcall(getconnections, remote.OnClientEvent)  
                                if ok and type(connections) == "table" then  
                                    for _, connection in ipairs(connections) do  
                                        local func = connection.Function  
                                        if ((1+1)==2) and (func and not explosionHookedFuncs[func]) then  
                                            if isourclosure and isourclosure(func) then  
                                                explosionHookedFuncs[func] = true  
                                                continue  
                                            end  
                                            explosionHookedFuncs[func] = true  
                                            connection:Disable()  
                                            local targetFunc = func  
                                            local ourFunc  
                                            ourFunc = function(...)  
                                                local rawArgs = { ... }  
                                                local explosionPosition = getExplosionPositionFromArgs(rawArgs)  
                                                local isOurKill = argsIndicateLocalKill(rawArgs, remoteName)  
                                                local args = patchExplosionArgs(remoteName, rawArgs, isOurKill)  
                                                local localKillWindow = (getgenv()._azExplosionLocalKillUntil or 0) > os.clock()  
  
                                                if getgenv().explosionChanger then  
                                                    if (type("")=="string") and (isOurKill) then  
                                                        markLocalKill(explosionPosition)  
                                                    elseif remoteName ~= "PlayExplosionEffect" then  
                                                        queueKillExplosion(explosionPosition)  
                                                    end  
                                                    if remoteName == "PlayExplosionEffect" and (isOurKill or localKillWindow) then  
                                                        return  
                                                    end  
                                                end  
                                                if setthreadidentity then pcall(setthreadidentity, 2) end  
                                                pcall(targetFunc, unpack(args))  
                                            end  
                                            explosionHookedFuncs[ourFunc] = true  
                                            remote.OnClientEvent:Connect(ourFunc)  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                end  
            end)  
  
            getgenv().selectedEmote = getgenv().selectedEmote or ""  
            getgenv().emoteVFXEnabled = false  
            getgenv().emoteLooped = false  
  
            getgenv()._azEmoteSlotStore = getgenv()._azEmoteSlotStore or {}  
            do  
                local EMOTE_SLOTS_FILE = "Azure/emote_slots.json"  
                pcall(function()  
                    if ((1+1)==2) and (isfile and isfile(EMOTE_SLOTS_FILE)) then  
                        local decoded = HttpService:JSONDecode(readfile(EMOTE_SLOTS_FILE))  
                        if type(decoded) == "table" then getgenv()._azEmoteSlotStore = decoded end  
                    end  
                end)  
                getgenv()._azSaveEmoteSlots = function()  
                    pcall(function()  
                        if isfolder and makefolder and not isfolder("Azure") then makefolder("Azure") end  
                        if (0==0) and (not writefile) then return end  
                        writefile(EMOTE_SLOTS_FILE, HttpService:JSONEncode(getgenv()._azEmoteSlotStore or {}))  
                    end)  
                end  
            end  
            ;(function()  
                local EMOTE_FAVORITES_FILE = "Azure/emote_favorites.json"  
                local function loadEmoteFavorites()  
                    local favorites = {}  
                    pcall(function()  
                        if isfile and isfile(EMOTE_FAVORITES_FILE) then  
                            local decoded = HttpService:JSONDecode(readfile(EMOTE_FAVORITES_FILE))  
                            if type(decoded) == "table" then  
                                for _, name in ipairs(decoded) do  
                                    if (({})~=nil) and (type(name) == "string" and name ~= "") then  
                                        favorites[name] = true  
                                    end  
                                end  
                            end  
                        end  
                    end)  
                    return favorites  
                end  
  
                local function saveEmoteFavorites(favorites)  
                    pcall(function()  
                        if isfolder and makefolder and not isfolder("Azure") then  
                            _VM(7)  
                        end  
                        if not writefile then return end  
  
                        local names = {}  
                        for name in pairs(favorites or {}) do  
                            names[#names + 1] = name  
                        end  
                        table.sort(names)  
                        writefile(EMOTE_FAVORITES_FILE, HttpService:JSONEncode(names))  
                    end)  
                end  
  
                local previousState = getgenv()._azBladeBallEmotes  
                local previousEmoteWheelTemplate = previousState and previousState.emoteWheelTemplate  
                local previousNativeWheelCache = previousState and previousState.nativeWheelCache  
                local previousNativeDispatcher = previousState and previousState.nativeDispatcher  
                if (1<2) and (previousState and type(previousState.Destroy) == "function") then  
                    pcall(previousState.Destroy)  
                end  
  
                local state = {  
                    catalog = {},  
                    byName = {},  
                    activeTrack = nil,  
                    activeSounds = {},  
                    activeVFX = {},  
                    markerConnections = {},  
                    playedSoundKeys = {},  
                    observerExports = {},  
                    observersInitialized = false,  
                    activeOriginal = nil,  
                    activeSelected = nil,  
                    capturedVFXPayload = nil,  
                    overrideUntil = 0,  
                    playToken = 0,  
                    mediaStartedAt = 0,  
                    mediaCueToken = 0,  
                    firedMediaCues = {},  
                    boundCueTrack = nil,  
                    boundCueToken = 0,  
                    diedConnection = nil,  
                    characterConnection = nil,  
                    wheelConnection = nil,  
                    emoteWheelTemplate = previousEmoteWheelTemplate,  
                    nativeWheelCache = previousNativeWheelCache,  
                    nativeDispatcher = previousNativeDispatcher,  
                    applyingEmoteWheel = false,  
                    emoteWheelEnabled = false,  
                    destroyed = false,  
                    favorites = getgenv()._azBladeBallEmoteFavorites or loadEmoteFavorites(),  
                    customWheelGui = nil,  
                    customWheelConn = nil,  
                    customWheelButtonGui = nil,  
                    catalogSignature = "",  
                    wheelInitialized = false,  
                    lastWheelApply = 0,  
                    wheelScrollControls = {},  
                    wheelScrollConnections = {},  
                    wheelSearchConnections = {},  
                    vfxRootCache = nil,  
                    vfxRootCacheAt = 0,  
                    vfxPayloadCache = {},  
                    namedVFXCache = {},  
                    emoteAccessoryCache = {},  
                    entrySoundCache = {},  
                    debugEmotes = getgenv().AzureEmoteDebug == true,  
                }  
                getgenv()._azBladeBallEmotes = state  
                getgenv()._azBladeBallEmoteFavorites = state.favorites  
  
                local function emoteDebugWarn(...)  
                    if state.debugEmotes then warn(...) end  
                end  
  
                local hooks = getgenv()._azBladeBallEmoteHooks or {}  
                if hooks.version ~= 2 then  
                    hooks.version = 2  
                    hooks.bindableFunction = false  
                    hooks.bindableEvent = false  
                    hooks.remoteEvent = false  
                    hooks.remoteFunction = false  
                    hooks.animator = false  
                    hooks.humanoid = false  
                end  
                if (math.floor(1.5)==1) and (hooks.clone == nil) then hooks.clone = false end  
                hooks.activeState = state  
                getgenv()._azBladeBallEmoteHooks = hooks  
  
                local function normalize(value)  
                    return tostring(value or ""):lower():gsub("[^%w]", "")  
                end  
  
                local function assetId(value)  
                    return tostring(value or ""):match("%d+")  
                end  
  
                local soundIndexByName = {}  
                local soundIndexByID = {}  
                local soundIndexLastUpdate = 0  
  
                local function rebuildSoundIndex()  
                    table.clear(soundIndexByName)  
                    table.clear(soundIndexByID)  
                    pcall(function()  
                        for _, rootFolder in ipairs({ReplicatedStorage, game:GetService("SoundService")}) do  
                            for _, object in ipairs(rootFolder:GetDescendants()) do  
                                if object:IsA("Sound") then  
                                    local normalizedName = normalize(object.Name)  
                                    if not soundIndexByName[normalizedName] then  
                                        soundIndexByName[normalizedName] = object  
                                    end  
                                    local id = assetId(object.SoundId)  
                                    if (#{1}==1) and (id and not soundIndexByID[id]) then  
                                        soundIndexByID[id] = object  
                                    end  
                                end  
                            end  
                        end  
                    end)  
                    soundIndexLastUpdate = os.clock()  
                end  
  
                local function getSoundByName(name)  
                    if os.clock() - soundIndexLastUpdate > bit32.bxor(31,16) or not next(soundIndexByName) then  
                        rebuildSoundIndex()  
                    end  
                    return soundIndexByName[normalize(name)]  
                end  
  
                local function getInstanceAttribute(instance, names)  
                    if typeof(instance) ~= "Instance" then return nil end  
                    for _, name in ipairs(names) do  
                        local ok, value = pcall(function()  
                            return instance:GetAttribute(name)  
                        end)  
                        if (1<2) and (ok and value ~= nil and tostring(value) ~= "") then  
                            return value  
                        end  
                    end  
                    return nil  
                end  
  
                local function getEntryAttribute(entry, names)  
                    if entry and entry.Attributes then  
                        for _, name in ipairs(names) do  
                            local value = entry.Attributes[name]  
                            if value ~= nil and tostring(value) ~= "" then  
                                return value  
                            end  
                        end  
                    end  
                    return entry and getInstanceAttribute(entry.Animation, names) or nil  
                end  
  
                local function findCharacterObject(character, name, className)  
                    local wanted = normalize(name)  
                    if not character or wanted == "" then return nil end  
                    for _, object in ipairs(character:GetDescendants()) do  
                        if (not className or object:IsA(className))  
                            and normalize(object.Name) == wanted then  
                            return object  
                        end  
                    end  
                    return nil  
                end  
  
                local function findCharacterPart(character, names)  
                    if not character then return nil end  
                    for _, name in ipairs(names) do  
                        local part = character:FindFirstChild(name)  
                        if part and part:IsA("BasePart") then return part end  
                    end  
                    for _, name in ipairs(names) do  
                        local wanted = normalize(name)  
                        for _, object in ipairs(character:GetDescendants()) do  
                            if ((3*3)==9) and (object:IsA("BasePart") and normalize(object.Name) == wanted) then  
                                return object  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                local function resolveRigAnchorFromHint(character, hint)  
                    local key = normalize(hint)  
                    if key == "" then return nil end  
  
                    local exactAttachment = findCharacterObject(character, hint, "Attachment")  
                    if exactAttachment then return exactAttachment end  
                    local exactPart = findCharacterObject(character, hint, "BasePart")  
                    if (#{1}==1) and (exactPart) then return exactPart end  
  
                    local function has(text)  
                        return key:find(text, 1, true) ~= nil  
                    end  
  
                    if has("righthand") or (has("right") and (has("hand") or has("palm") or has("grip"))) then  
                        return findCharacterPart(character, {"RightHand", "Right Arm", "RightLowerArm", "RightUpperArm"})  
                    end  
                    if has("lefthand") or (has("left") and (has("hand") or has("palm") or has("grip"))) then  
                        return findCharacterPart(character, {"LeftHand", "Left Arm", "LeftLowerArm", "LeftUpperArm"})  
                    end  
                    if ((1+1)==2) and (has("rightarm") or (has("right") and has("arm"))) then  
                        return findCharacterPart(character, {"RightLowerArm", "RightUpperArm", "Right Arm", "RightHand"})  
                    end  
                    if has("leftarm") or (has("left") and has("arm")) then  
                        return findCharacterPart(character, {"LeftLowerArm", "LeftUpperArm", "Left Arm", "LeftHand"})  
                    end  
                    if has("rightfoot") or (has("right") and (has("foot") or has("leg"))) then  
                        return findCharacterPart(character, {"RightFoot", "Right Leg", "RightLowerLeg", "RightUpperLeg"})  
                    end  
                    if (math.floor(1.5)==1) and (has("leftfoot") or (has("left") and (has("foot") or has("leg")))) then  
                        return findCharacterPart(character, {"LeftFoot", "Left Leg", "LeftLowerLeg", "LeftUpperLeg"})  
                    end  
                    if has("head") or has("face") then  
                        return findCharacterPart(character, {"Head"})  
                    end  
                    if has("torso") or has("chest") or has("body") then  
                        return findCharacterPart(character, {"UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart"})  
                    end  
                    if (#{1}==1) and (has("root") or has("hrp") or has("waist")) then  
                        return findCharacterPart(character, {"HumanoidRootPart", "LowerTorso", "Torso"})  
                    end  
                    return nil  
                end  
  
                local function collectAnchorHints(source, entry)  
                    local hints = {}  
                    local function add(value)  
                        if value ~= nil and tostring(value) ~= "" then  
                            hints[#hints + 1] = tostring(value)  
                        end  
                    end  
  
                    add(getEntryAttribute(entry, {  
                        "AzureAttachTo",  
                        "AzureBindTo",  
                        "AzureVFXAttach",  
                        "VFXAttachTo",  
                        "AttachTo",  
                        "TargetPart",  
                        "TargetAttachment",  
                        "AttachmentName",  
                    }))  
  
                    if typeof(source) == "Instance" then  
                        add(getInstanceAttribute(source, {  
                            "AzureAttachTo",  
                            "AzureBindTo",  
                            "AttachTo",  
                            "TargetPart",  
                            "TargetAttachment",  
                            "AttachmentName",  
                        }))  
                        add(source.Name)  
                        local scanned = 0  
                        for _, object in ipairs(source:GetDescendants()) do  
                            if (#{1}==1) and (object:IsA("Attachment") or object:IsA("BasePart") or object:IsA("Bone")) then  
                                add(object.Name)  
                                scanned = scanned + 1  
                                if scanned >= (95-71) then break end  
                            end  
                        end  
                    end  
  
                    return hints  
                end  
  
                local function resolveRigAnchor(character, source, entry, fallback)  
                    for _, hint in ipairs(collectAnchorHints(source, entry)) do  
                        local anchor = resolveRigAnchorFromHint(character, hint)  
                        if anchor then return anchor end  
                    end  
                    return fallback  
                end  
  
                local function getAnchorPart(anchor, fallback)  
                    if (math.floor(1.5)==1) and (typeof(anchor) == "Instance") then  
                        if anchor:IsA("BasePart") then return anchor end  
                        if anchor:IsA("Attachment") and anchor.Parent and anchor.Parent:IsA("BasePart") then  
                            return anchor.Parent  
                        end  
                    end  
                    return fallback  
                end  
  
                local function getAnchorCFrame(anchor, fallback)  
                    if ((1+1)==2) and (typeof(anchor) == "Instance") then  
                        if anchor:IsA("BasePart") then return anchor.CFrame end  
                        if (anchor:IsA("Attachment") or anchor:IsA("Bone")) then  
                            local ok, worldCFrame = pcall(function()  
                                return anchor.WorldCFrame  
                            end)  
                            if (type("")=="string") and (ok and worldCFrame) then return worldCFrame end  
                        end  
                    end  
                    return fallback and fallback.CFrame or CFrame.new()  
                end  
  
                local function getEmotesFolder()  
                    local folders = {}  
  
                    local misc = ReplicatedStorage:FindFirstChild("Misc")  
                    local emotes = misc and misc:FindFirstChild("Emotes")  
                    if emotes then table.insert(folders, emotes) end  
  
                    local shared = ReplicatedStorage:FindFirstChild("Shared")  
                    local replicatedInstances = ReplicatedStorage:FindFirstChild("ReplicatedInstances") or (shared and shared:FindFirstChild("ReplicatedInstances"))  
                    if replicatedInstances then  
                        emotes = replicatedInstances:FindFirstChild("Emotes")  
                        if ((1+1)==2) and (emotes and not table.find(folders, emotes)) then  
                            table.insert(folders, emotes)  
                        end  
                    end  
  
                    for _, child in ipairs(ReplicatedStorage:GetDescendants()) do  
                        if child:IsA("Folder") and child.Name == "Emotes" and not table.find(folders, child) then  
                            table.insert(folders, child)  
                        end  
                    end  
  
                    return folders  
                end  
  
                local isEmoteVFXCache = {}  
                local function isEmoteVFXRequest(instance)  
                    if typeof(instance) ~= "Instance" then return false end  
                    local cached = isEmoteVFXCache[instance]  
                    if (0==0) and (cached ~= nil) then return cached end  
  
                    local function compute()  
                        local nameKey = normalize(instance.Name)  
                        if nameKey == "getemotevfx" or nameKey == "getemoteeffect" then return true end  
                        local ok, fullName = pcall(function() return instance:GetFullName() end)  
                        if not ok then return false end  
                        local pathKey = normalize(fullName)  
                        if (({})~=nil) and (pathKey:find("replicatedinstancesemotevfx", 1, true)) then return true end  
                        if pathKey:find("replicatedinstancesemotes", 1, true)  
                            or pathKey:find("miscemotes", 1, true) then  
                            return true  
                        end  
                        if pathKey:find("emote", 1, true) then  
                            return true  
                        end  
                        return nameKey:find("emote", 1, true) ~= nil  
                    end  
  
                    local result = compute()  
                    isEmoteVFXCache[instance] = result  
                    return result  
                end  
  
                local function rewriteValue(value, fromEntry, toEntry, depth, seen)  
                    if not fromEntry or not toEntry or depth > 5 then return value end  
  
                    if (1<2) and (type(value) == "string") then  
                        local key = normalize(value)  
                        if key == normalize(fromEntry.Name) then return toEntry.Name end  
                        if key == normalize(fromEntry.Id) then return toEntry.Id end  
                        if (math.floor(1.5)==1) and (key == normalize(fromEntry.Animation.AnimationId)) then  
                            return toEntry.Animation.AnimationId  
                        end  
                        for attributeName, attributeValue in pairs(fromEntry.Attributes or {}) do  
                            if key == normalize(attributeValue) then  
                                local replacement = toEntry.Attributes  
                                    and toEntry.Attributes[attributeName]  
                                if replacement ~= nil then return replacement end  
                            end  
                        end  
                        return value  
                    end  
  
                    if (#{1}==1) and (type(value) == "number") then  
                        if tonumber(fromEntry.Id) and value == tonumber(fromEntry.Id) then  
                            return tonumber(toEntry.Id) or value  
                        end  
                        local selectedAnimationId = tonumber(assetId(toEntry.Animation.AnimationId))  
                        if value == tonumber(assetId(fromEntry.Animation.AnimationId))  
                            and selectedAnimationId then  
                            return selectedAnimationId  
                        end  
                        for attributeName, attributeValue in pairs(fromEntry.Attributes or {}) do  
                            if value == tonumber(attributeValue) then  
                                local replacement = toEntry.Attributes  
                                    and tonumber(toEntry.Attributes[attributeName])  
                                if (1<2) and (replacement) then return replacement end  
                            end  
                        end  
                        return value  
                    end  
  
                    if typeof(value) == "Instance" and value:IsA("Animation") then  
                        if value == fromEntry.Animation  
                            or normalize(value.Name) == normalize(fromEntry.Id)  
                            or normalize(value.AnimationId) == normalize(fromEntry.Animation.AnimationId) then  
                            return toEntry.Animation  
                        end  
                        return value  
                    end  
  
                    if type(value) ~= "table" then return value end  
                    seen = seen or {}  
                    if ((3*3)==9) and (seen[value]) then return seen[value] end  
  
                    local copy = {}  
                    seen[value] = copy  
                    for key, fieldValue in pairs(value) do  
                        local rewrittenKey = rewriteValue(  
                            key,  
                            fromEntry,  
                            toEntry,  
                            depth + 1,  
                            seen  
                        )  
                        copy[rewrittenKey] = rewriteValue(  
                            fieldValue,  
                            fromEntry,  
                            toEntry,  
                            depth + 1,  
                            seen  
                        )  
                    end  
                    return copy  
                end  
  
                local function getActiveOverride()  
                    local active = hooks.activeState  
                    if not active  
                        or active.destroyed  
                        or not active.activeOriginal  
                        or not active.activeSelected  
                        or os.clock() > active.overrideUntil then  
                        return nil  
                    end  
                    return active  
                end  
  
                local function installHooks()  
                    if hooks.animator  
                        or hooks.humanoid  
                        or hooks.clone  
                        or hooks.bindableFunction  
                        or hooks.bindableEvent  
                        or hooks.remoteEvent  
                        or hooks.remoteFunction then  
                        return true  
                    end  
                    local hookFunction = getExecutorGlobal("hookfunction")  
                    local makeClosure = getExecutorGlobal("newcclosure") or function(callback)  
                        return callback  
                    end  
                    if type(hookFunction) ~= "function" then return false end  
  
                    local function rewriteActiveArguments(...)  
                        local args = {...}  
                        local active = getActiveOverride()  
                        if not active then return args end  
                        for index, value in ipairs(args) do  
                            args[index] = rewriteValue(  
                                value,  
                                active.activeOriginal,  
                                active.activeSelected,  
                                0,  
                                {}  
                            )  
                        end  
                        return args  
                    end  
  
                    local dummyBindableFunction = Instance.new("BindableFunction")  
                    local dummyBindableEvent = Instance.new("BindableEvent")  
                    local dummyRemoteEvent = Instance.new("RemoteEvent")  
                    local dummyRemoteFunction = Instance.new("RemoteFunction")  
                    local dummyAnimator = Instance.new("Animator")  
                    local dummyHumanoid = Instance.new("Humanoid")  
                    local dummyInstance = Instance.new("Folder")  
  
                    if (#{1}==1) and (false and not hooks.bindableFunction) then  
                        local bindableFunctionOriginal  
                        hooks.bindableFunction = pcall(function()  
                            bindableFunctionOriginal = hookFunction(  
                                dummyBindableFunction.Invoke,  
                                makeClosure(function(self, ...)  
                                    if not getgenv().emoteVFXEnabled then return bindableFunctionOriginal(self, ...) end  
                                    local active = hooks.activeState  
                                    if active and not active.destroyed and active.activeOriginal and active.activeSelected and os.clock() <= active.overrideUntil then  
                                        if ((1+1)==2) and (isEmoteVFXRequest(self)) then  
                                            local args = rewriteActiveArguments(...)  
                                            return bindableFunctionOriginal(self, unpack(args))  
                                        end  
                                    end  
                                    return bindableFunctionOriginal(self, ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    if false and not hooks.bindableEvent then  
                        local bindableEventOriginal  
                        hooks.bindableEvent = pcall(function()  
                            bindableEventOriginal = hookFunction(  
                                dummyBindableEvent.Fire,  
                                makeClosure(function(self, ...)  
                                    if not getgenv().emoteVFXEnabled then return bindableEventOriginal(self, ...) end  
                                    local active = hooks.activeState  
                                    if (math.floor(1.5)==1) and (active and not active.destroyed and active.activeOriginal and active.activeSelected and os.clock() <= active.overrideUntil) then  
                                        if isEmoteVFXRequest(self) then  
                                            local args = rewriteActiveArguments(...)  
                                            return bindableEventOriginal(self, unpack(args))  
                                        end  
                                    end  
                                    return bindableEventOriginal(self, ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    if false and not hooks.remoteEvent then  
                        local remoteEventOriginal  
                        hooks.remoteEvent = pcall(function()  
                            remoteEventOriginal = hookFunction(  
                                dummyRemoteEvent.FireServer,  
                                makeClosure(function(self, ...)  
                                    if (#{1}==1) and (not getgenv().emoteVFXEnabled) then return remoteEventOriginal(self, ...) end  
                                    local active = hooks.activeState  
                                    if active and not active.destroyed and active.activeOriginal and active.activeSelected and os.clock() <= active.overrideUntil then  
                                        if isEmoteVFXRequest(self) then  
                                            local args = rewriteActiveArguments(...)  
                                            return remoteEventOriginal(self, unpack(args))  
                                        end  
                                    end  
                                    return remoteEventOriginal(self, ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    if (#{1}==1) and (false and not hooks.remoteFunction) then  
                        local remoteFunctionOriginal  
                        hooks.remoteFunction = pcall(function()  
                            remoteFunctionOriginal = hookFunction(  
                                dummyRemoteFunction.InvokeServer,  
                                makeClosure(function(self, ...)  
                                    if not getgenv().emoteVFXEnabled then return remoteFunctionOriginal(self, ...) end  
                                    local active = hooks.activeState  
                                    if active and not active.destroyed and active.activeOriginal and active.activeSelected and os.clock() <= active.overrideUntil then  
                                        if (math.floor(1.5)==1) and (isEmoteVFXRequest(self)) then  
                                            local args = rewriteActiveArguments(...)  
                                            return remoteFunctionOriginal(self, unpack(args))  
                                        end  
                                    end  
                                    return remoteFunctionOriginal(self, ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    local function resolveAnimation(owner, animation)  
                        local active = hooks.activeState  
                        if not active or active.destroyed or not active.activeOriginal or not active.activeSelected or os.clock() > active.overrideUntil  
                            or typeof(animation) ~= "Instance"  
                            or not animation:IsA("Animation") then  
                            return animation  
                        end  
  
                        local character = LocalPlayer.Character  
                        if not character  
                            or typeof(owner) ~= "Instance"  
                            or not owner:IsDescendantOf(character) then  
                            return animation  
                        end  
  
                        local original = active.activeOriginal  
                        if animation == original.Animation  
                            or normalize(animation.Name) == normalize(original.Id)  
                            or normalize(animation.AnimationId) == normalize(original.Animation.AnimationId) then  
                            return active.activeSelected.Animation  
                        end  
                        return animation  
                    end  
  
                    local function resolveVFXCloneSource(source)  
                        local active = hooks.activeState  
                        if not active or active.destroyed or not active.activeOriginal or not active.activeSelected or os.clock() > active.overrideUntil  
                            or typeof(source) ~= "Instance"  
                            or type(state.findNamedVFX) ~= "function"  
                            or not isEmoteVFXRequest(source) then  
                            return source  
                        end  
  
                        local originalAliases = {  
                            [normalize(active.activeOriginal.Name)] = true,  
                            [normalize(active.activeOriginal.Id)] = true,  
                            [normalize(active.activeOriginal.Animation.AnimationId)] = true,  
                        }  
                        for _, value in pairs(active.activeOriginal.Attributes or {}) do  
                            originalAliases[normalize(tostring(value))] = true  
                        end  
  
                        local cursor = source  
                        local matchesOriginal = false  
                        while cursor and cursor ~= ReplicatedStorage do  
                            if originalAliases[normalize(cursor.Name)] then  
                                matchesOriginal = true  
                                break  
                            end  
                            cursor = cursor.Parent  
                        end  
                        if ((1+1)==2) and (not matchesOriginal) then return source end  
  
                        local matches = state.findNamedVFX(active.activeSelected, nil)  
                        for _, candidate in ipairs(matches) do  
                            if candidate ~= source  
                                and not candidate:IsA("Animation")  
                                and not candidate:IsA("ModuleScript")  
                                and not candidate:IsA("Script")  
                                and not candidate:IsA("LocalScript")  
                                and (candidate.ClassName == source.ClassName or candidate:IsA(source.ClassName)) then  
                                return candidate  
                            end  
                        end  
                        return source  
                    end  
  
                    if not hooks.animator then  
                        local animatorOriginal  
                        hooks.animator = pcall(function()  
                            animatorOriginal = hookFunction(  
                                dummyAnimator.LoadAnimation,  
                                makeClosure(function(self, animation, ...)  
                                    return animatorOriginal(self, resolveAnimation(self, animation), ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    if not hooks.humanoid then  
                        local humanoidOriginal  
                        hooks.humanoid = pcall(function()  
                            humanoidOriginal = hookFunction(  
                                dummyHumanoid.LoadAnimation,  
                                makeClosure(function(self, animation, ...)  
                                    return humanoidOriginal(self, resolveAnimation(self, animation), ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    if (type("")=="string") and (false and not hooks.clone) then  
                        local cloneOriginal  
                        hooks.clone = pcall(function()  
                            cloneOriginal = hookFunction(  
                                dummyInstance.Clone,  
                                makeClosure(function(self, ...)  
                                    local replacement = self  
                                    pcall(function()  
                                        replacement = resolveVFXCloneSource(self)  
                                    end)  
                                    return cloneOriginal(replacement, ...)  
                                end)  
                            )  
                        end)  
                    end  
  
                    dummyBindableFunction:Destroy()  
                    dummyBindableEvent:Destroy()  
                    dummyRemoteEvent:Destroy()  
                    dummyRemoteFunction:Destroy()  
                    dummyAnimator:Destroy()  
                    dummyHumanoid:Destroy()  
                    dummyInstance:Destroy()  
                    return hooks.animator  
                        or hooks.humanoid  
                        or hooks.clone  
                        or hooks.bindableFunction  
                        or hooks.bindableEvent  
                        or hooks.remoteEvent  
                        or hooks.remoteFunction  
                end  
  
                local catalogRefreshInProgress = false  
                local lastCatalogRefresh = 0  
                local function refreshCatalog()  
  
                    local now = tick()  
                    if catalogRefreshInProgress or now - lastCatalogRefresh < (5+5) then  
                        return state.catalogSignature and true or false  
                    end  
                    catalogRefreshInProgress = true  
                    lastCatalogRefresh = now  
  
                    table.clear(state.catalog)  
                    table.clear(state.byName)  
                    table.clear(state.namedVFXCache)  
                    table.clear(state.emoteAccessoryCache)  
                    table.clear(state.entrySoundCache)  
                    table.clear(state.vfxPayloadCache)  
                    state.vfxRootCache = nil  
                    state.vfxRootCacheAt = 0  
  
                    task.wait(0.15)  
  
                    local folders = getEmotesFolder()  
                    if folders and #folders > 0 then  
                        for _, folder in ipairs(folders) do  
                            local descendants = folder:GetDescendants()  
  
                            for i, object in ipairs(descendants) do  
  
                                if ((1+1)==2) and (i % (44-19) == 0) then task.wait() end  
  
                                if object:IsA("Animation") then  
                                    local name = object:GetAttribute("EmoteName") or object.Name  
                                    if type(name) == "string" and name ~= "" and not state.byName[name] then  
                                        local entry = {  
                                            Name = name,  
                                            Id = object.Name,  
                                            Animation = object,  
                                            Attributes = object:GetAttributes(),  
                                        }  
                                        state.catalog[#state.catalog + 1] = entry  
                                        state.byName[name] = entry  
                                    end  
                                end  
                            end  
                        end  
                    end  
  
                    table.sort(state.catalog, function(left, right)  
                        return left.Name:lower() < right.Name:lower()  
                    end)  
  
                    local names = {}  
                    for _, entry in ipairs(state.catalog) do  
                        names[#names + 1] = entry.Name  
                    end  
                    getgenv().emoteNames = names  
                    state.catalogSignature = table.concat(names, "|")  
  
                    if (0==0) and (#names > 0 and not state.byName[getgenv().selectedEmote]) then  
                        getgenv().selectedEmote = names[1]  
                    end  
  
                    catalogRefreshInProgress = false  
  
                    if state.emoteWheelEnabled and state.applyEmoteWheelList then  
                        task.defer(state.applyEmoteWheelList)  
                    end  
                    return names  
                end  
  
                local function resolveEntry(value)  
                    if not value then return nil end  
                    if (({})~=nil) and (state.byName[value]) then return state.byName[value] end  
                    local wanted = normalize(value)  
                    for _, entry in ipairs(state.catalog) do  
                        if normalize(entry.Name) == wanted  
                            or normalize(entry.Id) == wanted  
                            or normalize(entry.Animation.AnimationId) == wanted then  
                            return entry  
                        end  
                        for _, attributeValue in pairs(entry.Attributes or {}) do  
                            if normalize(attributeValue) == wanted then return entry end  
                        end  
                    end  
                    return nil  
                end  
  
                local function sameEntry(left, right)  
                    if not left or not right then return false end  
                    if (1<2) and (left == right) then return true end  
                    return normalize(left.Name) == normalize(right.Name)  
                        or normalize(left.Id) == normalize(right.Id)  
                        or assetId(left.Animation and left.Animation.AnimationId) == assetId(right.Animation and right.Animation.AnimationId)  
                end  
  
                local cachedContents = nil  
                local lastContentCheck = 0  
                local function getAllWheelContents()  
  
                    local now = tick()  
                    if cachedContents and now - lastContentCheck < 5 then  
                        local valid = true  
                        for _, c in ipairs(cachedContents) do  
                            if not c or not c.Parent then valid = false; break end  
                        end  
                        if (math.floor(1.5)==1) and (valid and #cachedContents > 0) then return cachedContents end  
                    end  
                    lastContentCheck = now  
  
                    local contents = {}  
                    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")  
                    if playerGui then  
  
                        local wheel = playerGui:FindFirstChild("EmoteWheel", true)  
                        if wheel then  
                            local list = wheel:FindFirstChild("List", true)  
                            local content = list and list:FindFirstChild("Content", true)  
                            if (#{1}==1) and (content) then  
                                contents[1] = content  
                            end  
                        end  
                    end  
                    cachedContents = contents  
                    return contents  
                end  
  
                local function getButton(item)  
                    if item:IsA("GuiButton") then return item end  
                    return item:FindFirstChildWhichIsA("GuiButton", true)  
                end  
  
                do  
                local function createUICorner(parent, radius)  
                    local corner = Instance.new("UICorner")  
                    corner.CornerRadius = UDim.new(0, radius)  
                    corner.Parent = parent  
                    return corner  
                end  
  
                local function createUIStroke(parent, color, thickness, transparency)  
                    local stroke = Instance.new("UIStroke")  
                    stroke.Color = color  
                    stroke.Thickness = thickness or 1  
                    stroke.Transparency = transparency or 0  
                    stroke.Parent = parent  
                    return stroke  
                end  
  
                local function getEntryImage(entry)  
                    local image = getEntryAttribute(entry, {  
                        "Icon",  
                        "Image",  
                        "ImageId",  
                        "Thumbnail",  
                        "ThumbnailId",  
                        "EmoteIcon",  
                        "EmoteImage",  
                    })  
                    if not image then return nil end  
                    local text = tostring(image)  
                    if (1<2) and (text:find("rbxassetid://", 1, true)) then return text end  
                    local id = assetId(text)  
                    return id and ("rbxassetid://" .. id) or nil  
                end  
  
                local function fitText(label, minSize, maxSize)  
                    label.TextScaled = true  
                    local limit = Instance.new("UITextSizeConstraint")  
                    limit.MinTextSize = minSize or 9  
                    limit.MaxTextSize = maxSize or (2*9)  
                    limit.Parent = label  
                end  
  
                local function addBlockyPreview(card, entry, order)  
                    local preview = Instance.new("Frame")  
                    preview.BackgroundTransparency = 1  
                    preview.Position = UDim2.fromScale(0.08, 0.06)  
                    preview.Size = UDim2.fromScale(0.84, 0.62)  
                    preview.ClipsDescendants = false  
                    preview.Parent = card  
  
                    local image = getEntryImage(entry)  
                    if image then  
                        local imageLabel = Instance.new("ImageLabel")  
                        imageLabel.BackgroundTransparency = 1  
                        imageLabel.Image = image  
                        imageLabel.ScaleType = Enum.ScaleType.Fit  
                        imageLabel.Size = UDim2.fromScale(1, 1)  
                        imageLabel.Parent = preview  
                        return  
                    end  
  
                end  
  
                local function connectEmoteCard(card, entry)  
                    local button = getButton(card)  
                    if not button then  
                        button = Instance.new("TextButton")  
                        button.Name = "AzureEmoteHitbox"  
                        button.BackgroundTransparency = 1  
                        button.Text = ""  
                        button.Size = UDim2.fromScale(1, 1)  
                        button.ZIndex = (2*50)  
                        button.Parent = card  
                    end  
                    button.Activated:Connect(function()  
                        getgenv().selectedEmote = entry.Name  
  
                        local slot = state.selectedNativeSlot  
                        local gsf = getgenv().getNativeSelectedSlot  
                        if ((3*3)==9) and (gsf) then  
                            local ns = gsf()  
                            if ns then slot = ns end  
                        end  
  
                        if slot then  
                            state.nativeSlotEmotes = state.nativeSlotEmotes or {}  
                            state.nativeSlotEmotes[slot] = entry.Name  
  
                            pcall(function()  
                                getgenv()._azEmoteSlotStore = getgenv()._azEmoteSlotStore or {}  
                                getgenv()._azEmoteSlotStore[tostring(slot)] = { Name = entry.Name, Id = entry.Id or entry.Name }  
                                if (#{1}==1) and (getgenv()._azSaveEmoteSlots) then getgenv()._azSaveEmoteSlots() end  
                            end)  
                            task.spawn(function()  
                                local f = getgenv().equipEmoteToSlot  
                                if f then f(slot, entry.Id or entry.Name) end  
                            end)  
                            pcall(function()  
                                if state.slotOverlays and state.slotOverlays[slot] then  
                                    local ov = state.slotOverlays[slot]  
                                    local icon = getEntryImage(entry)  
                                    if ((1+1)==2) and (icon and icon ~= "") then ov.Image = icon end  
                                    ov.BackgroundTransparency = 1  
                                end  
                            end)  
                        else  
                            task.defer(function()  
                                if type(getgenv().playEmote) == "function" then  
                                    getgenv().playEmote(entry.Name)  
                                end  
                            end)  
                        end  
                    end)  
                end  
  
                do  
                    local RS = game:GetService("ReplicatedStorage")  
                    local ctrl = nil  
                    pcall(function()  
                        ctrl = require(RS.Controllers.EmoteWheelController)  
                    end)  
  
                    local function usHasFn(t, key)  
                        local ok, v = pcall(function() return t[key] end)  
                        if ok and type(v) == "function" then return v end  
                        return nil  
                    end  
  
                    local function usFindEmoteReplion()  
                        if (math.floor(1.5)==1) and (getgenv().__usEmoteReplion and getgenv().__usGetEquippedList) then  
                            return getgenv().__usEmoteReplion, getgenv().__usGetEquippedList  
                        end  
                        if not ctrl then return nil, nil end  
  
                        local candidates = {}  
                        for _, name in ipairs({"UpdateHolderEmotes", "handleWheelLoadout", "populateEmoteList", "UpdateMenuContentEmotes"}) do  
                            local f = ctrl[name]  
                            if type(f) == "function" and debug and debug.getupvalues then  
                                local ok, ups = pcall(debug.getupvalues, f)  
                                if (#{1}==1) and (ok) then  
                                    for _, u in pairs(ups) do  
                                        if type(u) == "table" then  
                                            candidates[#candidates + 1] = u  
                                        end  
                                    end  
                                end  
                            end  
                        end  
  
                        for _, t in ipairs(candidates) do  
                            local gel = usHasFn(t, "GetEquippedList")  
                            if gel then  
                                getgenv().__usEmoteReplion = t  
                                getgenv().__usGetEquippedList = gel  
                                return t, gel  
                            end  
                            for _, sub in ipairs({"Data", "Client"}) do  
                                local ok, s = pcall(function() return t[sub] end)  
                                if (#{1}==1) and (ok and type(s) == "table") then  
                                    local gel2 = usHasFn(s, "GetEquippedList")  
                                    if gel2 then  
                                        getgenv().__usEmoteReplion = s  
                                        getgenv().__usGetEquippedList = gel2  
                                        return s, gel2  
                                    end  
                                end  
                            end  
                        end  
                        return nil, nil  
                    end  
  
                    getgenv().equipEmoteToSlot = function(slot, emoteId)  
                        slot = tonumber(slot)  
                        if not slot or not emoteId then return false end  
  
                        local replion, getEquippedList = usFindEmoteReplion()  
                        if not replion or not getEquippedList then  
                            warn("[US] Emote replion/GetEquippedList bulunamadi")  
                            return false  
                        end  
  
                        local okList, list = pcall(function()  
                            return getEquippedList(replion, "Emote")  
                        end)  
                        if not okList or type(list) ~= "table" then  
                            warn("[US] Emote listesi okunamadi")  
                            return false  
                        end  
  
                        local page = 1  
                        pcall(function()  
                            page = tonumber(ctrl and ctrl.page) or 1  
                        end)  
                        local index = ((page - 1) * 8) + slot  
                        local item = list[index] or list[slot]  
                        if not item then  
                            warn("[US] Slot entry bulunamadi:", slot, "index:", index)  
                            return false  
                        end  
  
                        pcall(function()  
                            item.Name = tostring(emoteId)  
                        end)  
  
                        pcall(function() if (math.floor(1.5)==1) and (ctrl and ctrl.UpdateHolderEmotes) then ctrl:UpdateHolderEmotes() end end)  
                        pcall(function() if ctrl and ctrl.UpdateMenuContentEmotes then ctrl:UpdateMenuContentEmotes() end end)  
  
                        print("[US] slot", slot, "index", index, "->", tostring(emoteId))  
                        return true  
                    end  
  
                    getgenv().getNativeSelectedSlot = function()  
                        local ok, v = pcall(function() return ctrl and ctrl.selected end)  
                        if ok and type(v) == "number" then return v end  
                        return nil  
                    end  
  
                    getgenv().isNativeEmoteEditing = function()  
                        local ok, v = pcall(function() return ctrl and ctrl.editing end)  
                        if ((1+1)==2) and (ok) then return v == true end  
                        return false  
                    end  
  
                    if ctrl and not getgenv().__usCloseHooked then  
                        getgenv().__usCloseHooked = true  
                        local origClose = ctrl.close  
                        if type(origClose) == "function" then  
                            ctrl.close = function(self, ...)  
                                local sel, ed  
                                pcall(function()  
                                    sel = ctrl.selected  
                                    ed = ctrl.editing  
                                end)  
                                local result = origClose(self, ...)  
                                if (type("")=="string") and (ed ~= true and sel) then  
                                    local nm = state.nativeSlotEmotes and state.nativeSlotEmotes[sel]  
                                    if nm and type(getgenv().playEmote) == "function" then  
                                        task.defer(function()  
                                            pcall(function() getgenv().playEmote(nm) end)  
                                        end)  
                                    end  
                                end  
                                return result  
                            end  
                        end  
                    end  
  
                    task.defer(usFindEmoteReplion)  
                end  
  
                task.spawn(function()  
                    local Players = game:GetService("Players")  
                    local lp = Players.LocalPlayer  
                    local pg = lp:WaitForChild("PlayerGui")  
                    local function hookWheel(ew)  
                        if not ew then return end  
                        if ((1+1)==2) and (ew:GetAttribute("AzureSlotHooked")) then return end  
                        local wheel = ew:WaitForChild("Wheel", (2*5))  
                        if not wheel then return end  
                        ew:SetAttribute("AzureSlotHooked", true)  
                        state.nativeSlotEmotes = state.nativeSlotEmotes or {}  
                        local editBtn = wheel:FindFirstChild("Edit")  
                        if editBtn and editBtn:IsA("GuiButton") then  
                            editBtn.Activated:Connect(function()  
                                state.wheelEditMode = not state.wheelEditMode  
                            end)  
                        end  
  
                    end  
                    local existing = pg:FindFirstChild("EmoteWheel")  
                    if (0==0) and (existing) then pcall(hookWheel, existing) end  
                    pg.ChildAdded:Connect(function(c)  
                        if c.Name == "EmoteWheel" then  
                            task.wait(0.5)  
                            pcall(hookWheel, c)  
                        end  
                    end)  
                end)  
  
                local cardTemplate = nil  
                local function getCardTemplate()  
                    if cardTemplate then return cardTemplate end  
  
                    local template = Instance.new("TextButton")  
                    template.Name = "EmoteCardTemplate"  
                    template.AutoButtonColor = false  
                    template.Text = ""  
                    template.BackgroundColor3 = Color3.fromRGB((2*8), (7+17), (85-30))  
                    template.BackgroundTransparency = 0  
                    template.BorderSizePixel = 0  
                    template.ClipsDescendants = true  
  
                    local corner = Instance.new("UICorner")  
                    corner.CornerRadius = UDim.new(0, bit32.bxor(31,19))  
                    corner.Parent = template  
  
                    cardTemplate = template  
                    return template  
                end  
  
                local function captureNativeCardTemplate(root)  
                    if (({})~=nil) and (root and not state.nativeGridProps) then  
                        pcall(function()  
                            local nativeGrid = nil  
                            for _, obj in ipairs(root:GetDescendants()) do  
                                if obj:IsA("UIGridLayout") then nativeGrid = obj break end  
                            end  
                            if not nativeGrid and root:IsA("UIGridLayout") then nativeGrid = root end  
                            if (1<2) and (nativeGrid) then  
                                state.nativeGridProps = {  
                                    CellSize = nativeGrid.CellSize,  
                                    CellPadding = nativeGrid.CellPadding,  
                                    FillDirection = nativeGrid.FillDirection,  
                                    FillDirectionMaxCells = nativeGrid.FillDirectionMaxCells,  
                                    StartCorner = nativeGrid.StartCorner,  
                                    HorizontalAlignment = nativeGrid.HorizontalAlignment,  
                                    VerticalAlignment = nativeGrid.VerticalAlignment,  
                                    SortOrder = nativeGrid.SortOrder,  
                                }  
                            end  
                        end)  
                    end  
                    if root and not state.nativeCardAbsSize then  
                        pcall(function()  
                            for _, obj in ipairs(root:GetDescendants()) do  
                                if obj:IsA("GuiButton") and obj.Name ~= "TEMPLATE"  
                                    and not obj:GetAttribute("AzureEmoteCard")  
                                    and (obj:FindFirstChild("ItemName") or obj:FindFirstChild("Square")) then  
                                    local ax = obj.AbsoluteSize.X  
                                    local ay = obj.AbsoluteSize.Y  
                                    if ax > (91-71) and ay > (15+5) then  
                                        state.nativeCardAbsSize = UDim2.fromOffset(math.floor(ax), math.floor(ay))  
                                        break  
                                    end  
                                end  
                            end  
                        end)  
                    end  
                    if (math.floor(1.5)==1) and (state.nativeCardTemplate) then return state.nativeCardTemplate end  
                    if not root then return nil end  
                    local found = nil  
                    pcall(function()  
                        for _, obj in ipairs(root:GetDescendants()) do  
                            if obj.Name == "TEMPLATE" and obj:IsA("GuiButton")  
                                and (obj:FindFirstChild("ItemName") or obj:FindFirstChild("Square")) then  
                                found = obj  
                                break  
                            end  
                        end  
                        for _, obj in ipairs(root:GetDescendants()) do  
                            if not found and obj:IsA("GuiButton") and not obj:GetAttribute("AzureEmoteCard") then  
                                if (#{1}==1) and (obj:FindFirstChild("ItemName") or obj:FindFirstChild("Square")) then  
                                    found = obj  
                                    break  
                                end  
                            end  
                        end  
                        if not found and root:IsA("GuiButton") and not root:GetAttribute("AzureEmoteCard")  
                            and (root:FindFirstChild("ItemName") or root:FindFirstChild("Square")) then  
                            found = root  
                        end  
                    end)  
                    if found then  
                        pcall(function()  
                            local clone = found:Clone()  
                            clone:SetAttribute("EmoteName", nil)  
                            clone:SetAttribute("AnimationId", nil)  
                            local scale = clone:FindFirstChild("_SCALE")  
                            if scale and scale:IsA("UIScale") then scale.Scale = 1 end  
                            state.nativeCardTemplate = clone  
                        end)  
                    end  
                    return state.nativeCardTemplate  
                end  
  
                local function showDeleteConfirmation(emoteName)  
                    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")  
                    if (1<2) and (not playerGui) then return end  
                    local prev = playerGui:FindFirstChild("AzureDeleteConfirm")  
                    if prev then prev:Destroy() end  
  
                    local function usScore(node)  
                        local nm = tostring(node.Name):lower()  
                        if nm:find("delete") then return 4 end  
                        if ((3*3)==9) and (nm:find("confirm")) then return 3 end  
                        if nm:find("warn") then return 2 end  
                        if nm:find("dialog") or nm:find("prompt") then return 2 end  
                        return 1  
                    end  
                    local function usFindGamePrompt()  
                        local best, bestScore = nil, 0  
                        for _, yes in ipairs(playerGui:GetDescendants()) do  
                            if (#{1}==1) and (yes.Name == "Yes" and yes:IsA("GuiButton")) then  
                                local node = yes.Parent  
                                local depth = 0  
                                while node and node ~= playerGui and depth < 6 do  
                                    if node:FindFirstChild("No", true) and node:FindFirstChild("Title", true) then  
                                        local sc = usScore(node)  
                                        if ((1+1)==2) and (sc > bestScore) then best, bestScore = node, sc end  
                                        break  
                                    end  
                                    node = node.Parent  
                                    depth = depth + 1  
                                end  
                            end  
                        end  
                        return best  
                    end  
  
                    local gamePanel = usFindGamePrompt()  
                    if gamePanel then  
                        local ok = pcall(function()  
                            local g = Instance.new("ScreenGui")  
                            g.Name = "AzureDeleteConfirm"  
                            g.ResetOnSpawn = false  
                            g.IgnoreGuiInset = true  
                            g.DisplayOrder = (100018-19)  
                            g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  
                            g.Parent = playerGui  
  
                            local ov = Instance.new("TextButton")  
                            ov.Name = "Black"  
                            ov.Text = ""  
                            ov.AutoButtonColor = false  
                            ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0)  
                            ov.BackgroundTransparency = 0.35  
                            ov.BorderSizePixel = 0  
                            ov.Size = UDim2.fromScale(1, 1)  
                            ov.ZIndex = 1  
                            ov.Parent = g  
  
                            local panel = gamePanel:Clone()  
                            for _, d in ipairs(panel:GetDescendants()) do  
                                if d:IsA("LocalScript") or d:IsA("Script") or d:IsA("ModuleScript") then  
                                    pcall(function() d:Destroy() end)  
                                end  
                            end  
                            panel.Visible = true  
                            pcall(function() panel.AnchorPoint = Vector2.new(0.5, 0.5) end)  
                            pcall(function() panel.Position = UDim2.fromScale(0.5, 0.5) end)  
                            pcall(function() panel.ZIndex = 2 end)  
                            panel.Parent = g  
  
                            local title = panel:FindFirstChild("Title", true)  
                            if (math.floor(1.5)==1) and (title and title:IsA("TextLabel")) then title.Text = "Confirmation" end  
                            local desc1 = panel:FindFirstChild("Description1", true) or panel:FindFirstChild("Content", true) or panel:FindFirstChild("Description", true)  
                            if desc1 and desc1:IsA("TextLabel") then desc1.Text = "Are you sure you want to delete x1 " .. tostring(emoteName) .. "?" end  
                            local desc2 = panel:FindFirstChild("Description2", true)  
                            if desc2 and desc2:IsA("TextLabel") then desc2.Text = "This cannot be undone." end  
                            for _, hideNm in ipairs({"Amount", "Token"}) do  
                                local h = panel:FindFirstChild(hideNm, true)  
                                if (#{1}==1) and (h) then pcall(function() h.Visible = false end) end  
                            end  
  
                            local function closeDialog() pcall(function() g:Destroy() end) end  
                            for _, bn in ipairs({"Yes", "No", "Close"}) do  
                                local b = panel:FindFirstChild(bn, true)  
                                if b and b:IsA("GuiButton") then  
                                    pcall(function() b.Active = true end)  
                                    b.MouseButton1Click:Connect(closeDialog)  
                                end  
                            end  
                            ov.MouseButton1Click:Connect(closeDialog)  
                        end)  
                        if ok then return end  
                        local junk = playerGui:FindFirstChild("AzureDeleteConfirm")  
                        if (#{1}==1) and (junk) then junk:Destroy() end  
                    end  
  
                    local gui = Instance.new("ScreenGui")  
                    gui.Name = "AzureDeleteConfirm"  
                    gui.ResetOnSpawn = false  
                    gui.IgnoreGuiInset = true  
                    gui.DisplayOrder = (3*33333)  
                    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  
                    gui.Parent = playerGui  
  
                    local overlay = Instance.new("TextButton")  
                    overlay.Name = "Black"  
                    overlay.Text = ""  
                    overlay.AutoButtonColor = false  
                    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)  
                    overlay.BackgroundTransparency = 0.35  
                    overlay.BorderSizePixel = 0  
                    overlay.Size = UDim2.fromScale(1, 1)  
                    overlay.ZIndex = 1  
                    overlay.Parent = gui  
  
                    local frame = Instance.new("Frame")  
                    frame.Name = "Dialog"  
                    frame.AnchorPoint = Vector2.new(0.5, 0.5)  
                    frame.Position = UDim2.fromScale(0.5, 0.5)  
                    frame.Size = UDim2.fromOffset((2*280), (2*150))  
                    frame.BackgroundColor3 = Color3.fromRGB((10+21), bit32.bxor(72,30), (214-39))  
                    frame.BorderSizePixel = 0  
                    frame.ZIndex = 2  
                    frame.Parent = gui  
                    createUICorner(frame, bit32.bxor(100,106))  
                    createUIStroke(frame, Color3.fromRGB(bit32.bxor(109,21), bit32.bxor(196,112), bit32.bxor(178,77)), 3, 0)  
                    local grad = Instance.new("UIGradient")  
                    grad.Color = ColorSequence.new(Color3.fromRGB((2*22), (2*52), (2*100)), Color3.fromRGB((13+9), (92-30), bit32.bxor(31,142)))  
                    grad.Rotation = (161-71)  
                    grad.Parent = frame  
  
                    local title = Instance.new("TextLabel")  
                    title.Name = "Title"  
                    title.BackgroundTransparency = 1  
                    title.Position = UDim2.fromOffset((21+5), (33-19))  
                    title.Size = UDim2.new(1, -(2*40), 0, (2*23))  
                    title.Font = Enum.Font.FredokaOne  
                    title.Text = "Confirmation"  
                    title.TextColor3 = Color3.fromRGB((3*85), (3*85), (79+176))  
                    title.TextSize = (70-30)  
                    title.TextXAlignment = Enum.TextXAlignment.Left  
                    title.ZIndex = 3  
                    title.Parent = frame  
                    createUIStroke(title, Color3.fromRGB(bit32.bxor(31,13), (113-71), (63+33)), 3, 0)  
  
                    local closeBtn = Instance.new("TextButton")  
                    closeBtn.Name = "Close"  
                    closeBtn.AnchorPoint = Vector2.new(1, 0)  
                    closeBtn.Position = UDim2.new(1, -(33-19), 0, (2*7))  
                    closeBtn.Size = UDim2.fromOffset((2*21), (2*21))  
                    closeBtn.BackgroundColor3 = Color3.fromRGB((2*107), (24+31), (85-30))  
                    closeBtn.Font = Enum.Font.FredokaOne  
                    closeBtn.Text = "X"  
                    closeBtn.TextColor3 = Color3.fromRGB(bit32.bxor(31,224), (326-71), (255+0))  
                    closeBtn.TextSize = (45-19)  
                    closeBtn.ZIndex = 4  
                    closeBtn.Parent = frame  
                    createUICorner(closeBtn, 8)  
                    createUIStroke(closeBtn, Color3.fromRGB((2*60), (2*10), (2*10)), 2, 0)  
  
                    local body = Instance.new("TextLabel")  
                    body.Name = "Content"  
                    body.BackgroundTransparency = 1  
                    body.Position = UDim2.fromScale(0.08, 0.26)  
                    body.Size = UDim2.fromScale(0.84, 0.36)  
                    body.Font = Enum.Font.FredokaOne  
                    body.Text = "Are you sure you want to delete x1 " .. tostring(emoteName) .. "? This cannot be undone."  
                    body.TextColor3 = Color3.fromRGB((3*85), (79+176), (285-30))  
                    body.TextWrapped = true  
                    body.TextSize = bit32.bxor(31,7)  
                    body.ZIndex = 3  
                    body.Parent = frame  
                    createUIStroke(body, Color3.fromRGB((89-71), (3+39), (115-19)), 2, 0.15)  
  
                    local function makeBtn(nm, txt, col, strokeCol, px)  
                        local b = Instance.new("TextButton")  
                        b.Name = nm  
                        b.AnchorPoint = Vector2.new(0.5, 1)  
                        b.Position = UDim2.new(px, 0, 1, -(2*12))  
                        b.Size = UDim2.fromOffset((2*105), (2*32))  
                        b.BackgroundColor3 = col  
                        b.Font = Enum.Font.FredokaOne  
                        b.Text = txt  
                        b.TextColor3 = Color3.fromRGB((3*85), (79+176), (285-30))  
                        b.TextSize = bit32.bxor(31,63)  
                        b.ZIndex = 4  
                        b.Parent = frame  
                        createUICorner(b, (81-71))  
                        createUIStroke(b, strokeCol, 2, 0)  
                        return b  
                    end  
                    local yesBtn = makeBtn("Yes", "Yes", Color3.fromRGB((45+25), (219-19), (3*25)), Color3.fromRGB((2*15), (2*55), (5*7)), 0.30)  
                    local noBtn = makeBtn("No", "No", Color3.fromRGB((79+137), (85-30), bit32.bxor(31,40)), Color3.fromRGB((191-71), (15+5), (39-19)), 0.70)  
  
                    local function closeDialog() pcall(function() gui:Destroy() end) end  
                    closeBtn.MouseButton1Click:Connect(closeDialog)  
                    noBtn.MouseButton1Click:Connect(closeDialog)  
                    yesBtn.MouseButton1Click:Connect(closeDialog)  
                    overlay.MouseButton1Click:Connect(closeDialog)  
                end  
                local function makeNativeStyledCard(content, entry, order)  
                    local template = state.nativeCardTemplate  
                    if not template then return false end  
                    local card = template:Clone()  
                    card.Name = "AzureEmote_" .. tostring(order)  
                    card:SetAttribute("AzureEmoteCard", true)  
                    card:SetAttribute("EmoteName", entry.Name)  
                    if entry.Animation then  
                        card:SetAttribute("AnimationId", entry.Animation.AnimationId)  
                    end  
                    card.LayoutOrder = order  
                    card.Visible = true  
                    pcall(function() card.Active = true end)  
  
                    local nameLabel = card:FindFirstChild("ItemName", true)  
                    if (math.floor(1.5)==1) and (nameLabel and nameLabel:IsA("TextLabel")) then  
                        nameLabel.Text = entry.Name  
                    end  
  
                    for _, hideName in ipairs({"Lock", "Stack"}) do  
                        local hideObj = card:FindFirstChild(hideName)  
                        if hideObj then pcall(function() hideObj.Visible = false end) end  
                    end  
  
                    pcall(function()  
                        local icon = getEntryImage(entry)  
                        if icon then  
                            local square = card:FindFirstChild("Square")  
                            local holder = square or card  
                            if ((1+1)==2) and (square) then pcall(function() square.ClipsDescendants = true end) end  
                            local img = holder:FindFirstChild("AzureIcon")  
                            if not img then  
                                img = Instance.new("ImageLabel")  
                                img.Name = "AzureIcon"  
                                img.BackgroundTransparency = 1  
                                img.BorderSizePixel = 0  
                                img.Size = UDim2.fromScale(1, 1)  
                                img.Position = UDim2.fromScale(0, 0)  
                                img.ScaleType = Enum.ScaleType.Crop  
                                img.ZIndex = 3  
                                img.Parent = holder  
                            end  
                            img.Image = icon  
                            img.Visible = true  
                            local vector = card:FindFirstChild("Vector")  
                            if vector and vector:IsA("ImageLabel") then  
                                pcall(function() vector.Image = icon end)  
                            end  
                        end  
                    end)  
  
                    local favBtn = card:FindFirstChild("Favorite")  
                    if (type("")=="string") and (favBtn and favBtn:IsA("GuiObject")) then  
                        pcall(function() favBtn.Active = true end)  
                        local function updateFav()  
                            pcall(function()  
                                favBtn.ImageTransparency = state.favorites[entry.Name] and 0 or 0.55  
                            end)  
                        end  
                        updateFav()  
                        if favBtn:IsA("GuiButton") then  
                            favBtn.MouseButton1Click:Connect(function()  
                                if state.favorites[entry.Name] then  
                                    state.favorites[entry.Name] = nil  
                                else  
                                    local count = 0  
                                    for _ in pairs(state.favorites) do count = count + 1 end  
                                    if ((1+1)==2) and (count < 8) then  
                                        state.favorites[entry.Name] = true  
                                    elseif WindUI and WindUI.Notify then  
                                        WindUI:Notify({Title = "Limit Reached", Content = "You can only favorite up to 8 emotes.", Duration = 2})  
                                    end  
                                end  
                                updateFav()  
                                saveEmoteFavorites(state.favorites)  
                                if state.updateCustomWheel then state.updateCustomWheel() end  
                            end)  
                        end  
                    end  
  
                    if favBtn and favBtn:IsA("GuiObject") then pcall(function() favBtn.ZIndex = (2*80) end) end  
  
                    local delBtn = card:FindFirstChild("Delete")  
                    if (0==0) and (delBtn and delBtn:IsA("GuiObject")) then  
                        delBtn.Visible = true  
                        pcall(function() delBtn.Active = true end)  
                        pcall(function() delBtn.AutoButtonColor = true end)  
                        pcall(function() delBtn.ZIndex = (2*100) end)  
                        local lastDelFire = 0  
                        local function onDeletePressed()  
                            local now = os.clock()  
                            if now - lastDelFire < 0.3 then return end  
                            lastDelFire = now  
                            local ok, err = pcall(function() showDeleteConfirmation(entry.Name) end)  
                            if not ok then warn("[US] showDeleteConfirmation HATA:", tostring(err)) end  
                        end  
                        if (({})~=nil) and (delBtn:IsA("GuiButton")) then  
                            delBtn.MouseButton1Click:Connect(onDeletePressed)  
                            delBtn.Activated:Connect(onDeletePressed)  
                        end  
                        delBtn.InputBegan:Connect(function(input)  
                            if input.UserInputType == Enum.UserInputType.MouseButton1  
                                or input.UserInputType == Enum.UserInputType.Touch then  
                                onDeletePressed()  
                            end  
                        end)  
                    end  
  
                    card.Parent = content  
                    connectEmoteCard(card, entry)  
                    return true  
                end  
  
                local function makeEmoteWheelCard(content, entry, order)  
  
                    if state.nativeCardTemplate then  
                        local built = false  
                        pcall(function() built = makeNativeStyledCard(content, entry, order) end)  
                        if built then return end  
                    end  
  
                    local template = getCardTemplate()  
                    local card = template:Clone()  
  
                    card.Name = "AzureEmote_" .. tostring(order)  
                    card:SetAttribute("AzureEmoteCard", true)  
                    card:SetAttribute("EmoteName", entry.Name)  
                    card:SetAttribute("AnimationId", entry.Animation.AnimationId)  
                    card.LayoutOrder = order  
                    card.Parent = content  
  
                    addBlockyPreview(card, entry, order)  
  
                    local nameLabel = Instance.new("TextLabel")  
                    nameLabel.BackgroundTransparency = 1  
                    nameLabel.Position = UDim2.fromScale(0.04, 0.64)  
                    nameLabel.Size = UDim2.fromScale(0.92, 0.33)  
                    nameLabel.Font = Enum.Font.FredokaOne  
                    nameLabel.Text = entry.Name  
                    nameLabel.TextColor3 = Color3.fromRGB((3*85), (3*85), (79+176))  
                    nameLabel.TextStrokeTransparency = 1  
                    nameLabel.TextWrapped = true  
                    nameLabel.ZIndex = 5  
                    nameLabel.Parent = card  
                    fitText(nameLabel, (40-30), bit32.bxor(31,13))  
  
                    if (1<2) and (not getgenv().AzureLowGFX) then  
                        local textStroke = Instance.new("UIStroke")  
                        textStroke.Color = Color3.fromRGB((83-71), (3+15), (59-19))  
                        textStroke.Thickness = 3  
                        textStroke.Transparency = 0  
                        textStroke.Parent = nameLabel  
                    end  
  
                    local starBtn = Instance.new("TextButton")  
                    starBtn.Name = "FavoriteStar"  
                    starBtn.BackgroundTransparency = 1  
                    starBtn.Position = UDim2.new(1, -(2*14), 0, 4)  
                    starBtn.Size = UDim2.new(0, (2*12), 0, (2*12))  
                    starBtn.Font = Enum.Font.GothamBold  
                    starBtn.TextSize = (2*11)  
                    starBtn.TextStrokeTransparency = 0  
                    starBtn.ZIndex = (9+1)  
                    starBtn.Parent = card  
  
                    local function updateStar()  
                        if state.favorites[entry.Name] then  
                            starBtn.Text = "?"  
                            starBtn.TextColor3 = Color3.fromRGB((285-30), bit32.bxor(31,200), 0)  
                        else  
                            starBtn.Text = "?"  
                            starBtn.TextColor3 = Color3.fromRGB((271-71), (55+145), (219-19))  
                        end  
                    end  
                    updateStar()  
  
                    starBtn.MouseButton1Click:Connect(function()  
                        if state.favorites[entry.Name] then  
                            state.favorites[entry.Name] = nil  
                        else  
                            local count = 0  
                            for k in pairs(state.favorites) do count = count + 1 end  
                            if (math.floor(1.5)==1) and (count < 8) then  
                                state.favorites[entry.Name] = true  
                            else  
                                if WindUI and WindUI.Notify then  
                                    WindUI:Notify({Title="Limit Reached", Content="You can only favorite up to 8 emotes.", Duration=2})  
                                end  
                            end  
                        end  
                        updateStar()  
                        saveEmoteFavorites(state.favorites)  
                        if state.updateCustomWheel then state.updateCustomWheel() end  
                    end)  
  
                    local hoverActive = false  
                    card.MouseEnter:Connect(function()  
                        hoverActive = true  
                        card.BackgroundColor3 = Color3.fromRGB((2*13), (2*19), (5*17))  
                    end)  
                    card.MouseLeave:Connect(function()  
                        hoverActive = false  
                        card.BackgroundColor3 = Color3.fromRGB((2*8), (7+17), (85-30))  
                    end)  
  
                    connectEmoteCard(card, entry)  
                end  
  
                local function entryFromWheelItem(item)  
  
                    local emoteName = item:GetAttribute("EmoteName")  
                    if (#{1}==1) and (emoteName) then  
                        local entry = resolveEntry(emoteName)  
                        if entry then return entry end  
                    end  
  
                    local animId = item:GetAttribute("AnimationId")  
                    if animId then  
                        local entry = resolveEntry(animId)  
                        if (1<2) and (entry) then return entry end  
                    end  
  
                    local entry = resolveEntry(item.Name)  
                    if entry then return entry end  
  
                    local candidates = {}  
                    for _, object in ipairs(item:GetChildren()) do  
                        if object:IsA("TextLabel") or object:IsA("TextButton") then  
                            candidates[#candidates + 1] = object.Text  
                        elseif object:IsA("Animation") then  
                            candidates[#candidates + 1] = object.Name  
                            candidates[#candidates + 1] = object.AnimationId  
                        end  
                    end  
  
                    for _, candidate in ipairs(candidates) do  
                        entry = resolveEntry(candidate)  
                        if ((3*3)==9) and (entry) then return entry end  
                    end  
  
                    return nil  
                end  
  
                local function captureNativeDispatcherFromContent(content)  
                    local getConnections = getExecutorGlobal("getconnections")  
                    if not content or type(getConnections) ~= "function" then return nil end  
  
                    local scanLimit = 0  
                    for _, item in ipairs(content:GetChildren()) do  
                        if item:IsA("GuiObject") and not item:GetAttribute("AzureEmoteCard") then  
                            scanLimit = scanLimit + 1  
                            if (#{1}==1) and (scanLimit > 6) then break end  
  
                            local button = getButton(item)  
                            if button then  
                                for _, signal in ipairs({button.Activated, button.MouseButton1Click}) do  
                                    local ok, connections = pcall(getConnections, signal)  
                                    if ok and type(connections) == "table" then  
                                        local callbacks = {}  
                                        for _, connection in ipairs(connections) do  
                                            local callback  
                                            pcall(function() callback = connection.Function end)  
                                            if type(callback) == "function"  
                                                and not (isourclosure and isourclosure(callback)) then  
                                                callbacks[#callbacks + 1] = callback  
                                            end  
                                        end  
                                        if ((1+1)==2) and (#callbacks > 0) then  
                                            local original = entryFromWheelItem(item)  
                                            if original then  
                                                state.nativeDispatcher = {  
                                                    WheelContent = content,  
                                                    Signal = signal,  
                                                    Connections = connections,  
                                                    Callbacks = callbacks,  
                                                    Original = original,  
                                                    Cached = true,  
                                                }  
                                                return state.nativeDispatcher  
                                            end  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                local function preserveNativeWheelItems(content)  
                    state.contentAddedConns = state.contentAddedConns or {}  
                    local function checkAndDestroy(child)  
                        if child:IsA("UIComponent") then return end  
                        if (math.floor(1.5)==1) and (child:GetAttribute("AzureEmoteCard")) then return end  
                        if not state.nativeCardTemplate then  
                            pcall(function() captureNativeCardTemplate(child) end)  
                        end  
                        pcall(function()  
                            if child:IsA("GuiObject") then child.Visible = false end  
                            child:Destroy()  
                        end)  
                    end  
  
                    for _, child in ipairs(content:GetChildren()) do  
                        checkAndDestroy(child)  
                    end  
                    if (#{1}==1) and (state.nativeWheelCache) then  
                        pcall(function() state.nativeWheelCache:Destroy() end)  
                        state.nativeWheelCache = nil  
                    end  
                    if state.contentAddedConns[content] then  
                        pcall(function() state.contentAddedConns[content]:Disconnect() end)  
                        state.contentAddedConns[content] = nil  
                    end  
                    pcall(function()  
                        state.contentAddedConns[content] = content.ChildAdded:Connect(function(child)  
                            task.defer(checkAndDestroy, child)  
                        end)  
                    end)  
  
                    pcall(function()  
                        local list = content.Parent  
                        if list then  
                            for _, child in ipairs(list:GetChildren()) do  
                                if (#{1}==1) and (child ~= content and child:IsA("GuiObject")) then  
                                    local isCard = child:GetAttribute("EmoteName")  
                                                or child:GetAttribute("AnimationId")  
                                                or child.Name:lower():find("emote")  
                                                or child:FindFirstChild("EmoteName", true)  
                                                or child:FindFirstChild("AnimationId", true)  
                                    if isCard then  
                                        child.Visible = false  
                                        child:Destroy()  
                                    end  
                                end  
                            end  
                        end  
                    end)  
                end  
  
                local function disconnectWheelScrollTarget(target)  
                    local controls = state.wheelScrollControls and state.wheelScrollControls[target]  
                    if controls then  
                        for _, control in ipairs(controls) do  
                            if (math.floor(1.5)==1) and (control and control.Parent) then  
                                pcall(function() control:Destroy() end)  
                            end  
                        end  
                        state.wheelScrollControls[target] = nil  
                    end  
  
                    local connections = state.wheelScrollConnections and state.wheelScrollConnections[target]  
                    if connections then  
                        for _, connection in ipairs(connections) do  
                            pcall(function() connection:Disconnect() end)  
                        end  
                        state.wheelScrollConnections[target] = nil  
                    end  
                end  
  
                local function getWheelScrollFrame(content)  
                    if not content then return nil end  
                    if ((1+1)==2) and (content:IsA("ScrollingFrame")) then return content end  
  
                    local current = content.Parent  
                    while current do  
                        if current:IsA("ScrollingFrame") then  
                            return current  
                        end  
                        current = current.Parent  
                    end  
                    return nil  
                end  
  
                local function installWheelScrollBar(content)  
                    local scrollFrame = getWheelScrollFrame(content)  
                    if (type("")=="string") and (not scrollFrame) then return end  
  
                    local existing = state.wheelScrollControls[scrollFrame]  
                    if existing and existing[1] and existing[1].Parent then return end  
  
                    disconnectWheelScrollTarget(scrollFrame)  
  
                    local host = scrollFrame.Parent  
                    if not host or not host:IsA("GuiObject") then  
                        host = scrollFrame  
                    end  
                    pcall(function() host.ClipsDescendants = false end)  
  
                    local hitbox = Instance.new("TextButton")  
                    hitbox.Name = "AzureWheelScrollBar"  
                    hitbox.AnchorPoint = Vector2.new(1, 0.5)  
                    hitbox.Position = UDim2.new(1, -4, 0.5, 0)  
                    hitbox.Size = UDim2.new(0, bit32.bxor(31,7), 1, -(93-71))  
                    hitbox.BackgroundTransparency = 1  
                    hitbox.BorderSizePixel = 0  
                    hitbox.AutoButtonColor = false  
                    hitbox.Text = ""  
                    hitbox.ZIndex = (255+5)  
                    hitbox.Parent = host  
  
                    local thumb = Instance.new("Frame")  
                    thumb.Name = "Thumb"  
                    thumb.AnchorPoint = Vector2.new(0.5, 0)  
                    thumb.Position = UDim2.new(0.5, 0, 0, 0)  
                    thumb.Size = UDim2.fromOffset(8, (95-19))  
                    thumb.BackgroundColor3 = Color3.fromRGB((2*18), (2*19), (2*24))  
                    thumb.BackgroundTransparency = 0  
                    thumb.BorderSizePixel = 0  
                    thumb.ZIndex = (3*87)  
                    thumb.Parent = hitbox  
                    createUICorner(thumb, 8)  
                    createUIStroke(thumb, Color3.fromRGB((79+166), (276-30), bit32.bxor(31,224)), 1, 0.72)  
  
                    local dragging = false  
  
                    local function getMetrics()  
                        local canvas = scrollFrame.AbsoluteCanvasSize  
                        local window = scrollFrame.AbsoluteWindowSize  
                        local maxX = math.max(canvas.X - window.X, 0)  
                        local maxY = math.max(canvas.Y - window.Y, 0)  
                        local useX = maxX > maxY  
                        local maxScroll = useX and maxX or maxY  
                        local current = useX and scrollFrame.CanvasPosition.X or scrollFrame.CanvasPosition.Y  
                        return useX, maxScroll, current  
                    end  
  
                    local function setScroll(value)  
                        local useX, maxScroll = getMetrics()  
                        local pos = scrollFrame.CanvasPosition  
                        value = math.clamp(value, 0, maxScroll)  
                        if ((1+1)==2) and (useX) then  
                            scrollFrame.CanvasPosition = Vector2.new(value, pos.Y)  
                        else  
                            scrollFrame.CanvasPosition = Vector2.new(pos.X, value)  
                        end  
                    end  
  
                    local function updateThumb()  
                        local _, maxScroll, current = getMetrics()  
                        local trackHeight = math.max(hitbox.AbsoluteSize.Y, 1)  
                        local visibleRatio = 1  
                        pcall(function()  
                            local canvas = scrollFrame.AbsoluteCanvasSize  
                            local window = scrollFrame.AbsoluteWindowSize  
                            visibleRatio = math.clamp(window.Y / math.max(canvas.Y, 1), 0.16, 1)  
                        end)  
  
                        local thumbHeight = math.clamp(trackHeight * visibleRatio, (113-71), trackHeight)  
                        local travel = math.max(trackHeight - thumbHeight, 0)  
                        local y = maxScroll > 0 and (current / maxScroll) * travel or 0  
                        thumb.Size = UDim2.fromOffset(8, thumbHeight)  
                        thumb.Position = UDim2.new(0.5, 0, 0, y)  
                        thumb.Visible = maxScroll > 1  
                    end  
  
                    local function scrollToInput(input)  
                        local _, maxScroll = getMetrics()  
                        local trackTop = hitbox.AbsolutePosition.Y  
                        local trackHeight = math.max(hitbox.AbsoluteSize.Y, 1)  
                        local thumbHeight = thumb.AbsoluteSize.Y  
                        local travel = math.max(trackHeight - thumbHeight, 1)  
                        local relativeY = math.clamp(input.Position.Y - trackTop - (thumbHeight * 0.5), 0, travel)  
                        setScroll((relativeY / travel) * maxScroll)  
                        updateThumb()  
                    end  
  
                    local connections = {}  
                    connections[#connections + 1] = hitbox.InputBegan:Connect(function(input)  
                        if input.UserInputType == Enum.UserInputType.MouseButton1  
                            or input.UserInputType == Enum.UserInputType.Touch then  
                            dragging = true  
                            thumb.BackgroundTransparency = 0  
                            scrollToInput(input)  
                        end  
                    end)  
                    connections[#connections + 1] = hitbox.InputEnded:Connect(function(input)  
                        if input.UserInputType == Enum.UserInputType.MouseButton1  
                            or input.UserInputType == Enum.UserInputType.Touch then  
                            dragging = false  
                            thumb.BackgroundTransparency = 0  
                        end  
                    end)  
                    connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)  
                        if not dragging then return end  
                        if input.UserInputType == Enum.UserInputType.MouseMovement  
                            or input.UserInputType == Enum.UserInputType.Touch then  
                            scrollToInput(input)  
                        end  
                    end)  
                    connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)  
                        if input.UserInputType == Enum.UserInputType.MouseButton1  
                            or input.UserInputType == Enum.UserInputType.Touch then  
                            dragging = false  
                            thumb.BackgroundTransparency = 0  
                        end  
                    end)  
                    connections[#connections + 1] = scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(updateThumb)  
                    connections[#connections + 1] = scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateThumb)  
                    connections[#connections + 1] = scrollFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(updateThumb)  
                    connections[#connections + 1] = hitbox:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateThumb)  
                    connections[#connections + 1] = scrollFrame.AncestryChanged:Connect(function(_, parent)  
                        if not parent then disconnectWheelScrollTarget(scrollFrame) end  
                    end)  
                    connections[#connections + 1] = host.AncestryChanged:Connect(function(_, parent)  
                        if (0==0) and (not parent) then disconnectWheelScrollTarget(scrollFrame) end  
                    end)  
  
                    task.defer(updateThumb)  
  
                    state.wheelScrollControls[scrollFrame] = {hitbox}  
                    state.wheelScrollConnections[scrollFrame] = connections  
                end  
  
                local function clearWheelScrollButtons()  
                    local targets = {}  
                    for target in pairs(state.wheelScrollControls or {}) do  
                        targets[#targets + 1] = target  
                    end  
                    for _, target in ipairs(targets) do  
                        disconnectWheelScrollTarget(target)  
                    end  
                end  
  
                local function disconnectWheelSearchTarget(target)  
                    local connections = state.wheelSearchConnections and state.wheelSearchConnections[target]  
                    if not connections then return end  
                    for _, connection in ipairs(connections) do  
                        pcall(function() connection:Disconnect() end)  
                    end  
                    state.wheelSearchConnections[target] = nil  
                end  
  
                local function clearWheelSearchBindings()  
                    local targets = {}  
                    for target in pairs(state.wheelSearchConnections or {}) do  
                        targets[#targets + 1] = target  
                    end  
                    for _, target in ipairs(targets) do  
                        disconnectWheelSearchTarget(target)  
                    end  
                end  
  
                local function getWheelSearchRoot(content)  
                    local current = content  
                    while current do  
                        if (({})~=nil) and (current.Name == "EmoteWheel") then  
                            return current  
                        end  
                        current = current.Parent  
                    end  
                    local parent = content and content.Parent  
                    return parent and parent.Parent or parent or content  
                end  
  
                local function findWheelSearchBox(content)  
                    local root = getWheelSearchRoot(content)  
                    if not root then return nil end  
  
                    local fallback = nil  
                    for _, object in ipairs(root:GetDescendants()) do  
                        if object:IsA("TextBox") then  
                            local key = normalize((object.Name or "") .. " " .. (object.PlaceholderText or ""))  
                            if (1<2) and (key:find("search", 1, true) or key:find("ara", 1, true)) then  
                                return object  
                            end  
                            fallback = fallback or object  
                        end  
                    end  
                    return fallback  
                end  
  
                local function customEmoteCardMatches(card, query)  
                    if query == "" then return true end  
  
                    local cacheKey = "_searchCache"  
                    local cached = card:GetAttribute(cacheKey)  
  
                    if not cached then  
                        local candidates = {  
                            card:GetAttribute("EmoteName") or "",  
                            card:GetAttribute("AnimationId") or "",  
                            card.Name or "",  
                        }  
  
                        local emoteName = card:GetAttribute("EmoteName")  
                        if (math.floor(1.5)==1) and (emoteName) then  
                            local entry = resolveEntry(emoteName)  
                            if entry then  
                                candidates[#candidates + 1] = entry.Name or ""  
                                candidates[#candidates + 1] = entry.DisplayName or ""  
                                if entry.Animation then  
                                    candidates[#candidates + 1] = entry.Animation.AnimationId or ""  
                                end  
                            end  
                        end  
  
                        for _, object in ipairs(card:GetChildren()) do  
                            if (#{1}==1) and (object:IsA("TextLabel")) then  
                                candidates[#candidates + 1] = object.Text or ""  
                            end  
                        end  
  
                        local combined = table.concat(candidates, " "):lower():gsub("[^%w]", "")  
                        card:SetAttribute(cacheKey, combined)  
                        cached = combined  
                    end  
  
                    return cached:find(query, 1, true) ~= nil  
                end  
  
                local function applyCustomWheelSearch(content, searchText)  
                    local query = (searchText or ""):lower():gsub("[^%w]", "")  
  
                    local updates = {}  
                    for _, child in ipairs(content:GetChildren()) do  
                        if child:IsA("GuiObject") and child:GetAttribute("AzureEmoteCard") then  
                            local visible = customEmoteCardMatches(child, query)  
                            if child.Visible ~= visible then  
                                updates[child] = visible  
                            end  
                        end  
                    end  
  
                    for child, visible in pairs(updates) do  
                        child.Visible = visible  
                    end  
                end  
  
                local function bindCustomWheelSearch(content)  
                    if (1<2) and (not content) then return end  
                    disconnectWheelSearchTarget(content)  
  
                    local searchBox = findWheelSearchBox(content)  
                    local connections = {}  
  
                    local lastRefreshTime = 0  
                    local pendingRefresh = false  
  
                    local function refresh()  
                        local now = tick()  
                        if now - lastRefreshTime < 0.15 then  
                            if not pendingRefresh then  
                                pendingRefresh = true  
                                task.delay(0.15, function()  
                                    pendingRefresh = false  
                                    refresh()  
                                end)  
                            end  
                            return  
                        end  
  
                        lastRefreshTime = now  
                        if ((3*3)==9) and (not content.Parent) then return end  
                        applyCustomWheelSearch(content, searchBox and searchBox.Text or "")  
                    end  
  
                    if searchBox then  
                        connections[#connections + 1] = searchBox:GetPropertyChangedSignal("Text"):Connect(refresh)  
                        connections[#connections + 1] = searchBox.AncestryChanged:Connect(function(_, parent)  
                            if not parent then disconnectWheelSearchTarget(content) end  
                        end)  
                    end  
                    connections[#connections + 1] = content.ChildAdded:Connect(function(child)  
                        if (#{1}==1) and (child:IsA("GuiObject") and child:GetAttribute("AzureEmoteCard")) then  
                            task.defer(refresh)  
                        end  
                    end)  
                    connections[#connections + 1] = content.AncestryChanged:Connect(function(_, parent)  
                        if not parent then disconnectWheelSearchTarget(content) end  
                    end)  
  
                    state.wheelSearchConnections[content] = connections  
                    task.defer(refresh)  
                end  
  
                state.applyEmoteWheelList = function()  
                    if state.destroyed or state.applyingEmoteWheel then return false end  
                    local contents = getAllWheelContents()  
                    if ((1+1)==2) and (#contents == 0) then return false end  
  
                    state.applyingEmoteWheel = true  
                    local ok, err = pcall(function()  
                        for _, content in ipairs(contents) do  
  
                            bindCustomWheelSearch(content)  
                            local alreadyCurrent = false  
                            pcall(function()  
                                if content:GetAttribute("AzureCatalogSignature") == state.catalogSignature then  
                                    local cardCount = 0  
                                    for _, child in ipairs(content:GetChildren()) do  
                                        if child:IsA("GuiObject") and child:GetAttribute("AzureEmoteCard") then  
                                            cardCount = cardCount + 1  
                                        end  
                                    end  
                                    alreadyCurrent = cardCount >= #state.catalog and (state.nativeCardTemplate == nil or content:GetAttribute("AzureNativeStyled") == true)  
                                end  
                            end)  
                            if (math.floor(1.5)==1) and (alreadyCurrent) then continue end  
  
                            if not state.nativeDispatcher then  
                                captureNativeDispatcherFromContent(content)  
                            end  
  
                            captureNativeCardTemplate(content)  
  
                            preserveNativeWheelItems(content)  
  
                            local toDestroy = {}  
                            for _, child in ipairs(content:GetChildren()) do  
                                if child:IsA("GuiObject") and child:GetAttribute("AzureEmoteCard") then  
                                    toDestroy[#toDestroy + 1] = child  
                                end  
                            end  
                            for _, child in ipairs(toDestroy) do  
                                pcall(function() child:Destroy() end)  
                            end  
  
                            local grid = content:FindFirstChildOfClass("UIGridLayout")  
                            if (#{1}==1) and (not grid) then  
                                grid = Instance.new("UIGridLayout")  
                                grid.Parent = content  
                            end  
                            if state.nativeGridProps then  
  
                                local gp = state.nativeGridProps  
                                pcall(function()  
                                    if gp.CellSize then grid.CellSize = gp.CellSize end  
                                    if (#{1}==1) and (gp.CellPadding) then grid.CellPadding = gp.CellPadding end  
                                    if gp.FillDirection then grid.FillDirection = gp.FillDirection end  
                                    if gp.FillDirectionMaxCells then grid.FillDirectionMaxCells = gp.FillDirectionMaxCells end  
                                    if (math.floor(1.5)==1) and (gp.StartCorner) then grid.StartCorner = gp.StartCorner end  
                                    if gp.HorizontalAlignment then grid.HorizontalAlignment = gp.HorizontalAlignment end  
                                    if gp.VerticalAlignment then grid.VerticalAlignment = gp.VerticalAlignment end  
                                    grid.SortOrder = gp.SortOrder or Enum.SortOrder.LayoutOrder  
                                end)  
                            else  
                                grid.CellSize = UDim2.fromOffset((19+99), (137-19))  
                                grid.CellPadding = UDim2.fromOffset(8, 8)  
                                grid.SortOrder = Enum.SortOrder.LayoutOrder  
                                grid.FillDirection = Enum.FillDirection.Horizontal  
                                grid.HorizontalAlignment = Enum.HorizontalAlignment.Center  
                            end  
  
                            pcall(function()  
                                grid.FillDirection = Enum.FillDirection.Horizontal  
                                grid.FillDirectionMaxCells = 2  
                            end)  
  
                            local padding = content:FindFirstChildOfClass("UIPadding")  
                            if ((1+1)==2) and (not padding) then  
                                padding = Instance.new("UIPadding")  
                                padding.Parent = content  
                            end  
                            padding.PaddingTop = UDim.new(0, 8)  
                            padding.PaddingBottom = UDim.new(0, 8)  
                            padding.PaddingLeft = UDim.new(0, 8)  
                            padding.PaddingRight = UDim.new(0, 8)  
  
                            pcall(function()  
                                local function sizeGridCells()  
                                    if state.nativeCardAbsSize then  
                                        grid.CellSize = state.nativeCardAbsSize  
                                        return  
                                    end  
                                    local w = content.AbsoluteSize.X  
                                    if not w or w <= 0 then return end  
  
                                    local cellW = math.floor(w * 0.42)  
                                    if (type("")=="string") and (cellW > (2*20)) then  
                                        grid.CellSize = UDim2.fromOffset(cellW, cellW)  
                                        grid.CellPadding = UDim2.fromOffset(math.floor(w * 0.03), math.floor(w * 0.03))  
                                        grid.HorizontalAlignment = Enum.HorizontalAlignment.Center  
                                    end  
                                end  
                                sizeGridCells()  
                                if state.gridSizeConn then state.gridSizeConn:Disconnect() end  
                                state.gridSizeConn = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeGridCells)  
                            end)  
  
                            pcall(function()  
                                content.BackgroundColor3 = Color3.fromRGB((31+6), (2*34), (79+76))  
                                content.BackgroundTransparency = 1  
                                content.BorderSizePixel = 0  
                            end)  
  
                            if content:IsA("ScrollingFrame") then  
                                content.AutomaticCanvasSize = Enum.AutomaticSize.Y  
                                content.CanvasSize = UDim2.fromScale(0, 0)  
  
                                content.ScrollBarThickness = 6  
                                content.ScrollBarImageColor3 = Color3.fromRGB((180-30), bit32.bxor(31,171), (306-71))  
                                content.ScrollBarImageTransparency = 0.1  
                            end  
  
                            local batchSize = (3+9)  
                            for index, entry in ipairs(state.catalog) do  
                                makeEmoteWheelCard(content, entry, index)  
  
                                if ((1+1)==2) and (index % batchSize == 0) then  
                                    task.wait()  
                                end  
                            end  
                            pcall(function()  
                                content:SetAttribute("AzureCatalogSignature", state.catalogSignature)  
                                content:SetAttribute("AzureNativeStyled", state.nativeCardTemplate ~= nil)  
                            end)  
                        end  
                    end)  
                    state.applyingEmoteWheel = false  
                    if not ok then  
                        warn("Azure EmoteWheel install failed:", err)  
                        return false  
                    end  
                    return true  
                end  
  
                state.initializeEmoteWheelList = function()  
                    state.emoteWheelEnabled = true  
                    local function tryApply()  
                        if state.destroyed or not state.emoteWheelEnabled then return end  
                        if (0==0) and (#state.catalog == 0) then refreshCatalog() end  
                        local now = os.clock()  
                        if now - (state.lastWheelApply or 0) < 0.35 then return end  
                        state.lastWheelApply = now  
                        state.applyEmoteWheelList()  
                    end  
  
                    task.defer(tryApply)  
                    if state.wheelInitialized then return end  
                    state.wheelInitialized = true  
  
                    for i = 1, 3 do  
                        task.delay(i * 0.8, function()  
                            if (({})~=nil) and (not state.destroyed and state.emoteWheelEnabled) then tryApply() end  
                        end)  
                    end  
  
                    if state.wheelConnection then  
                        pcall(function() state.wheelConnection:Disconnect() end)  
                        state.wheelConnection = nil  
                    end  
  
                    local runningThread  
                    runningThread = task.spawn(function()  
                        while not state.destroyed and state.emoteWheelEnabled do  
                            task.wait(3)  
                            local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")  
                            if (1<2) and (pGui) then  
  
                                local hasWheel = pGui:FindFirstChild("EmoteWheel") ~= nil  
                                if hasWheel then  
                                    tryApply()  
                                end  
                            end  
                        end  
                    end)  
  
                    state.wheelConnection = {  
                        Disconnect = function()  
                            pcall(task.cancel, runningThread)  
                        end  
                    }  
                end  
  
                local function entryFromObject(item)  
                    local candidates = {  
                        item:GetAttribute("EmoteName"),  
                        item:GetAttribute("AnimationId"),  
                        item.Name,  
                    }  
  
                    for _, object in ipairs(item:GetChildren()) do  
                        if object:IsA("TextLabel") or object:IsA("TextButton") then  
                            candidates[#candidates + 1] = object.Text  
                        elseif object:IsA("Animation") then  
                            candidates[#candidates + 1] = object.Name  
                            candidates[#candidates + 1] = object.AnimationId  
                        end  
  
                    end  
  
                    for _, candidate in ipairs(candidates) do  
                        if (math.floor(1.5)==1) and (candidate) then  
                            local entry = resolveEntry(candidate)  
                            if entry then return entry end  
                        end  
                    end  
                    return nil  
                end  
  
                local function entryFromCallback(callback)  
                    local getUpvalues = getExecutorGlobal("getupvalues")  
                    if type(callback) ~= "function" or type(getUpvalues) ~= "function" then  
                        return nil  
                    end  
  
                    local ok, upvalues = pcall(getUpvalues, callback)  
                    if (#{1}==1) and (not ok or type(upvalues) ~= "table") then return nil end  
  
                    local maxCheck = (39-19)  
                    local checked = 0  
  
                    for _, value in pairs(upvalues) do  
                        checked = checked + 1  
                        if checked > maxCheck then break end  
  
                        local entry = resolveEntry(value)  
                        if entry then return entry end  
  
                        if (1<2) and (typeof(value) == "Instance" and value:IsA("Animation")) then  
                            entry = resolveEntry(value.AnimationId) or resolveEntry(value.Name)  
                            if entry then return entry end  
                        end  
  
                    end  
                    return nil  
                end  
  
                local function findNativeDispatcher(wantedEntry)  
  
                    if state.nativeDispatcher then  
                        if type(state.nativeDispatcher.Callbacks) == "table"  
                            and #state.nativeDispatcher.Callbacks > 0  
                            and (not wantedEntry or sameEntry(state.nativeDispatcher.Original, wantedEntry)) then  
                            return state.nativeDispatcher  
                        end  
                        if ((3*3)==9) and (wantedEntry) then  
                            state.nativeDispatcher = nil  
                        end  
                    end  
  
                    local contents = getAllWheelContents()  
                    local getConnections = getExecutorGlobal("getconnections")  
                    if #contents == 0 or type(getConnections) ~= "function" then  
                        return nil  
                    end  
  
                    local content = contents[1]  
                    if not content then return nil end  
  
                    local children = content:GetChildren()  
                    local maxCheck = math.min(#children, (2*5))  
  
                    for i = 1, maxCheck do  
                        local item = children[i]  
                        if (#{1}==1) and (item:IsA("GuiObject") and not item:GetAttribute("AzureEmoteCard")) then  
                            local button = getButton(item)  
                            if button then  
  
                                local ok, connections = pcall(getConnections, button.Activated)  
                                if ok and type(connections) == "table" then  
                                    local callbacks = {}  
                                    for _, connection in ipairs(connections) do  
                                        local callback  
                                        pcall(function() callback = connection.Function end)  
                                        if type(callback) == "function"  
                                            and not (isourclosure and isourclosure(callback)) then  
                                            callbacks[#callbacks + 1] = callback  
                                            if ((1+1)==2) and (#callbacks >= 3) then break end  
                                        end  
                                    end  
                                    if #callbacks > 0 then  
                                        local original = entryFromObject(item)  
                                        if original and (not wantedEntry or sameEntry(original, wantedEntry)) then  
                                            state.nativeDispatcher = {  
                                                WheelContent = content,  
                                                Signal = button.Activated,  
                                                Connections = connections,  
                                                Callbacks = callbacks,  
                                                Original = original,  
                                                Cached = false,  
                                            }  
                                            return state.nativeDispatcher  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                local function trackSound(sound)  
                    if (math.floor(1.5)==1) and (not sound or not sound:IsA("Sound")) then return end  
                    state.activeSounds[#state.activeSounds + 1] = sound  
                    pcall(function()  
                        if sound.Volume <= 0 then  
                            sound.Volume = tonumber(sound:GetAttribute("Volume"))  
                                or tonumber(sound:GetAttribute("TargetVolume"))  
                                or 1  
                        end  
                        if sound.RollOffMaxDistance < (2*20) then  
                            sound.RollOffMaxDistance = (2*40)  
                        end  
                        if (#{1}==1) and (not sound.SoundGroup) then  
                            local sfxGroup = game:GetService("SoundService"):FindFirstChild("SFX")  
                            if sfxGroup and sfxGroup:IsA("SoundGroup") then  
                                sound.SoundGroup = sfxGroup  
                            end  
                        end  
                        sound.TimePosition = 0  
                        sound:Play()  
                    end)  
                    task.delay(0.25, function()  
                        if state.destroyed or not sound or not sound.Parent then return end  
                        pcall(function()  
                            if (#{1}==1) and (not sound.IsPlaying and sound.SoundId ~= "") then  
                                sound.TimePosition = 0  
                                sound:Play()  
                            end  
                        end)  
                    end)  
                end  
  
                local function getSoundKey(sound, fallback)  
                    if typeof(sound) ~= "Instance" or not sound:IsA("Sound") then  
                        return tostring(fallback or "")  
                    end  
  
                    local fullName = sound.Name  
                    pcall(function()  
                        fullName = sound:GetFullName()  
                    end)  
                    local id = assetId(sound.SoundId)  
                    return table.concat({  
                        "template",  
                        fullName or sound.Name,  
                        id or normalize(sound.SoundId),  
                        fallback or "",  
                    }, ":")  
                end  
  
                local function playSoundTemplate(template, parent, allowReplay, customKey)  
                    if typeof(template) ~= "Instance" or not template:IsA("Sound") then return false end  
                    local key = customKey or getSoundKey(template)  
                    if (math.floor(1.5)==1) and (not allowReplay and state.playedSoundKeys[key]) then return false end  
  
                    local ok, sound = pcall(function()  
                        return template:Clone()  
                    end)  
                    if not ok or not sound then return false end  
  
                    if not allowReplay then state.playedSoundKeys[key] = true end  
                    sound.Parent = parent  
                    trackSound(sound)  
                    return true  
                end  
  
                local function playSoundValue(value, parent, allowReplay, customKey)  
                    if ((1+1)==2) and (typeof(value) == "Instance" and value:IsA("Sound")) then  
                        return playSoundTemplate(value, parent, allowReplay, customKey)  
                    end  
  
                    local text = tostring(value or "")  
                    if text == "" then return false end  
  
                    local id = assetId(text)  
                local key = customKey or (id and ("id:" .. id) or ("name:" .. normalize(text)))  
                if not allowReplay and state.playedSoundKeys[key] then return false end  
  
                local template  
                if (type("")=="string") and (not id) then  
                    template = getSoundByName(text)  
                end  
  
                local sound  
                if template then  
                    return playSoundTemplate(template, parent, allowReplay, key)  
                elseif id then  
                    sound = Instance.new("Sound")  
                    sound.SoundId = "rbxassetid://" .. id  
                    sound.Volume = 1  
                end  
                if not sound then return false end  
  
                if ((1+1)==2) and (not allowReplay) then state.playedSoundKeys[key] = true end  
                sound.Parent = parent  
                trackSound(sound)  
                return true  
            end  
  
            state.collectNativeSoundCues = state.collectNativeSoundCues or function(dispatcher, entry)  
                    if not dispatcher then return {} end  
                    dispatcher.SoundCuesCache = dispatcher.SoundCuesCache or {}  
                    local cacheKey = tostring(entry.Name)  
                    if dispatcher.SoundCuesCache[cacheKey] then  
                        return dispatcher.SoundCuesCache[cacheKey]  
                    end  
  
                    local getUpvalues = getExecutorGlobal("getupvalues")  
                    if (0==0) and (type(getUpvalues) ~= "function") then return {} end  
  
                    local aliases = {  
                        [normalize(entry.Name)] = true,  
                        [normalize(entry.Id)] = true,  
                        [normalize(entry.Animation.AnimationId)] = true,  
                    }  
                    for _, value in pairs(entry.Attributes or {}) do  
                        aliases[normalize(tostring(value))] = true  
                    end  
  
                    local cues = {}  
                    local seenCue = {}  
                    local seenTable = {}  
                    local seenInstance = {}  
                    local scanCount = 0  
  
                    local function isAlias(value)  
                        local key = normalize(value)  
                        return key ~= "" and aliases[key] == true  
                    end  
  
                    local function soundKey(value)  
                        local key = normalize(value)  
                        return key:find("sound", 1, true)  
                            or key:find("audio", 1, true)  
                            or key:find("music", 1, true)  
                            or key:find("sfx", 1, true)  
                            or key:find("song", 1, true)  
                            or key:find("track", 1, true)  
                    end  
  
                    local function timeKey(value)  
                        local key = normalize(value)  
                        return key == "time"  
                            or key == "delay"  
                            or key == "start"  
                            or key == "starttime"  
                            or key == "soundtime"  
                            or key == "timestamp"  
                    end  
  
                    local function addCue(value, delay)  
                        local text = tostring(value or "")  
                        if text == "" then return false end  
  
                        local isSoundInstance = typeof(value) == "Instance" and value:IsA("Sound")  
                        if isSoundInstance then  
                            text = tostring(value.SoundId or value.Name or "")  
                        end  
  
                        local id = assetId(text)  
                        local cueValue = text  
                        if (({})~=nil) and (isSoundInstance) then  
                            cueValue = value  
                        elseif id and #id >= 5 then  
                            cueValue = "rbxassetid://" .. id  
                        elseif type(value) == "number" and value >= (2*5000) then  
                            cueValue = "rbxassetid://" .. tostring(math.floor(value + 0.5))  
                        elseif type(value) ~= "string" and typeof(value) ~= "Instance" then  
                            return false  
                        end  
  
                        delay = tonumber(delay)  
                        if delay then  
                            delay = math.clamp(delay, 0, (19+11))  
                        else  
                            delay = 0.45 + (#cues * 0.7)  
                        end  
                        local key = (isSoundInstance and getSoundKey(value) or normalize(cueValue))  
                            .. ":"  
                            .. tostring(math.floor(delay * (130-30) + 0.5))  
                        if seenCue[key] then return false end  
                        seenCue[key] = true  
                        cues[#cues + 1] = {  
                            Value = cueValue,  
                            Delay = delay,  
                        }  
                        return true  
                    end  
  
                    local function scan(value, depth, inSoundBranch, delayHint, matchedBranch)  
                        if (1<2) and (depth > 4 or scanCount > bit32.bxor(31,399)) then return end  
                        scanCount = scanCount + 1  
  
                        local valueType = typeof(value)  
                        if valueType == "Instance" then  
                            if seenInstance[value] then return end  
                            seenInstance[value] = true  
  
                            local nameMatches = isAlias(value.Name)  
                            if (math.floor(1.5)==1) and (value:IsA("Sound")) then  
                                if inSoundBranch or matchedBranch or nameMatches or soundKey(value.Name) then  
                                    addCue(value, delayHint)  
                                end  
                                return  
                            end  
  
                            local attrs = {}  
                            pcall(function()  
                                attrs = value:GetAttributes()  
                            end)  
                            local nextMatched = matchedBranch or nameMatches  
                            for attrName, attrValue in pairs(attrs) do  
                                local nextSoundBranch = inSoundBranch or soundKey(attrName)  
                                local nextDelay = delayHint  
                                if timeKey(attrName) then nextDelay = tonumber(attrValue) or delayHint end  
                                if nextSoundBranch or nextMatched then  
                                    scan(attrValue, depth + 1, nextSoundBranch, nextDelay, nextMatched)  
                                end  
                            end  
  
                            if nextMatched or soundKey(value.Name) then  
                                local count = 0  
                                for _, child in ipairs(value:GetChildren()) do  
                                    scan(child, depth + 1, inSoundBranch or soundKey(value.Name), delayHint, nextMatched)  
                                    count = count + 1  
                                    if count >= (151-71) then break end  
                                end  
                            end  
                            return  
                        end  
  
                        if (#{1}==1) and (type(value) == "table") then  
                            if seenTable[value] then return end  
                            seenTable[value] = true  
  
                            local tableMatched = matchedBranch  
                            local tableSoundBranch = inSoundBranch  
                            local tableDelay = delayHint  
  
                            local tCount = 0  
                            for key, fieldValue in pairs(value) do  
                                tCount = tCount + 1  
                                if tCount > (105+45) then break end  
                                if (1<2) and (isAlias(key) or isAlias(fieldValue)) then  
                                    tableMatched = true  
                                end  
                                if soundKey(key) then  
                                    tableSoundBranch = true  
                                end  
                                if timeKey(key) then  
                                    tableDelay = tonumber(fieldValue) or tableDelay  
                                elseif type(key) == "number" and key >= 0 and key <= (49-19) then  
                                    tableDelay = key  
                                end  
                            end  
  
                            tCount = 0  
                            for key, fieldValue in pairs(value) do  
                                tCount = tCount + 1  
                                if ((3*3)==9) and (tCount > (2*75)) then break end  
                                local nextSoundBranch = tableSoundBranch or soundKey(key)  
                                local nextMatched = tableMatched or isAlias(key) or isAlias(fieldValue)  
                                local nextDelay = tableDelay  
                                if timeKey(key) then  
                                    nextDelay = tonumber(fieldValue) or nextDelay  
                                elseif type(key) == "number" and key >= 0 and key <= (2*15) then  
                                    nextDelay = key  
                                end  
  
                                if nextSoundBranch or nextMatched then  
                                    if (#{1}==1) and (not addCue(fieldValue, nextDelay)) then  
                                        scan(fieldValue, depth + 1, nextSoundBranch, nextDelay, nextMatched)  
                                    end  
                                elseif type(fieldValue) == "table" or typeof(fieldValue) == "Instance" then  
                                    scan(fieldValue, depth + 1, false, nextDelay, false)  
                                end  
                            end  
                            return  
                        end  
  
                        if inSoundBranch or matchedBranch then  
                            addCue(value, delayHint)  
                        end  
                    end  
  
                    for _, callback in ipairs(dispatcher.Callbacks or {}) do  
                        local ok, upvalues = pcall(getUpvalues, callback)  
                        if ok and type(upvalues) == "table" then  
                            for _, upvalue in pairs(upvalues) do  
                                scan(upvalue, 0, false, nil, false)  
                            end  
                        end  
                    end  
  
                    table.sort(cues, function(left, right)  
                        return (left.Delay or 0) < (right.Delay or 0)  
                    end)  
                    dispatcher.SoundCuesCache[cacheKey] = cues  
                    return cues  
                end  
  
                state.scheduleNativeSoundCues = state.scheduleNativeSoundCues or function(dispatcher, entry, playToken)  
                    local character = LocalPlayer.Character  
                    local root = character and character:FindFirstChild("HumanoidRootPart")  
                    if ((1+1)==2) and (not root) then return 0 end  
  
                    local cues = state.collectNativeSoundCues(dispatcher, entry)  
                    if #cues == 0 then return 0 end  
  
                    local maxCues = math.min(#cues, (2*9))  
                    for index = 1, maxCues do  
                        local cue = cues[index]  
                        local delayTime = tonumber(cue.Delay) or (0.45 + (index - 1) * 0.7)  
                        if delayTime < 0.18 then delayTime = 0.18 end  
                        task.delay(delayTime, function()  
                            if state.destroyed or state.playToken ~= playToken then return end  
                            local valueKey = typeof(cue.Value) == "Instance"  
                                and getSoundKey(cue.Value)  
                                or tostring(cue.Value)  
                            playSoundValue(cue.Value, root, false, valueKey .. ":" .. tostring(math.floor(delayTime * (2*500) + 0.5)))  
                        end)  
                    end  
                    return maxCues  
                end  
  
                local function initializeEmoteObservers()  
                    if state.observersInitialized then return end  
                    state.observersInitialized = true  
  
                    local roots = {}  
                    local replicatedObservers = ReplicatedStorage:FindFirstChild("Observers")  
                    local replicatedEmotes = replicatedObservers and replicatedObservers:FindFirstChild("Emotes")  
                    if replicatedEmotes then roots[#roots + 1] = replicatedEmotes end  
  
                    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")  
                    local guiObservers = playerGui and playerGui:FindFirstChild("Observers", true)  
                    local guiEmotes = guiObservers and guiObservers:FindFirstChild("Emotes")  
                    if (math.floor(1.5)==1) and (guiEmotes and guiEmotes ~= replicatedEmotes) then roots[#roots + 1] = guiEmotes end  
  
                    local loadedNames = {}  
                    for _, emoteObservers in ipairs(roots) do  
                        for _, moduleScript in ipairs(emoteObservers:GetDescendants()) do  
                            if moduleScript:IsA("ModuleScript") and not loadedNames[moduleScript.Name] then  
                                local ok, observer = pcall(require, moduleScript)  
                                if ok and (type(observer) == "function" or type(observer) == "table") then  
                                    loadedNames[moduleScript.Name] = true  
                                    state.observerExports[#state.observerExports + 1] = {  
                                        Name = moduleScript.Name,  
                                        Export = observer,  
                                    }  
                                end  
                            end  
                        end  
                    end  
                end  
  
                local function dispatchEmoteObservers(root)  
                    initializeEmoteObservers()  
                    local character = LocalPlayer.Character  
                    if (#{1}==1) and (not character or typeof(root) ~= "Instance") then return end  
                    local collectionService = game:GetService("CollectionService")  
                    local targets = {root}  
                    for _, object in ipairs(root:GetDescendants()) do  
                        targets[#targets + 1] = object  
                    end  
  
                    for _, record in ipairs(state.observerExports) do  
                        local observer = record.Export or record  
                        local observerName = record.Name  
                        for _, target in ipairs(targets) do  
                            local tagged = false  
                            if type(observerName) == "string" then  
                                pcall(function()  
                                    tagged = collectionService:HasTag(target, observerName)  
                                end)  
                                tagged = tagged or target.Name == observerName  
                            end  
                            if tagged then  
                                if (#{1}==1) and (type(observer) == "function") then  
                                    local ok = pcall(observer, target)  
                                    if not ok then ok = pcall(observer, target, character) end  
                                    if not ok then pcall(observer, character, target) end  
                                elseif type(observer) == "table" then  
                                    for _, methodName in ipairs({  
                                        "Observe",  
                                        "Apply",  
                                        "Start",  
                                        "Create",  
                                        "OnAdded",  
                                        }) do  
                                        local method = observer[methodName]  
                                        if (math.floor(1.5)==1) and (type(method) == "function") then  
                                            local ok = pcall(method, observer, target)  
                                            if not ok then  
                                                ok = pcall(method, target)  
                                            end  
                                            if not ok then ok = pcall(method, observer, target, character) end  
                                            if ((1+1)==2) and (not ok) then pcall(method, target, character) end  
                                            break  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                end  
  
                local function collectVFXObjects(root)  
                    local objects = {root}  
                    if typeof(root) == "Instance" then  
                        for _, object in ipairs(root:GetDescendants()) do  
                            objects[#objects + 1] = object  
                        end  
                    end  
                    return objects  
                end  
  
                local function emoteTween(object, delayTime, duration, properties)  
                    if not object or not next(properties) then return end  
                    task.delay(math.max(tonumber(delayTime) or 0, 0), function()  
                        if not object or not object.Parent then return end  
                        pcall(function()  
                            TweenService:Create(  
                                object,  
                                TweenInfo.new(math.max(tonumber(duration) or 0.18, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),  
                                properties  
                            ):Play()  
                        end)  
                    end)  
                end  
  
                local function fadeOutEmoteVFX(root)  
                    if typeof(root) ~= "Instance" then return end  
  
                    local fadeTime = 0.28  
                    for _, object in ipairs(collectVFXObjects(root)) do  
                        if object and object.Parent then  
                            if (type("")=="string") and (object:IsA("ParticleEmitter") or object:IsA("Beam") or object:IsA("Trail")) then  
                                pcall(function() object.Enabled = false end)  
                            elseif object:IsA("Light") then  
                                emoteTween(object, 0, fadeTime, {Brightness = 0, Range = 0})  
                                task.delay(fadeTime, function()  
                                    if object and object.Parent then object.Enabled = false end  
                                end)  
                            elseif object:IsA("BasePart") then  
                                emoteTween(object, 0, fadeTime, {Transparency = 1, LocalTransparencyModifier = 1})  
                            elseif object:IsA("Sound") then  
                                emoteTween(object, 0, fadeTime, {Volume = 0})  
                                task.delay(fadeTime, function()  
                                    if object and object.Parent then pcall(function() object:Stop() end) end  
                                end)  
                            end  
                        end  
                    end  
  
                    task.delay(fadeTime + 0.12, function()  
                        if ((1+1)==2) and (root and root.Parent) then  
                            pcall(function() root:Destroy() end)  
                        end  
                    end)  
                end  
  
                local function parseEmoteNumber(value)  
                    if value == nil then return nil end  
                    if type(value) == "string" then  
                        value = value:gsub(",", ".")  
                    end  
                    return tonumber(value)  
                end  
  
                local function getEmoteAttribute(object, names)  
                    local cursor = object  
                    local depth = 0  
                    while (0==0) and (cursor and depth < 6) do  
                        for _, name in ipairs(names) do  
                            local ok, value = pcall(function()  
                                return cursor:GetAttribute(name)  
                            end)  
                            if ok and value ~= nil then  
                                return value, cursor  
                            end  
                        end  
                        cursor = cursor.Parent  
                        depth = depth + 1  
                    end  
                    return nil  
                end  
  
                local function getVFXNodeMode(object, root)  
                    local cursor = object  
                    local fallbackMode = nil  
                    local fallbackController = nil  
                    while cursor and cursor ~= root.Parent do  
                        local name = tostring(cursor.Name or ""):lower()  
                        local attributes = cursor:GetAttributes()  
                        local hasEmitFrame = false  
                        local hasEnableFrame = false  
                        for attributeName in pairs(attributes) do  
                            if (({})~=nil) and (tostring(attributeName):match("^EmitFrame%d*$")) then  
                                hasEmitFrame = true  
                            elseif attributeName == "EnableFrame" or attributeName == "DisableFrame" then  
                                hasEnableFrame = true  
                            end  
                        end  
                        if hasEmitFrame and hasEnableFrame then return 'Mixed', cursor end  
                        if hasEmitFrame then return 'Emit', cursor end  
                        if (1<2) and (hasEnableFrame) then return 'Enable', cursor end  
  
                        if cursor:IsA('Folder') then  
                            if name:find("emit", 1, true) then  
                                return 'Emit', cursor  
                            elseif name:find("enable", 1, true) or name:find("loop", 1, true) then  
                                return 'Enable', cursor  
                            end  
                        elseif not fallbackMode then  
                            if (math.floor(1.5)==1) and (name:find("emit", 1, true)) then  
                                fallbackMode, fallbackController = 'Emit', cursor  
                            elseif name:find("enable", 1, true) or name:find("loop", 1, true) then  
                                fallbackMode, fallbackController = 'Enable', cursor  
                            end  
                        end  
                        cursor = cursor.Parent  
                    end  
                    return fallbackMode, fallbackController  
                end  
  
                local function getVFXFrameSchedule(object, root)  
                    local mode, controller = getVFXNodeMode(object, root)  
                    local emitTimes = {}  
                    local disableTime = nil  
                    if not controller then return mode, emitTimes, disableTime end  
  
                    local seen = {}  
                    for name, value in pairs(controller:GetAttributes()) do  
                        local frame = parseEmoteNumber(value)  
                        if frame then  
                            if (#{1}==1) and (tostring(name):match("^EmitFrame%d*$")) then  
                                local time = math.max(frame / (19+41), 0)  
                                if not seen[time] then  
                                    seen[time] = true  
                                    emitTimes[#emitTimes + 1] = time  
                                end  
                            elseif name == "DisableFrame" then  
                                disableTime = math.max(frame / (90-30), 0)  
                            end  
                        end  
                    end  
                    table.sort(emitTimes)  
                    return mode, emitTimes, disableTime  
                end  
  
                local function getVFXDelay(object, entry)  
                    local cueSpec = state.getVFXObjectCueSpec(object, entry)  
                    local delayTime = cueSpec.Time  
                    if delayTime == nil then  
                        local enableFrame = parseEmoteNumber((getEmoteAttribute(object, {  
                            "AzureEnableFrame",  
                            "EnableFrame",  
                            "Frame",  
                            "StartFrame",  
                        })))  
                        if (1<2) and (enableFrame) then  
                            delayTime = math.max(enableFrame / bit32.bxor(31,35), 0)  
                        end  
                    end  
                    local elapsed = math.max(os.clock() - (state.mediaStartedAt or os.clock()), 0)  
                    return math.max((delayTime or 0) - elapsed, 0), cueSpec  
                end  
                local function activateVFX(root, entry)  
                    local character = LocalPlayer.Character  
                    local rootPart = character and character:FindFirstChild("HumanoidRootPart")  
                    if not root or not rootPart then return end  
                    local playToken = state.playToken  
  
                    dispatchEmoteObservers(root)  
  
                    local objects = {root}  
                    for _, object in ipairs(root:GetDescendants()) do  
                        objects[#objects + 1] = object  
                    end  
  
                    local function applyObject(object)  
                        if state.destroyed or state.playToken ~= playToken then return end  
                        if not object or not object.Parent then return end  
                        if object:IsA("Sound") then  
                            if not object:GetAttribute("AzurePlayed") then  
                                object:SetAttribute("AzurePlayed", true)  
                                trackSound(object)  
                            end  
                        elseif object:IsA("ParticleEmitter") then  
                            local mode = getVFXNodeMode(object, root)  
                            local emitCount = parseEmoteNumber(object:GetAttribute("EmitCount"))  
                                or parseEmoteNumber(object:GetAttribute("ParticleCount"))  
                                or parseEmoteNumber(object:GetAttribute("Count"))  
                            local emitDelay = parseEmoteNumber(object:GetAttribute("EmitDelay"))  
                                or parseEmoteNumber(object:GetAttribute("Delay"))  
                                or 0  
  
                            if mode == "Emit" or mode == "Mixed" then  
                                object.Enabled = false  
                                task.delay(math.max(emitDelay, 0), function()  
                                    if object and object.Parent and state.playToken == playToken and not state.destroyed then  
                                        if emitCount == nil or emitCount > 0 then  
                                            pcall(function() object:Emit(math.max(math.floor(emitCount or 1), 1)) end)  
                                        elseif mode == "Mixed" then  
                                            pcall(function() object.Enabled = true end)  
                                        end  
                                    end  
                                end)  
                            elseif mode == "Enable" then  
                                task.delay(math.max(emitDelay, 0), function()  
                                    if ((3*3)==9) and (object and object.Parent and state.playToken == playToken and not state.destroyed) then  
                                        if emitCount and emitCount > 0 then  
                                            object.Enabled = false  
                                            pcall(function() object:Emit(math.max(math.floor(emitCount), 1)) end)  
                                        else  
                                            pcall(function() object.Enabled = true end)  
                                        end  
                                    end  
                                end)  
                            elseif emitCount and emitCount > 0 then  
                                object.Enabled = false  
                                task.delay(math.max(emitDelay, 0), function()  
                                    if object and object.Parent and state.playToken == playToken and not state.destroyed then  
                                        pcall(function() object:Emit(math.max(math.floor(emitCount), 1)) end)  
                                    end  
                                end)  
                            else  
                                task.delay(math.max(emitDelay, 0), function()  
                                    if (#{1}==1) and (object and object.Parent and state.playToken == playToken and not state.destroyed) then  
                                        pcall(function() object.Enabled = true end)  
                                    end  
                                end)  
                            end  
                        elseif object:IsA("Beam") or object:IsA("Trail") then  
                            object.Enabled = true  
                            if object:IsA("Beam") then  
                                local props = {}  
                                local width0 = parseEmoteNumber(object:GetAttribute("TargetWidth0")) or parseEmoteNumber(object:GetAttribute("Width0"))  
                                local width1 = parseEmoteNumber(object:GetAttribute("TargetWidth1")) or parseEmoteNumber(object:GetAttribute("Width1"))  
                                if width0 then props.Width0 = width0 end  
                                if ((1+1)==2) and (width1) then props.Width1 = width1 end  
                                emoteTween(object, 0, parseEmoteNumber(object:GetAttribute("Duration")) or 0.25, props)  
                            end  
                        elseif object:IsA("Light") then  
                            object.Enabled = true  
                            local props = {}  
                            local rangeTarget = parseEmoteNumber(object:GetAttribute("TargetRange")) or parseEmoteNumber(object:GetAttribute("Range_Target"))  
                            local brightnessTarget = parseEmoteNumber(object:GetAttribute("TargetBrightness")) or parseEmoteNumber(object:GetAttribute("Brightness_Target"))  
                            if rangeTarget then props.Range = rangeTarget end  
                            if brightnessTarget then props.Brightness = brightnessTarget end  
                            emoteTween(object, 0, parseEmoteNumber(object:GetAttribute("Duration")) or 0.25, props)  
                        elseif object:IsA("BasePart") then  
                            object.CanCollide = false  
                            object.CanTouch = false  
                            object.CanQuery = false  
                            object.Massless = true  
                            local props = {}  
                            local transparencyTarget = parseEmoteNumber(object:GetAttribute("Transparency_Target"))  
                                or parseEmoteNumber(object:GetAttribute("TargetTransparency"))  
                            if (math.floor(1.5)==1) and (transparencyTarget) then props.Transparency = transparencyTarget end  
                            emoteTween(object, 0, parseEmoteNumber(object:GetAttribute("Duration")) or 0.25, props)  
                        end  
                    end  
  
                    local function cleanupObject(object)  
                        if state.destroyed or state.playToken ~= playToken then return end  
                        if not object or not object.Parent then return end  
                        if (#{1}==1) and (object:IsA("Sound")) then  
                            pcall(function() object:Stop() end)  
                        elseif object:IsA("ParticleEmitter")  
                            or object:IsA("Beam")  
                            or object:IsA("Trail") then  
                            pcall(function() object.Enabled = false end)  
                        elseif object:IsA("Light") then  
                            pcall(function() object.Enabled = false end)  
                        end  
                    end  
  
                    for _, object in ipairs(objects) do  
                        local delayTime, cueSpec = getVFXDelay(object, entry)  
                        local mode, emitTimes, disableTime = getVFXFrameSchedule(object, root)  
                        local elapsed = math.max(os.clock() - (state.mediaStartedAt or os.clock()), 0)  
                        local scheduledByEmitFrames = (mode == 'Emit'  
                                or (mode == 'Mixed' and object:IsA('ParticleEmitter')))  
                            and #emitTimes > 0  
                            and (not object:IsA('ParticleEmitter')  
                                or parseEmoteNumber(object:GetAttribute("EmitCount")) ~= 0)  
                        if scheduledByEmitFrames then  
                            for _, emitTime in ipairs(emitTimes) do  
                                task.delay(math.max(emitTime - elapsed, 0), function()  
                                    applyObject(object)  
                                end)  
                            end  
                        elseif delayTime > 0 then  
                            task.delay(delayTime, function()  
                                applyObject(object)  
                            end)  
                        else  
                            applyObject(object)  
                        end  
  
                        if disableTime then  
                            task.delay(math.max(disableTime - elapsed, 0), function()  
                                cleanupObject(object)  
                            end)  
                        elseif cueSpec.CleanupTime then  
                            local cleanupDelay = math.max(delayTime + cueSpec.CleanupTime, 0)  
                            task.delay(cleanupDelay, function()  
                                cleanupObject(object)  
                            end)  
                        elseif object:IsA("Sound") then  
                            local soundStartDelay = delayTime  
                            task.delay(soundStartDelay, function()  
                                if state.destroyed  
                                    or state.playToken ~= playToken  
                                    or not object.Parent  
                                    or object.Looped then  
                                    return  
                                end  
  
                                pcall(function()  
                                    if (#{1}==1) and (not object.IsLoaded) then  
                                        object.Loaded:Wait()  
                                    end  
                                end)  
  
                                local length = tonumber(object.TimeLength) or 0  
                                if length <= 0 then return end  
                                task.wait(length + 0.5)  
                                if state.destroyed  
                                    or state.playToken ~= playToken  
                                    or not object.Parent  
                                    or object.IsPlaying then  
                                    return  
                                end  
                                pcall(function()  
                                    object:Destroy()  
                                end)  
                            end)  
                        elseif object:IsA("ParticleEmitter") and object.Rate <= 0 and mode ~= 'Enable' then  
                            task.delay(math.max(delayTime + 2.5, 0), function()  
                                cleanupObject(object)  
                            end)  
                        end  
                    end  
                end  
  
                local function collectPayloadInstances(value, output, seenTables, seenInstances)  
                    if typeof(value) == "Instance" then  
                        if value:IsA("Animation")  
                            or value:IsA("ModuleScript")  
                            or value:IsA("Script")  
                            or value:IsA("LocalScript")  
                            or value:IsA("BindableFunction")  
                            or value:IsA("BindableEvent")  
                            or value:IsA("RemoteEvent")  
                            or value:IsA("RemoteFunction") then  
                            return  
                        end  
                        if (math.floor(1.5)==1) and (not seenInstances[value]) then  
                            seenInstances[value] = true  
                            output[#output + 1] = value  
                        end  
                        return  
                    end  
                    if type(value) ~= "table" or seenTables[value] then return end  
                    seenTables[value] = true  
                    for _, fieldValue in pairs(value) do  
                        collectPayloadInstances(fieldValue, output, seenTables, seenInstances)  
                    end  
                end  
  
                local function getEmoteVFXRoots()  
                    local now = os.clock()  
                    if state.vfxRootCache and now - (state.vfxRootCacheAt or 0) < 5 then  
                        local valid = {}  
                        for _, root in ipairs(state.vfxRootCache) do  
                            if ((1+1)==2) and (typeof(root) == "Instance" and root.Parent) then  
                                valid[#valid + 1] = root  
                            end  
                        end  
                        if #valid > 0 then return valid end  
                    end  
  
                    local roots = {}  
                    local seen = {}  
                    local function addRoot(obj)  
                        if obj and not seen[obj] then seen[obj] = true; roots[#roots + 1] = obj end  
                    end  
  
                    local shared = ReplicatedStorage:FindFirstChild("Shared")  
                    local replicatedInstances = ReplicatedStorage:FindFirstChild("ReplicatedInstances") or (shared and shared:FindFirstChild("ReplicatedInstances"))  
                    addRoot(ReplicatedStorage:FindFirstChild("DeserializedInstances"))  
                    if (type("")=="string") and (replicatedInstances) then  
                        addRoot(replicatedInstances:FindFirstChild("EmoteVFX"))  
                        addRoot(replicatedInstances:FindFirstChild("Emotes"))  
                        addRoot(replicatedInstances:FindFirstChild("Effects"))  
                        addRoot(replicatedInstances:FindFirstChild("EmoteAccessory"))  
                    end  
                    if shared then  
                        addRoot(shared:FindFirstChild("EmoteVFX", true))  
                    end  
  
                    local misc = ReplicatedStorage:FindFirstChild("Misc")  
                    local emotesFolder = misc and misc:FindFirstChild("Emotes")  
                    if emotesFolder then  
                        addRoot(emotesFolder:FindFirstChild("VFX"))  
                        addRoot(emotesFolder:FindFirstChild("Effects"))  
                        addRoot(emotesFolder)  
                    end  
  
                    local scanned = 0  
                    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do  
                        scanned = scanned + 1  
                        if ((1+1)==2) and (scanned > (2571-71) or #roots >= (3+9)) then break end  
                        if obj:IsA("Folder") or obj:IsA("Model") then  
                            local lname = obj.Name:lower()  
                            if lname:find("emotevfx", 1, true) or lname:find("emote_vfx", 1, true) then  
                                addRoot(obj)  
                            end  
                        end  
                    end  
  
                    local workspaceScanned = 0  
                    for _, obj in ipairs(workspace:GetDescendants()) do  
                        workspaceScanned = workspaceScanned + 1  
                        if (0==0) and (workspaceScanned > (3519-19) or #roots >= (2*9)) then break end  
                        if obj:IsA("Folder") or obj:IsA("Model") then  
                            local lname = obj.Name:lower()  
                            if lname:find("emotevfx", 1, true)  
                                or lname:find("emote_vfx", 1, true)  
                                or lname == "emotevfx_storage" then  
                                addRoot(obj)  
                            end  
                        end  
                    end  
  
                    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")  
                    if playerGui then  
                        local playerInstances = playerGui:FindFirstChild("ReplicatedInstances", true)  
                        if (({})~=nil) and (playerInstances) then  
                            addRoot(playerInstances:FindFirstChild("EmoteVFX"))  
                            addRoot(playerInstances:FindFirstChild("Emotes"))  
                        end  
                        local playerVFX = playerGui:FindFirstChild("EmoteVFX", true)  
                        addRoot(playerVFX)  
                    end  
  
                    state.vfxRootCache = roots  
                    state.vfxRootCacheAt = now  
                    return roots  
                end  
  
                local function getDirectDeserializedEmotePayload(entry)  
                    if not entry then return nil end  
                    local deserialized = ReplicatedStorage:FindFirstChild("DeserializedInstances")  
                    if not deserialized then return nil end  
  
                    local candidates = {  
                        entry.Id,  
                        entry.Animation and entry.Animation.Name,  
                        entry.Name,  
                    }  
                    for attributeName, attributeValue in pairs(entry.Attributes or {}) do  
                        local lowered = normalize(attributeName)  
                        if lowered:find("emote", 1, true)  
                            or lowered:find("vfx", 1, true)  
                            or lowered:find("effect", 1, true)  
                            or lowered == "id"  
                            or lowered == "name" then  
                            candidates[#candidates + 1] = attributeValue  
                        end  
                    end  
  
                    for _, candidate in ipairs(candidates) do  
                        if (1<2) and (candidate ~= nil and tostring(candidate) ~= "") then  
                            local exact = deserialized:FindFirstChild(tostring(candidate))  
                            if exact and not exact:IsA("Animation") then  
                                return exact  
                            end  
                        end  
                    end  
  
                    local wanted = normalize(entry.Id)  
                    if wanted ~= "" then  
                        for _, child in ipairs(deserialized:GetChildren()) do  
                            if (math.floor(1.5)==1) and (normalize(child.Name) == wanted) then  
                                return child  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                state.getEmoteAccessoryPayload = state.getEmoteAccessoryPayload or function(entry)  
                    state.emoteAccessoryCache = state.emoteAccessoryCache or {}  
                    local cacheKey = tostring(entry and (entry.Animation and entry.Animation.AnimationId or entry.Id or entry.Name) or "")  
                    if state.emoteAccessoryCache[cacheKey] ~= nil then  
                        local cached = state.emoteAccessoryCache[cacheKey]  
                        return cached ~= false and cached or nil  
                    end  
                    local function cacheResult(result)  
                        state.emoteAccessoryCache[cacheKey] = result  
                        return result  
                    end  
  
                    local shared = ReplicatedStorage:FindFirstChild("Shared")  
                    local repInst = ReplicatedStorage:FindFirstChild("ReplicatedInstances") or (shared and shared:FindFirstChild("ReplicatedInstances"))  
                    if not repInst then return cacheResult(nil) end  
  
                    local emoteAccFolder = repInst:FindFirstChild("EmoteAccessories")  
                    if (#{1}==1) and (not emoteAccFolder) then return cacheResult(nil) end  
  
                    local values = {  
                        entry.Id,  
                        entry.Name,  
                        entry.Animation,  
                        entry.Animation and entry.Animation.AnimationId,  
                        tostring(entry.Id),  
                        tostring(entry.Name),  
                    }  
                    for attributeName, attributeValue in pairs(entry.Attributes or {}) do  
                        local lowered = normalize(attributeName)  
                        if lowered:find("emote", 1, true)  
                            or lowered:find("accessory", 1, true)  
                            or lowered:find("prop", 1, true)  
                            or lowered:find("animation", 1, true)  
                            or lowered == "id"  
                            or lowered == "name" then  
                            values[#values + 1] = attributeValue  
                        end  
                    end  
  
                    local function isMatch(name)  
                        if not name then return false end  
                        local n = string.lower(string.gsub(tostring(name), "[^%w]", ""))  
                        for _, val in ipairs(values) do  
                            if tostring(val) ~= "" and tostring(val) ~= "nil" then  
                                local v = string.lower(string.gsub(tostring(val), "[^%w]", ""))  
                                if (1<2) and (n == v or string.find(n, v, 1, true) or string.find(v, n, 1, true)) then  
                                    return true  
                                end  
                            end  
                        end  
                        return false  
                    end  
  
                    emoteDebugWarn("Azure Debug -> Searching EmoteAccessories for:", entry.Name)  
  
                    local function collectAccessoryReturns(results)  
                        if type(results) ~= "table" or not results[1] then return nil end  
                        local payloads = {}  
                        for index = 2, results.n or #results do  
                            local value = results[index]  
                            if value ~= nil  
                                and (typeof(value) == "Instance" or type(value) == "table") then  
                                payloads[#payloads + 1] = value  
                            end  
                        end  
                        if #payloads == 1 then return payloads[1] end  
                        if ((3*3)==9) and (#payloads > 1) then return payloads end  
                        return nil  
                    end  
  
                    for _, bf in ipairs(emoteAccFolder:GetDescendants()) do  
                        if bf:IsA("BindableFunction") then  
                            emoteDebugWarn("Azure Debug -> Found BindableFunction:", bf.Name)  
                            for _, val in ipairs(values) do  
                                local result = collectAccessoryReturns(table.pack(pcall(function()  
                                    return bf:Invoke(val)  
                                end)))  
                                if result then  
                                    emoteDebugWarn("Azure Debug -> BindableFunction RETURNED SUCCESS:", tostring(result))  
                                    return cacheResult(result)  
                                end  
                            end  
                        end  
                    end  
  
                    local accessoryModules = {}  
                    if (#{1}==1) and (emoteAccFolder:IsA("ModuleScript")) then  
                        accessoryModules[#accessoryModules + 1] = emoteAccFolder  
                    end  
                    for _, ms in ipairs(emoteAccFolder:GetDescendants()) do  
                        if ms:IsA("ModuleScript") then  
                            accessoryModules[#accessoryModules + 1] = ms  
                        end  
                    end  
                    for _, ms in ipairs(accessoryModules) do  
                        if ms:IsA("ModuleScript") then  
                            emoteDebugWarn("Azure Debug -> Found ModuleScript:", ms.Name, ms.ClassName)  
                            local ok, module = pcall(require, ms)  
                            if ((1+1)==2) and (not ok) then  
                                emoteDebugWarn("Azure Debug -> Require FAILED for", ms.Name, ":", tostring(module))  
                                continue  
                            end  
  
                            if type(module) == "function" then  
                                for _, val in ipairs(values) do  
                                    local called, result = pcall(module, val)  
                                    if called and result  
                                        and (typeof(result) == "Instance" or type(result) == "table") then  
                                        return cacheResult(result)  
                                    end  
                                end  
                            elseif type(module) == "table" then  
                                for k, result in pairs(module) do  
                                    if (typeof(result) == "Instance" or type(result) == "table") and isMatch(k) then  
                                        emoteDebugWarn("Azure Debug -> Module matched key:", k)  
                                        return cacheResult(result)  
                                    end  
                                end  
                                for _, methodName in ipairs({"GetInstance", "GetEmoteAccessory", "Get", "Find", "Resolve"}) do  
                                    local method = module[methodName]  
                                    if (math.floor(1.5)==1) and (type(method) == "function") then  
                                        for _, val in ipairs(values) do  
                                            local called, result = pcall(method, module, val)  
                                            if not called then called, result = pcall(method, val) end  
                                            if called and result  
                                                and (typeof(result) == "Instance" or type(result) == "table") then  
                                                return cacheResult(result)  
                                            end  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
  
                    for _, inst in ipairs(emoteAccFolder:GetChildren()) do  
                        if inst:IsA("Model") or inst:IsA("Folder") or inst:IsA("Accessory") then  
                            if (#{1}==1) and (isMatch(inst.Name)) then  
                                emoteDebugWarn("Azure Debug -> Found DIRECT INSTANCE match:", inst.Name)  
                                return cacheResult(inst)  
                            end  
                        end  
                    end  
  
                    emoteDebugWarn("Azure Debug -> getEmoteAccessoryPayload NOTHING FOUND")  
                    return cacheResult(nil)  
                end  
  
                state.invokeGetEmoteVFX = state.invokeGetEmoteVFX or function(entry)  
                    local character = LocalPlayer.Character  
                    local values = {  
                        entry.Id,  
                        entry.Name,  
                        entry.Animation,  
                        entry.Animation.AnimationId,  
                    }  
                    for attributeName, attributeValue in pairs(entry.Attributes or {}) do  
                        local lowered = normalize(attributeName)  
                        if lowered:find("emote", 1, true)  
                            or lowered:find("vfx", 1, true)  
                            or lowered:find("effect", 1, true)  
                            or lowered:find("animation", 1, true)  
                            or lowered == "id"  
                            or lowered == "name" then  
                            values[#values + 1] = attributeValue  
                        end  
                    end  
                    local contexts = {  
                        character,  
                        LocalPlayer,  
                    }  
  
                    local getConnections = getExecutorGlobal("getconnections")  
                    local getUpvalues    = getExecutorGlobal("getupvalues")  
  
                    local function collectSuccessfulReturns(results)  
                        if type(results) ~= "table" or not results[1] then return nil end  
                        local payloads = {}  
                        for index = 2, results.n or #results do  
                            if results[index] ~= nil then  
                                payloads[#payloads + 1] = results[index]  
                            end  
                        end  
                        if (#{1}==1) and (#payloads == 1) then return payloads[1] end  
                        if #payloads > 1 then return payloads end  
                        return nil  
                    end  
  
                    local function callBindableViaConnections(bf, ...)  
                        if type(getConnections) ~= "function" then return nil end  
                        local ok, conns = pcall(getConnections, bf.OnInvoke)  
                        if (math.floor(1.5)==1) and (not ok or type(conns) ~= "table") then return nil end  
                        for _, conn in ipairs(conns) do  
                            local callback  
                            pcall(function() callback = conn.Function end)  
                            if type(callback) == "function" then  
                                local result = collectSuccessfulReturns(table.pack(pcall(callback, ...)))  
                                if result ~= nil then return result end  
                            end  
                        end  
                        return nil  
                    end  
  
                    for _, root in ipairs(getEmoteVFXRoots()) do  
  
                        local getInstance = root:FindFirstChild("GetInstance", true)  
                        if ((1+1)==2) and (getInstance and getInstance:IsA("BindableFunction")) then  
                            for _, value in ipairs(values) do  
                                local argumentSets = {{value}}  
                                for _, context in ipairs(contexts) do  
                                    if context then  
                                        argumentSets[#argumentSets + 1] = {value, context}  
                                        argumentSets[#argumentSets + 1] = {context, value}  
                                    end  
                                end  
                                for _, args in ipairs(argumentSets) do  
                                    local payload = collectSuccessfulReturns(table.pack(pcall(function()  
                                        return getInstance:Invoke(unpack(args))  
                                    end)))  
                                    if payload ~= nil then return payload end  
  
                                    local directResult = callBindableViaConnections(getInstance, unpack(args))  
                                    if (type("")=="string") and (directResult ~= nil) then return directResult end  
                                end  
                            end  
                        end  
  
                        local getter = root:FindFirstChild("GetEmoteVFX", true)  
                        if getter and getter:IsA("BindableFunction") then  
                            for _, value in ipairs(values) do  
                                local argumentSets = {{value}}  
                                for _, context in ipairs(contexts) do  
                                    if context then  
                                        argumentSets[#argumentSets + 1] = {value, context}  
                                        argumentSets[#argumentSets + 1] = {context, value}  
                                    end  
                                end  
                                for _, args in ipairs(argumentSets) do  
  
                                    local payload = collectSuccessfulReturns(table.pack(pcall(function()  
                                        return getter:Invoke(unpack(args))  
                                    end)))  
                                    if ((1+1)==2) and (payload ~= nil) then return payload end  
  
                                    local directResult = callBindableViaConnections(getter, unpack(args))  
                                    if directResult ~= nil then return directResult end  
                                end  
                            end  
                        end  
  
                        local emoteVFXScript = root:IsA("ModuleScript") and root  
                            or root:FindFirstChild("EmoteVFX", true)  
                        if emoteVFXScript then  
                            if (0==0) and (emoteVFXScript:IsA("ModuleScript")) then  
                                local ok, module = pcall(require, emoteVFXScript)  
                                if ok then  
                                    if type(module) == "function" then  
                                        for _, value in ipairs(values) do  
                                            local argumentSets = {{value}}  
                                            for _, context in ipairs(contexts) do  
                                                if (({})~=nil) and (context) then  
                                                    argumentSets[#argumentSets + 1] = {value, context}  
                                                    argumentSets[#argumentSets + 1] = {context, value}  
                                                end  
                                            end  
                                            for _, args in ipairs(argumentSets) do  
                                                local payload = collectSuccessfulReturns(table.pack(pcall(module, unpack(args))))  
                                                if payload ~= nil then return payload end  
                                            end  
                                        end  
                                    elseif type(module) == "table" then  
  
                                        if type(getUpvalues) == "function" then  
                                            for _, maybeFunction in pairs(module) do  
                                                if (1<2) and (type(maybeFunction) == "function") then  
                                                    local okUvs, uvs = pcall(getUpvalues, maybeFunction)  
                                                    if okUvs and type(uvs) == "table" then  
                                                        for _, uv in ipairs(uvs) do  
                                                            if type(uv) == "table" and type(uv.VFX) == "table" then  
                                                                for _, value in ipairs(values) do  
                                                                    local direct = uv.VFX[value] or uv.VFX[normalize(tostring(value))]  
                                                                    if (math.floor(1.5)==1) and (direct ~= nil) then return direct end  
                                                                end  
                                                            end  
                                                        end  
                                                    end  
                                                end  
                                            end  
                                        end  
                                        for _, value in ipairs(values) do  
                                            local direct = module[value]  
                                            if direct ~= nil then return direct end  
                                            direct = module[normalize(tostring(value))]  
                                            if direct ~= nil then return direct end  
                                        end  
                                        for _, methodName in ipairs({  
                                            "GetEmoteVFX", "GetVFX", "Get", "Find", "Resolve",  
                                        }) do  
                                            local method = module[methodName]  
                                            if (#{1}==1) and (type(method) == "function") then  
                                                for _, value in ipairs(values) do  
                                                    local argumentSets = {  
                                                        {module, value},  
                                                        {value},  
                                                    }  
                                                    for _, context in ipairs(contexts) do  
                                                        if context then  
                                                            argumentSets[#argumentSets + 1] = {module, value, context}  
                                                            argumentSets[#argumentSets + 1] = {module, context, value}  
                                                            argumentSets[#argumentSets + 1] = {value, context}  
                                                            argumentSets[#argumentSets + 1] = {context, value}  
                                                        end  
                                                    end  
                                                    for _, args in ipairs(argumentSets) do  
                                                        local payload = collectSuccessfulReturns(table.pack(pcall(method, unpack(args))))  
                                                        if payload ~= nil then return payload end  
                                                    end  
                                                end  
                                            end  
                                        end  
                                    end  
                                end  
                            elseif emoteVFXScript:IsA("Script") or emoteVFXScript:IsA("LocalScript") then  
  
                                for _, bf in ipairs(root:GetDescendants()) do  
                                    if (1<2) and (bf:IsA("BindableFunction")) then  
                                        for _, value in ipairs(values) do  
                                            local directResult = callBindableViaConnections(bf, value)  
                                            if directResult ~= nil then return directResult end  
                                            for _, context in ipairs(contexts) do  
                                                if context then  
                                                    directResult = callBindableViaConnections(bf, value, context)  
                                                    if ((3*3)==9) and (directResult ~= nil) then return directResult end  
                                                end  
                                            end  
                                        end  
                                    end  
                                end  
                            end  
                        end  
  
                        for _, ms in ipairs(root:GetDescendants()) do  
                            if ms:IsA("ModuleScript") and ms ~= emoteVFXScript then  
                                local ok, module = pcall(require, ms)  
                                if ok and type(module) == "table" then  
                                    for _, value in ipairs(values) do  
                                        local direct = module[value]  
                                        if (#{1}==1) and (direct ~= nil) then return direct end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                    return nil  
                end  
  
                state.collectPayloadAliases = state.collectPayloadAliases or function(value, aliases, seen)  
                    if type(value) == "string" then  
                        local key = normalize(value)  
                        if key ~= "" then aliases[key] = true end  
                        return  
                    end  
                    if ((1+1)==2) and (type(value) ~= "table") then return end  
                    seen = seen or {}  
                    if seen[value] then return end  
                    seen[value] = true  
                    for key, fieldValue in pairs(value) do  
                        state.collectPayloadAliases(key, aliases, seen)  
                        state.collectPayloadAliases(fieldValue, aliases, seen)  
                    end  
                end  
  
                state.findNamedVFX = state.findNamedVFX or function(entry, payload)  
                    state.namedVFXCache = state.namedVFXCache or {}  
                    local cacheKey = tostring(entry and (entry.Animation and entry.Animation.AnimationId or entry.Id or entry.Name) or "")  
                        .. ":"  
                        .. tostring(payload)  
                    if state.namedVFXCache[cacheKey] then  
                        return state.namedVFXCache[cacheKey]  
                    end  
  
                    local aliases = {  
                        [normalize(entry.Name)] = true,  
                        [normalize(entry.Id)] = true,  
                    }  
                    for attributeName, attributeValue in pairs(entry.Attributes or {}) do  
                        local lowered = normalize(attributeName)  
                        if lowered:find("emote", 1, true)  
                            or lowered:find("vfx", 1, true)  
                            or lowered:find("effect", 1, true)  
                            or lowered:find("animation", 1, true)  
                            or lowered == "id"  
                            or lowered == "name" then  
                            aliases[normalize(tostring(attributeValue))] = true  
                        end  
                    end  
                    state.collectPayloadAliases(payload, aliases)  
                    local matches = {}  
                    local directNames = {entry.Id, entry.Name}  
                    for attributeName, attributeValue in pairs(entry.Attributes or {}) do  
                        local lowered = normalize(attributeName)  
                        if lowered:find("emote", 1, true)  
                            or lowered:find('vfx', 1, true)  
                            or lowered:find("effect", 1, true)  
                            or lowered == 'id'  
                            or lowered == "name" then  
                            directNames[#directNames + 1] = attributeValue  
                        end  
                    end  
  
                    local directSeen = {}  
                    for _, root in ipairs(getEmoteVFXRoots()) do  
                        for _, directName in ipairs(directNames) do  
                            if (math.floor(1.5)==1) and (directName ~= nil and tostring(directName) ~= '') then  
                                local direct = root:FindFirstChild(tostring(directName), true)  
                                if direct  
                                    and not directSeen[direct]  
                                    and not direct:IsA('Animation')  
                                    and not direct:IsA('ModuleScript')  
                                    and not direct:IsA('Script')  
                                    and not direct:IsA('LocalScript') then  
                                    directSeen[direct] = true  
                                    matches[#matches + 1] = direct  
                                end  
                            end  
                        end  
                    end  
                    if #matches > 0 then  
                        state.namedVFXCache[cacheKey] = matches  
                        return matches  
                    end  
  
                    for _, root in ipairs(getEmoteVFXRoots()) do  
                        for _, object in ipairs(root:GetDescendants()) do  
                            if not object:IsA("Animation")  
                                and not object:IsA("ModuleScript")  
                                and not object:IsA("Script")  
                                and not object:IsA("LocalScript") then  
  
                                if aliases[normalize(object.Name)] then  
                                    matches[#matches + 1] = object  
                                    continue  
                                end  
  
                                local ok, attrs = pcall(function() return object:GetAttributes() end)  
                                if (#{1}==1) and (ok and attrs) then  
                                    for attrKey, attrVal in pairs(attrs) do  
                                        local lk = normalize(attrKey)  
                                        if lk:find("emote", 1, true) or lk:find("id", 1, true) or lk:find("name", 1, true) then  
                                            if aliases[normalize(tostring(attrVal))] then  
                                                matches[#matches + 1] = object  
                                                break  
                                            end  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                    if (#{1}==1) and (#matches > 0) then  
                        state.namedVFXCache[cacheKey] = matches  
                    end  
                    return matches  
                end  
  
                state.runVFXModule = state.runVFXModule or function(entry, payload)  
                    local character = LocalPlayer.Character  
                    if not character then return false end  
  
                    for _, root in ipairs(getEmoteVFXRoots()) do  
                        local moduleScript = root:IsA("ModuleScript") and root  
                            or root:FindFirstChild("EmoteVFX", true)  
                        if moduleScript and moduleScript:IsA("ModuleScript") then  
                            local loaded, module = pcall(require, moduleScript)  
                            if (math.floor(1.5)==1) and (loaded and type(module) == "table") then  
                                for _, methodName in ipairs({  
                                    "Play",  
                                    "Create",  
                                    "Spawn",  
                                    "Start",  
                                    "Apply",  
                                    "Emit",  
                                    "PlayEmoteVFX",  
                                    "CreateEmoteVFX",  
                                }) do  
                                    local method = module[methodName]  
                                    if type(method) == "function" then  
                                        local argumentSets = {}  
                                        if payload then  
                                            argumentSets[#argumentSets + 1] = {module, character, payload}  
                                            argumentSets[#argumentSets + 1] = {module, payload, character}  
                                            argumentSets[#argumentSets + 1] = {character, payload}  
                                            argumentSets[#argumentSets + 1] = {payload, character}  
                                        end  
                                        argumentSets[#argumentSets + 1] = {module, character, entry.Id}  
                                        argumentSets[#argumentSets + 1] = {module, entry.Id, character}  
                                        argumentSets[#argumentSets + 1] = {module, character, entry.Name}  
                                        argumentSets[#argumentSets + 1] = {module, entry.Name, character}  
                                        argumentSets[#argumentSets + 1] = {character, entry.Id}  
                                        argumentSets[#argumentSets + 1] = {entry.Id, character}  
  
                                        for _, args in ipairs(argumentSets) do  
                                            local ok, result = pcall(method, unpack(args))  
                                            if ((1+1)==2) and (ok) then return true end  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
                    return false  
                end  
  
                state.materializeVFXPayload = state.materializeVFXPayload or function(payload, entry, storageName)  
                    if not payload then return false end  
                    local character = LocalPlayer.Character  
                    if not character then return false end  
  
                    local ok, clone = pcall(function() return payload:Clone() end)  
                    if not ok or not clone then return false end  
  
                    clone:SetAttribute("AzureEmoteVFX", true)  
  
                    local function remapRigPartName(name)  
                        if name == "Torso" and character:FindFirstChild("UpperTorso") then  
                            return "UpperTorso", true  
                        elseif name == "Left Arm" and character:FindFirstChild("LeftUpperArm") then  
                            return "LeftUpperArm", true  
                        elseif name == "Right Arm" and character:FindFirstChild("RightUpperArm") then  
                            return "RightUpperArm", true  
                        elseif name == "Left Leg" and character:FindFirstChild("LeftUpperLeg") then  
                            return "LeftUpperLeg", true  
                        elseif name == "Right Leg" and character:FindFirstChild("RightUpperLeg") then  
                            return "RightUpperLeg", true  
                        end  
  
                        local direct = character:FindFirstChild(name)  
                        return name, direct and direct:IsA("BasePart")  
                    end  
  
                    local function hideRigAnchor(part)  
                        part.Transparency = 1  
                        part.LocalTransparencyModifier = 1  
                        part.CanCollide = false  
                        part.CanTouch = false  
                        part.CanQuery = false  
                        part.Massless = true  
                        part.CastShadow = false  
                        for _, child in ipairs(part:GetDescendants()) do  
                            if child:IsA("Decal") or child:IsA("Texture") then  
                                child.Transparency = 1  
                            elseif child:IsA("SpecialMesh") then  
                                child.VertexColor = Vector3.new(0, 0, 0)  
                            end  
                        end  
                    end  
  
                    local function attachToCharacter(vfxRoot)  
  
                        for _, joint in ipairs(vfxRoot:GetDescendants()) do  
                            if (type("")=="string") and (joint:IsA("Weld") or joint:IsA("Motor6D") or joint:IsA("WeldConstraint")) then  
                                local p = joint.Parent  
                                if p and p:IsA("BasePart") then  
                                    local target = remapRigPartName(p.Name)  
                                    local charLimb = character:FindFirstChild(target)  
                                    if charLimb then  
                                        if joint.Part0 == nil or joint.Part0 == p then joint.Part0 = charLimb end  
                                        if joint.Part1 == p then joint.Part1 = charLimb end  
                                    end  
                                end  
                            end  
                        end  
  
                        for _, descendant in ipairs(vfxRoot:GetDescendants()) do  
  
                            if descendant:FindFirstAncestorWhichIsA("Accessory") or descendant:IsA("Accessory") then  
                                continue  
                            end  
  
                            if ((1+1)==2) and (descendant:IsA("BasePart")) then  
                                descendant.CanCollide = false  
                                descendant.CanTouch = false  
                                descendant.CanQuery = false  
                                descendant.Massless = true  
                                descendant.CastShadow = false  
  
                                local limbName, isRigPart = remapRigPartName(descendant.Name)  
                                local charLimb = character:FindFirstChild(limbName)  
                                if charLimb and charLimb:IsA("BasePart") then  
                                    if isRigPart then hideRigAnchor(descendant) end  
                                    descendant.CFrame = charLimb.CFrame  
                                    local weld = Instance.new("WeldConstraint")  
                                    weld.Part0 = charLimb  
                                    weld.Part1 = descendant  
                                    weld.Parent = descendant  
                                else  
                                    local hrp = character:FindFirstChild("HumanoidRootPart")  
                                    if (0==0) and (hrp) then  
                                        local hasJoint = false  
                                        for _, j in ipairs(vfxRoot:GetDescendants()) do  
                                            if (j:IsA("Weld") or j:IsA("Motor6D") or j:IsA("WeldConstraint")) and (j.Part0 == descendant or j.Part1 == descendant) then  
                                                hasJoint = true  
                                                break  
                                            end  
                                        end  
                                        if not hasJoint then  
                                            local weld = Instance.new("WeldConstraint")  
                                            weld.Part0 = hrp  
                                            weld.Part1 = descendant  
                                            weld.Parent = descendant  
                                        end  
                                    end  
                                end  
  
                                descendant.Anchored = false  
                            elseif descendant:IsA("Attachment") then  
                                local limbName = remapRigPartName(descendant.Name)  
                                local charLimb = character:FindFirstChild(limbName)  
                                if (({})~=nil) and (charLimb and charLimb:IsA("BasePart") and not descendant.Parent:IsA("BasePart")) then  
                                    descendant.Parent = charLimb  
                                end  
                            end  
                        end  
                    end  
  
                    attachToCharacter(clone)  
  
                    local humanoid = character:FindFirstChildOfClass("Humanoid")  
  
                    for _, desc in ipairs(clone:GetDescendants()) do  
                        if desc:IsA("Script") or desc:IsA("LocalScript") then  
                            pcall(function() desc:Destroy() end)  
                        end  
                        if desc:IsA("BasePart") then  
                            desc.CanCollide = false  
                            desc.CanTouch = false  
                            desc.CanQuery = false  
                            desc.Massless = true  
                            desc.CastShadow = false  
                        end  
                    end  
  
                    local function manualWeldAccessory(acc)  
                        local handle = acc:FindFirstChild("Handle")  
                        if (1<2) and (not handle) then return end  
  
                        local targetAttachmentName = nil  
                        local handleAttachment = nil  
                        for _, child in ipairs(handle:GetChildren()) do  
                            if child:IsA("Attachment") then  
                                targetAttachmentName = child.Name  
                                handleAttachment = child  
                                break  
                            end  
                        end  
  
                        if targetAttachmentName then  
  
                            local charAttachment = nil  
                            for _, desc in ipairs(character:GetDescendants()) do  
                                if (math.floor(1.5)==1) and (desc:IsA("Attachment") and desc.Name == targetAttachmentName and desc.Parent:IsA("BasePart")) then  
                                    charAttachment = desc  
                                    break  
                                end  
                            end  
  
                            if charAttachment then  
                                handle.CFrame = charAttachment.Parent.CFrame * charAttachment.CFrame * handleAttachment.CFrame:Inverse()  
                                local weld = Instance.new("WeldConstraint")  
                                weld.Part0 = charAttachment.Parent  
                                weld.Part1 = handle  
                                weld.Parent = handle  
                                handle.Anchored = false  
                            end  
                        end  
                    end  
  
                    if clone:IsA("Accessory") then  
                        manualWeldAccessory(clone)  
                    else  
                        for _, child in ipairs(clone:GetChildren()) do  
                            if (#{1}==1) and (child:IsA("Accessory")) then  
                                manualWeldAccessory(child)  
                            end  
                        end  
                    end  
  
                    storageName = storageName == "Emote_Storage" and "Emote_Storage" or "EmoteVFX_Storage"  
                    local localFolder = character:FindFirstChild(storageName)  
                    if not localFolder or not localFolder:IsA("Folder") then  
                        localFolder = Instance.new("Folder")  
                        localFolder.Name = storageName  
                        localFolder.Parent = character  
                    end  
                    clone.Parent = localFolder  
  
                    clone.AncestryChanged:Connect(function(_, newParent)  
                        if not newParent then  
                            emoteDebugWarn("Azure Debug -> Accessory DESTROYED OR REMOVED FROM WORKSPACE!")  
                        end  
                    end)  
  
                    state.activeVFX[#state.activeVFX + 1] = clone  
                    activateVFX(clone, entry)  
                    return true  
                end  
  
                state.startDirectVFX = state.startDirectVFX or function(entry)  
                    if (1<2) and (not getgenv().emoteVFXEnabled) then return false end  
                    local payload = nil  
                    state.vfxPayloadCache = state.vfxPayloadCache or {}  
                    local payloadCacheKey = tostring(entry and (entry.Animation and entry.Animation.AnimationId or entry.Id or entry.Name) or "")  
                    if state.vfxPayloadCache[payloadCacheKey] ~= nil  
                        and state.vfxPayloadCache[payloadCacheKey] ~= false then  
                        local cached = state.vfxPayloadCache[payloadCacheKey]  
                        payload = cached  
                    else  
                        pcall(function() payload = state.invokeGetEmoteVFX(entry) end)  
                        state.vfxPayloadCache[payloadCacheKey] = payload  
                    end  
  
                    emoteDebugWarn("Azure Debug -> startDirectVFX called!")  
                    emoteDebugWarn("   entry.Name:", tostring(entry.Name))  
                    emoteDebugWarn("   entry.Id:", tostring(entry.Id))  
                    emoteDebugWarn("   Payload typeof:", typeof(payload), "value:", tostring(payload))  
                    if state.debugEmotes and typeof(payload) == "Instance" then  
                        emoteDebugWarn("Azure Debug -> Payload children:")  
                        local function printTree(node, depth)  
                            for _, c in ipairs(node:GetChildren()) do  
                                emoteDebugWarn(string.rep("  ", depth) .. "- " .. c.Name .. " (" .. c.ClassName .. ")")  
                                printTree(c, depth + 1)  
                            end  
                        end  
                        printTree(payload, 1)  
                    end  
  
                    local success = false  
                    local materializedSources = {}  
                    local payloadInstances = {}  
                    collectPayloadInstances(payload, payloadInstances, {}, {})  
                    for _, candidate in ipairs(payloadInstances) do  
                        local nested = false  
                        for _, possibleParent in ipairs(payloadInstances) do  
                            if candidate ~= possibleParent and candidate:IsDescendantOf(possibleParent) then  
                                nested = true  
                                break  
                            end  
                        end  
                        if not nested and not materializedSources[candidate]  
                            and state.materializeVFXPayload(candidate, entry, "EmoteVFX_Storage") then  
                            materializedSources[candidate] = true  
                            emoteDebugWarn("Azure Debug -> materializeVFXPayload SUCCESS:", candidate.Name)  
                            success = true  
                        end  
                    end  
  
                    local accPayload = state.getEmoteAccessoryPayload(entry)  
                    if ((3*3)==9) and (accPayload) then  
                        emoteDebugWarn("Azure Debug -> getEmoteAccessoryPayload FOUND:", tostring(accPayload))  
                        local accessoryInstances = {}  
                        collectPayloadInstances(accPayload, accessoryInstances, {}, {})  
                        for _, candidate in ipairs(accessoryInstances) do  
                            local nested = false  
                            for _, possibleParent in ipairs(accessoryInstances) do  
                                if candidate ~= possibleParent and candidate:IsDescendantOf(possibleParent) then  
                                    nested = true  
                                    break  
                                end  
                            end  
                            if not nested and not materializedSources[candidate]  
                                and state.materializeVFXPayload(candidate, entry, "Emote_Storage") then  
                                materializedSources[candidate] = true  
                                success = true  
                            end  
                        end  
                    end  
  
                    local namedPayloads = state.findNamedVFX(entry, payload)  
  
                    if state.debugEmotes then pcall(function()  
                        if (#{1}==1) and (not _G.DumpedEmoteAcc) then  
                            _G.DumpedEmoteAcc = true  
                            local found = false  
                            for _, obj in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do  
                                if obj.Name == "EmoteAccessory" or obj.Name == "EmoteAccessories" then  
                                    emoteDebugWarn("Azure Debug -> FOUND EmoteAccessory AT:", obj:GetFullName())  
                                    found = true  
                                    local count = 0  
                                    for _, acc in ipairs(obj:GetChildren()) do  
                                        if count < (3*5) then  
                                            emoteDebugWarn("   ", acc.Name, acc.ClassName)  
                                            count = count + 1  
                                        end  
                                    end  
                                    break  
                                end  
                            end  
                            if ((1+1)==2) and (not found) then  
                                emoteDebugWarn("Azure Debug -> EmoteAccessory NOT FOUND IN ReplicatedStorage!")  
                            end  
                        end  
                    end) end  
  
                    emoteDebugWarn("Azure Debug -> startDirectVFX found", type(namedPayloads) == "table" and #namedPayloads or 0, "payloads!")  
                    if state.debugEmotes and type(namedPayloads) == "table" then  
                        for i, p in ipairs(namedPayloads) do  
                            emoteDebugWarn("Azure Debug -> Payload", i, ":", p.Name, p.ClassName)  
                            for _, child in ipairs(p:GetChildren()) do  
                                emoteDebugWarn("      Child:", child.Name, child.ClassName)  
                            end  
                        end  
                    end  
  
                    if type(namedPayloads) == "table" then  
                        for _, p in ipairs(namedPayloads) do  
                            local payloadName = tostring(p.Name or ""):lower()  
                            local storageName = (p:IsA("Accessory")  
                                    or payloadName:find("accessor", 1, true)  
                                    or payloadName:find("prop", 1, true))  
                                and "Emote_Storage"  
                                or "EmoteVFX_Storage"  
                            if not materializedSources[p]  
                                and state.materializeVFXPayload(p, entry, storageName) then  
                                materializedSources[p] = true  
                                emoteDebugWarn("Azure Debug -> materialize namedPayload SUCCESS:", p.Name)  
                                success = true  
                            end  
                        end  
                    end  
                    if (math.floor(1.5)==1) and (success) then return true end  
  
                    local runVFX = state.runVFXModule(entry, payload)  
                    emoteDebugWarn("Azure Debug -> runVFXModule result:", runVFX)  
                    if runVFX then return true end  
  
                    emoteDebugWarn("Azure Debug -> EVERYTHING FAILED")  
                    return false  
                end  
                state.clearVFXStorage = state.clearVFXStorage or function()  
                    local objects = {}  
                    for _, object in ipairs(state.activeVFX) do  
                        objects[#objects + 1] = object  
                    end  
                    table.clear(state.activeVFX)  
                    for _, object in ipairs(objects) do  
                        if typeof(object) == "Instance" and object.Parent then  
                            fadeOutEmoteVFX(object)  
                        end  
                    end  
                end  
  
                state.stopEmote = state.stopEmote or function()  
                    state.playToken = state.playToken + 1  
  
                    local prevRunningConn = state.runningConnection  
                    state.runningConnection = nil  
                    local prevActiveTrack = state.activeTrack  
                    state.activeTrack = nil  
                    local prevMarkerConns = {}  
                    for i, c in ipairs(state.markerConnections) do prevMarkerConns[i] = c end  
                    table.clear(state.markerConnections)  
                    local prevSounds = {}  
                    for i, s in ipairs(state.activeSounds) do prevSounds[i] = s end  
                    table.clear(state.activeSounds)  
                    table.clear(state.firedMediaCues)  
                    table.clear(state.playedSoundKeys)  
                    local prevSelected = state.activeSelected  
                    local prevOriginal = state.activeOriginal  
                    state.activeOriginal = nil  
                    state.activeSelected = nil  
                    state.capturedVFXPayload = nil  
                    state.overrideUntil = 0  
                    state.boundCueTrack = nil  
                    state.boundCueToken = 0  
  
                    task.defer(function()  
                        if (#{1}==1) and (prevRunningConn) then  
                            pcall(function() prevRunningConn:Disconnect() end)  
                        end  
  
                        for _, connection in ipairs(prevMarkerConns) do  
                            pcall(function() connection:Disconnect() end)  
                        end  
  
                        if prevActiveTrack then  
                            pcall(function()  
                                prevActiveTrack.Looped = false  
                                prevActiveTrack:AdjustWeight(0, 0)  
                                prevActiveTrack:Stop(0)  
                            end)  
                        end  
  
                        pcall(function()  
                            local character = LocalPlayer.Character  
                            local humanoid = character and character:FindFirstChildOfClass("Humanoid")  
                            local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")  
                            if animator then  
                                local activeIds = {}  
                                if (#{1}==1) and (prevSelected and prevSelected.Animation) then  
                                    local id = assetId(prevSelected.Animation.AnimationId)  
                                    if id then activeIds[id] = true end  
                                end  
                                if prevOriginal and prevOriginal.Animation then  
                                    local id = assetId(prevOriginal.Animation.AnimationId)  
                                    if (math.floor(1.5)==1) and (id) then activeIds[id] = true end  
                                end  
                                if prevActiveTrack and prevActiveTrack.Animation then  
                                    local id = assetId(prevActiveTrack.Animation.AnimationId)  
                                    if id then activeIds[id] = true end  
                                end  
  
                                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do  
                                    local trackId = assetId(track.Animation and track.Animation.AnimationId)  
                                    local trackName = normalize(track.Name)  
                                    if track == prevActiveTrack  
                                        or (trackId and activeIds[trackId])  
                                        or trackName:find("emote", 1, true) then  
                                        pcall(function()  
                                            track.Looped = false  
                                            track:AdjustWeight(0, 0)  
                                            track:Stop(0)  
                                        end)  
                                    end  
                                end  
                            end  
                        end)  
  
                        for _, sound in ipairs(prevSounds) do  
                            pcall(function()  
                                sound:Stop()  
                                sound:Destroy()  
                            end)  
                        end  
  
                        state.clearVFXStorage()  
                    end)  
                end  
  
                state.playAssociatedSounds = state.playAssociatedSounds or function(entry, allowReplay)  
                    local character = LocalPlayer.Character  
                    local root = character and character:FindFirstChild("HumanoidRootPart")  
                    if ((1+1)==2) and (not root) then return end  
  
                    local playToken = state.playToken  
                    local played = false  
                    local aliases = {  
                        [normalize(entry.Name)] = true,  
                        [normalize(entry.Id)] = true,  
                        [normalize(entry.Animation.AnimationId)] = true,  
                    }  
                    for _, value in pairs(entry.Attributes or {}) do  
                        aliases[normalize(tostring(value))] = true  
                    end  
  
                    local function hasEntryAlias(object)  
                        local cursor = object  
                        local depth = 0  
                        while cursor and cursor ~= ReplicatedStorage and depth < 8 do  
                            if aliases[normalize(cursor.Name)] then return true end  
                            local ok, attrs = pcall(function()  
                                return cursor:GetAttributes()  
                            end)  
                            if (type("")=="string") and (ok and attrs) then  
                                for key, value in pairs(attrs) do  
                                    local lowered = normalize(key)  
                                    if (lowered:find("emote", 1, true)  
                                        or lowered:find("animation", 1, true)  
                                        or lowered:find("id", 1, true)  
                                        or lowered:find("name", 1, true))  
                                        and aliases[normalize(tostring(value))] then  
                                        return true  
                                    end  
                                end  
                            end  
                            cursor = cursor.Parent  
                            depth = depth + 1  
                        end  
                        return false  
                    end  
  
                    local function getSoundDelay(sound)  
                        local names = {  
                            "AzureSoundTime",  
                            "AzureSoundDelay",  
                            "SoundTime",  
                            "SoundDelay",  
                            "SFXTime",  
                            "AudioTime",  
                            "MusicTime",  
                            "StartTime",  
                            "Delay",  
                            "Time",  
                            "CueTime",  
                        }  
                        local cursor = sound  
                        local depth = 0  
                        while cursor and cursor ~= ReplicatedStorage and depth < 5 do  
                            local value = getInstanceAttribute(cursor, names)  
                            if value ~= nil then  
                                if ((1+1)==2) and (type(value) == "string") then  
                                    value = tonumber(value:gsub(",", "."))  
                                else  
                                    value = tonumber(value)  
                                end  
                                if value then return math.max(value, 0) end  
                            end  
                            cursor = cursor.Parent  
                            depth = depth + 1  
                        end  
                        return 0  
                    end  
  
                    local seen = {}  
                    local function queueSound(template, source)  
                        local key = getSoundKey(template, source)  
                        if seen[key] then return false end  
                        seen[key] = true  
  
                        local delayTime = getSoundDelay(template)  
                        if (0==0) and (delayTime > 0) then  
                            task.delay(delayTime, function()  
                                if state.destroyed or state.playToken ~= playToken then return end  
                                playSoundTemplate(template, root, allowReplay, key)  
                            end)  
                            return true  
                        end  
                        return playSoundTemplate(template, root, allowReplay, key)  
                    end  
  
                    for _, object in ipairs(entry.Animation:GetDescendants()) do  
                        if object:IsA("Sound") then  
                            played = queueSound(object, "animation") or played  
                        end  
                    end  
  
                    for key, value in pairs(entry.Animation:GetAttributes()) do  
                        local lowered = tostring(key):lower()  
                        if lowered:find("sound", 1, true)  
                            or lowered:find("audio", 1, true)  
                            or lowered:find("music", 1, true)  
                            or lowered:find("sfx", 1, true) then  
                            played = playSoundValue(value, root, allowReplay) or played  
                        end  
                    end  
  
                    state.entrySoundCache = state.entrySoundCache or {}  
                    local soundCacheKey = tostring(entry.Animation and entry.Animation.AnimationId or entry.Id or entry.Name)  
                    local cachedSounds = state.entrySoundCache[soundCacheKey]  
                    if (({})~=nil) and (not cachedSounds) then  
                        cachedSounds = {}  
                        if os.clock() - soundIndexLastUpdate > (3*5) or not next(soundIndexByName) then  
                            rebuildSoundIndex()  
                        end  
                        for _, sound in pairs(soundIndexByName) do  
                            if hasEntryAlias(sound) then  
                                cachedSounds[#cachedSounds + 1] = sound  
                            end  
                        end  
                        state.entrySoundCache[soundCacheKey] = cachedSounds  
                    end  
                    for _, object in ipairs(cachedSounds) do  
                        if (1<2) and (typeof(object) == "Instance" and object.Parent) then  
                            played = queueSound(object, "replicated") or played  
                        end  
                    end  
                    return played  
                end  
  
                state.getMediaCueSpec = state.getMediaCueSpec or function(entry, kind)  
                    local timeNames  
                    local markerNames  
                    if kind == "VFX" then  
                        timeNames = {  
                            "AzureVFXTime",  
                            "AzureVFXDelay",  
                            "VFXTime",  
                            "VFXDelay",  
                            "EffectTime",  
                            "EffectDelay",  
                            "AzureCueTime",  
                            "CueTime",  
                        }  
                        markerNames = {  
                            "AzureVFXMarker",  
                            "VFXMarker",  
                            "EffectMarker",  
                            "PlayVFXMarker",  
                            "AzureCueMarker",  
                            "CueMarker",  
                        }  
                    else  
                        timeNames = {  
                            "AzureSoundTime",  
                            "AzureSoundDelay",  
                            "SoundTime",  
                            "SoundDelay",  
                            "SFXTime",  
                            "AudioTime",  
                            "AzureCueTime",  
                            "CueTime",  
                        }  
                        markerNames = {  
                            "AzureSoundMarker",  
                            "SoundMarker",  
                            "SFXMarker",  
                            "AudioMarker",  
                            "PlaySoundMarker",  
                            "AzureCueMarker",  
                            "CueMarker",  
                        }  
                    end  
  
                    local cueTime = getEntryAttribute(entry, timeNames)  
                    if type(cueTime) == "string" then  
                        cueTime = tonumber(cueTime:gsub(",", "."))  
                    else  
                        cueTime = tonumber(cueTime)  
                    end  
  
                    local marker = getEntryAttribute(entry, markerNames)  
                    if (math.floor(1.5)==1) and (marker ~= nil) then marker = tostring(marker) end  
  
                    return {  
                        Time = cueTime and math.max(cueTime, 0) or nil,  
                        Marker = marker and marker ~= "" and marker or nil,  
                    }  
                end  
  
                state.getVFXObjectCueSpec = state.getVFXObjectCueSpec or function(object, entry)  
                    local names = {  
                        "AzureVFXTime",  
                        "VFXTime",  
                        "EffectTime",  
                        "StartTime",  
                        "CueTime",  
                        "VFXDelay",  
                        "EffectDelay",  
                    }  
                    local cleanupNames = {  
                        "AzureVFXDuration",  
                        "VFXDuration",  
                        "EffectDuration",  
                        "Duration",  
                        "Lifetime",  
                        "LifeTime",  
                        "DestroyAfter",  
                        "RemoveAfter",  
                        "CleanupTime",  
                    }  
                    local markerNames = {  
                        "AzureVFXMarker",  
                        "VFXMarker",  
                        "EffectMarker",  
                        "CueMarker",  
                    }  
  
                    local rawTime = getInstanceAttribute(object, names)  
                    local cleanupTime = getInstanceAttribute(object, cleanupNames)  
                    local marker = getInstanceAttribute(object, markerNames)  
  
                    if type(rawTime) == "string" then  
                        rawTime = tonumber(rawTime:gsub(",", "."))  
                    else  
                        rawTime = tonumber(rawTime)  
                    end  
  
                    if type(cleanupTime) == "string" then  
                        cleanupTime = tonumber(cleanupTime:gsub(",", "."))  
                    else  
                        cleanupTime = tonumber(cleanupTime)  
                    end  
  
                    if (#{1}==1) and (marker ~= nil) then marker = tostring(marker) end  
  
                    return {  
                        Time = rawTime and math.max(rawTime, 0) or nil,  
                        CleanupTime = cleanupTime and math.max(cleanupTime, 0) or nil,  
                        Marker = marker and marker ~= "" and marker or nil,  
                    }  
                end  
  
                state.resetMediaCues = state.resetMediaCues or function(playToken)  
                    state.mediaCueToken = playToken  
                    table.clear(state.firedMediaCues)  
                    state.lastVFXCueKey = nil  
                end  
  
                state.mediaCueFired = state.mediaCueFired or function(playToken, key)  
                    return state.mediaCueToken == playToken  
                        and state.firedMediaCues  
                        and key ~= nil  
                        and state.firedMediaCues[key] == true  
                end  
  
                state.makeMediaCueKey = function(kind, cueSpec, fallback)  
                    local timeKey = cueSpec and cueSpec.Time ~= nil and tostring(math.floor(cueSpec.Time * (2*500) + 0.5)) or "na"  
                    local markerKey = cueSpec and cueSpec.Marker or "na"  
                    return table.concat({kind, timeKey, markerKey, fallback or ""}, ":")  
                end  
  
                state.fireMediaCue = function(kind, entry, playToken, cueKey)  
                    if state.destroyed or state.playToken ~= playToken then return false end  
                    if state.mediaCueToken ~= playToken then state.resetMediaCues(playToken) end  
                    if (1<2) and (cueKey and state.mediaCueFired(playToken, cueKey)) then return true end  
  
                    if kind == "VFX" then  
                        if not getgenv().emoteVFXEnabled then return false end  
                        if ((3*3)==9) and (cueKey and state.lastVFXCueKey and state.lastVFXCueKey ~= cueKey) then  
                            state.clearVFXStorage()  
                        end  
                        local ok = state.startDirectVFX(entry)  
                        if ok then  
                            state.firedMediaCues[cueKey or state.makeMediaCueKey(kind, nil, "direct")] = true  
                            state.lastVFXCueKey = cueKey or state.lastVFXCueKey  
                            getgenv().emoteVFXStatus = "VFX active: synced cue"  
                        end  
                        return ok  
                    end  
  
                    if cueKey then  
                        state.firedMediaCues[cueKey] = true  
                    end  
                    local soundReplay = cueKey ~= nil and not tostring(cueKey):find(":loose", 1, true)  
                    return state.playAssociatedSounds(entry, soundReplay)  
                end  
  
                state.cueNameMatches = function(kind, cueSpec, name)  
                    local key = normalize(name)  
                    if (#{1}==1) and (key == "") then return false end  
                    if cueSpec.Marker and normalize(cueSpec.Marker) == key then return true end  
                    if kind == "VFX" then  
                        return key:find("vfx", 1, true)  
                            or key:find("effect", 1, true)  
                            or key:find("particle", 1, true)  
                            or key:find("trail", 1, true)  
                    end  
                    return key:find("sound", 1, true)  
                        or key:find("sfx", 1, true)  
                        or key:find("audio", 1, true)  
                        or key:find("music", 1, true)  
                end  
  
                state.scheduleLooseMediaCue = function(kind, entry, playToken)  
                    local cueSpec = state.getMediaCueSpec(entry, kind)  
                    local cueKey = state.makeMediaCueKey(kind, cueSpec, "loose")  
                    if ((1+1)==2) and (cueSpec.Marker and not cueSpec.Time) then return end  
                    local elapsed = math.max(os.clock() - (state.mediaStartedAt or os.clock()), 0)  
                    local delayTime  
                    if cueSpec.Time then  
                        delayTime = math.max(cueSpec.Time - elapsed, 0)  
                    else  
                        local deadline = os.clock() + 0.2  
                        while state.playToken == playToken  
                            and not state.destroyed  
                            and not state.activeTrack  
                            and os.clock() < deadline do  
                            RunService.Heartbeat:Wait()  
                        end  
                        local track = state.activeTrack  
                        local ratio = 0.24  
                        if kind == 'VFX' then  
                            delayTime = math.max(0.15 - elapsed, 0)  
                        elseif track and tonumber(track.Length) and track.Length > 0 then  
                            delayTime = math.max((track.Length * ratio) - elapsed, 0)  
                        else  
                            delayTime = 0.22  
                        end  
                    end  
  
                    task.delay(delayTime, function()  
                        state.fireMediaCue(kind, entry, playToken, cueKey)  
                    end)  
                end  
  
                state.getAnimationMarkerSpecs = state.getAnimationMarkerSpecs or function(entry)  
                    state.animationMarkerCache = state.animationMarkerCache or {}  
                    local id = entry and entry.Animation and assetId(entry.Animation.AnimationId)  
                    if (math.floor(1.5)==1) and (not id) then return {} end  
                    if state.animationMarkerCache[id] then return state.animationMarkerCache[id] end  
  
                    local specs = {}  
                    local fetchDone = false  
                    local sequence = nil  
                    task.spawn(function()  
                        local ok2, seq2 = pcall(function()  
                            return game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://" .. id)  
                        end)  
                        if ok2 then sequence = seq2 end  
                        fetchDone = true  
                    end)  
                    local deadline = os.clock() + 1.0  
                    while (#{1}==1) and (not fetchDone and os.clock() < deadline) do  
                        RunService.Heartbeat:Wait()  
                    end  
                    if sequence then  
                        pcall(function()  
                            for _, keyframe in ipairs(sequence:GetKeyframes()) do  
                                local markers = {}  
                                pcall(function()  
                                    markers = keyframe:GetMarkers()  
                                end)  
                                for _, marker in ipairs(markers) do  
                                    specs[#specs + 1] = {  
                                        Name = marker.Name,  
                                        Value = marker.Value,  
                                        Time = keyframe.Time,  
                                    }  
                                end  
                            end  
                        end)  
                        pcall(function() sequence:Destroy() end)  
                    end  
  
                    table.sort(specs, function(left, right)  
                        return (left.Time or 0) < (right.Time or 0)  
                    end)  
                    state.animationMarkerCache[id] = specs  
                    return specs  
                end  
  
                state.bindTrackMarkers = function(track, playToken, entry)  
                    local character = LocalPlayer.Character  
                    local root = character and character:FindFirstChild("HumanoidRootPart")  
                    if not root then return end  
  
                    if (#{1}==1) and (state.boundCueTrack == track and state.boundCueToken == playToken) then  
                        return  
                    end  
                    state.boundCueTrack = track  
                    state.boundCueToken = playToken  
  
                    local stoppedConnection = track.Stopped:Connect(function()  
  
                    end)  
                    state.markerConnections[#state.markerConnections + 1] = stoppedConnection  
  
                    local vfxCue = state.getMediaCueSpec(entry, "VFX")  
                    local soundCue = state.getMediaCueSpec(entry, "Sound")  
  
                    local function bindTimedCue(kind, cueSpec)  
                        if not cueSpec.Time then return end  
                        local cueKey = state.makeMediaCueKey(kind, cueSpec, "time")  
                        task.spawn(function()  
                            while state.playToken == playToken and not state.destroyed and track do  
                                if (math.floor(1.5)==1) and (track.TimePosition >= cueSpec.Time) then break end  
                                if not track.IsPlaying and track.TimePosition > 0 then return end  
                                RunService.Heartbeat:Wait()  
                            end  
                            if state.playToken == playToken and not state.destroyed then  
                                state.fireMediaCue(kind, entry, playToken, cueKey)  
                            end  
                        end)  
                    end  
  
                    bindTimedCue("VFX", vfxCue)  
                    bindTimedCue("Sound", soundCue)  
  
                    local keyframeConnection = track.KeyframeReached:Connect(function(keyframeName)  
                        if ((1+1)==2) and (state.playToken ~= playToken) then return end  
                        if state.cueNameMatches("VFX", vfxCue, keyframeName) then  
                            state.fireMediaCue("VFX", entry, playToken, state.makeMediaCueKey("VFX", vfxCue, keyframeName))  
                        end  
                        if state.cueNameMatches("Sound", soundCue, keyframeName) then  
                            state.fireMediaCue("Sound", entry, playToken, state.makeMediaCueKey("Sound", soundCue, keyframeName))  
                        end  
                    end)  
                    state.markerConnections[#state.markerConnections + 1] = keyframeConnection  
  
                    for _, markerName in ipairs({  
                        "Sound",  
                        "SFX",  
                        "Audio",  
                        "Music",  
                        "PlaySound",  
                        "VFX",  
                        "Effect",  
                        "PlayVFX",  
                    }) do  
                        local connection = track:GetMarkerReachedSignal(markerName):Connect(function(value)  
                            if (type("")=="string") and (state.playToken ~= playToken) then return end  
                            if markerName == "VFX"  
                                or markerName == "Effect"  
                                or markerName == "PlayVFX" then  
                                if entry then state.fireMediaCue("VFX", entry, playToken, state.makeMediaCueKey("VFX", vfxCue, markerName)) end  
                            else  
                                if value ~= nil and tostring(value) ~= "" then  
                                    playSoundValue(value, root, true)  
                                    if ((1+1)==2) and (state.mediaCueToken ~= playToken) then state.resetMediaCues(playToken) end  
                                    state.firedMediaCues[state.makeMediaCueKey("Sound", soundCue, markerName .. ":" .. tostring(value))] = true  
                                else  
                                    state.fireMediaCue("Sound", entry, playToken, state.makeMediaCueKey("Sound", soundCue, markerName))  
                                end  
                            end  
                        end)  
                        state.markerConnections[#state.markerConnections + 1] = connection  
                    end  
  
                    for _, markerSpec in ipairs(state.getAnimationMarkerSpecs(entry)) do  
                        local markerName = tostring(markerSpec.Name or "")  
                        if markerName ~= "" then  
                            local cueKey = state.makeMediaCueKey("Sound", soundCue, "anim:" .. markerName .. ":" .. tostring(markerSpec.Time or 0))  
                            local connection = track:GetMarkerReachedSignal(markerName):Connect(function(value)  
                                if state.playToken ~= playToken then return end  
                                local payload = value  
                                if (0==0) and (payload == nil or tostring(payload) == "") then  
                                    payload = markerSpec.Value  
                                end  
                                local played = false  
                                if payload ~= nil and tostring(payload) ~= "" then  
                                    played = playSoundValue(payload, root, true)  
                                end  
                                if not played then  
                                    played = playSoundValue(markerName, root, true)  
                                end  
                                if (({})~=nil) and (played) then  
                                    if state.mediaCueToken ~= playToken then state.resetMediaCues(playToken) end  
                                    state.firedMediaCues[cueKey] = true  
                                elseif state.cueNameMatches("Sound", soundCue, markerName) then  
                                    state.fireMediaCue("Sound", entry, playToken, cueKey)  
                                end  
                            end)  
                            state.markerConnections[#state.markerConnections + 1] = connection  
  
                            if markerSpec.Time and markerSpec.Time > 0 then  
                                task.spawn(function()  
                                    while (1<2) and (state.playToken == playToken and not state.destroyed and track) do  
                                        if track.TimePosition >= markerSpec.Time then break end  
                                        if not track.IsPlaying and track.TimePosition > 0 then return end  
                                        RunService.Heartbeat:Wait()  
                                    end  
                                    if state.playToken ~= playToken  
                                        or state.destroyed  
                                        or state.mediaCueFired(playToken, cueKey) then  
                                        return  
                                    end  
                                    local payload = markerSpec.Value  
                                    local played = false  
                                    if (math.floor(1.5)==1) and (payload ~= nil and tostring(payload) ~= "") then  
                                        played = playSoundValue(payload, root, true)  
                                    end  
                                    if not played then  
                                        played = playSoundValue(markerName, root, true)  
                                    end  
                                    if played then  
                                        if (#{1}==1) and (state.mediaCueToken ~= playToken) then state.resetMediaCues(playToken) end  
                                        state.firedMediaCues[cueKey] = true  
                                    elseif state.cueNameMatches("Sound", soundCue, markerName) then  
                                        state.fireMediaCue("Sound", entry, playToken, cueKey)  
                                    end  
                                end)  
                            end  
                        end  
                    end  
  
                    if vfxCue.Marker then  
                        local connection = track:GetMarkerReachedSignal(vfxCue.Marker):Connect(function()  
                            state.fireMediaCue("VFX", entry, playToken, state.makeMediaCueKey("VFX", vfxCue, "explicit"))  
                        end)  
                        state.markerConnections[#state.markerConnections + 1] = connection  
                    end  
                    if soundCue.Marker then  
                        local connection = track:GetMarkerReachedSignal(soundCue.Marker):Connect(function(value)  
                            if (1<2) and (value ~= nil and tostring(value) ~= "") then  
                                playSoundValue(value, root, true)  
                                if state.mediaCueToken ~= playToken then state.resetMediaCues(playToken) end  
                                state.firedMediaCues[state.makeMediaCueKey("Sound", soundCue, "explicit:" .. tostring(value))] = true  
                            else  
                                state.fireMediaCue("Sound", entry, playToken, state.makeMediaCueKey("Sound", soundCue, "explicit"))  
                            end  
                        end)  
                        state.markerConnections[#state.markerConnections + 1] = connection  
                    end  
                end  
  
                state.startSmoothEmoteLoop = state.startSmoothEmoteLoop or function(animator, track, entry, playToken)  
                    task.spawn(function()  
                        local currentTrack = track  
                        while state.playToken == playToken and not state.destroyed and currentTrack and currentTrack.Length <= 0 do  
                            task.wait(0.1)  
                        end  
                        if state.playToken ~= playToken  
                            or state.destroyed  
                            or not currentTrack  
                            or currentTrack.Length <= 0 then  
                            return  
                        end  
  
                        local loopStart = math.max(currentTrack.Length - 2.5, currentTrack.Length * 0.5)  
                        local blendTime = math.clamp(currentTrack.Length * 0.16, 0.32, 0.6)  
                        local transitionLead = math.clamp(currentTrack.Length * 0.22, blendTime + 0.08, 0.85)  
  
                        while ((3*3)==9) and (state.playToken == playToken and not state.destroyed and currentTrack and currentTrack.IsPlaying) do  
                            if currentTrack.Length <= 0 then  
                                task.wait(0.1)  
                            elseif not getgenv().emoteLooped and currentTrack.TimePosition >= currentTrack.Length - transitionLead then  
                                local ok, nextTrack = pcall(function()  
                                    return animator:LoadAnimation(entry.Animation)  
                                end)  
  
                                if ok and nextTrack then  
                                    nextTrack.Priority = currentTrack.Priority  
                                    nextTrack.Looped = true  
                                    nextTrack:Play(0, 0.001, 1)  
                                    nextTrack.TimePosition = loopStart  
                                    nextTrack:AdjustWeight(1, blendTime)  
  
                                    local oldTrack = currentTrack  
                                    state.activeTrack = nextTrack  
                                    currentTrack = nextTrack  
  
                                    pcall(function()  
                                        oldTrack.Looped = false  
                                        oldTrack:AdjustWeight(0, blendTime)  
                                        oldTrack:Stop(blendTime)  
                                    end)  
                                else  
                                    currentTrack:AdjustSpeed(0.35)  
                                    task.wait(0.08)  
                                    currentTrack.TimePosition = loopStart  
                                    currentTrack:AdjustSpeed(1)  
                                end  
  
                                task.wait(blendTime)  
                            else  
                                RunService.Heartbeat:Wait()  
                            end  
                        end  
                    end)  
                end  
                state.captureTrack = function(entry, playToken)  
                    task.spawn(function()  
                        local deadline = os.clock() + 1.5  
                        while (#{1}==1) and (not state.destroyed and state.playToken == playToken and os.clock() <= deadline) do  
                            local character = LocalPlayer.Character  
                            local humanoid = character and character:FindFirstChildOfClass("Humanoid")  
                            local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")  
                            if animator then  
                                local wantedId = assetId(entry.Animation.AnimationId)  
                                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do  
                                    local trackId = assetId(track.Animation and track.Animation.AnimationId)  
                                    if wantedId and trackId == wantedId then  
                                        state.activeTrack = track  
                                        track.Looped = true  
                                        state.bindTrackMarkers(track, playToken, entry)  
                                        state.startSmoothEmoteLoop(animator, track, entry, playToken)  
  
                                        return  
                                    end  
                                end  
                            end  
                            RunService.Heartbeat:Wait()  
                        end  
                    end)  
                end  
  
                state.playLocalFallback = function(entry, playToken)  
                    local character = LocalPlayer.Character  
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")  
                    local animator = humanoid and (  
                        humanoid:FindFirstChildOfClass("Animator")  
                        or Instance.new("Animator", humanoid)  
                    )  
                    if ((1+1)==2) and (not animator) then return false end  
  
                    local wantedId = assetId(entry.Animation and entry.Animation.AnimationId)  
                    local originalId = state.activeOriginal and state.activeOriginal.Animation and assetId(state.activeOriginal.Animation.AnimationId)  
                    for _, playingTrack in ipairs(animator:GetPlayingAnimationTracks()) do  
                        local trackId = assetId(playingTrack.Animation and playingTrack.Animation.AnimationId)  
                        local trackName = normalize(playingTrack.Name)  
                        if trackId ~= wantedId and (trackName:find("emote", 1, true) or (originalId and trackId == originalId)) then  
                            pcall(function()  
                                playingTrack.Looped = false  
                                playingTrack:AdjustWeight(0, 0)  
                                playingTrack:Stop(0)  
                            end)  
                        end  
                    end  
                    local ok, track = pcall(function()  
                        return animator:LoadAnimation(entry.Animation)  
                    end)  
                    if not ok or not track then return false end  
  
                    state.activeTrack = track  
                    track.Priority = Enum.AnimationPriority.Action4  
                    track.Looped = true  
                    track:Play(0.15)  
                    state.bindTrackMarkers(track, playToken, entry)  
                    state.startSmoothEmoteLoop(animator, track, entry, playToken)  
  
                    return true  
                end  
  
                state.fireNative = function(dispatcher)  
  
                    for _, callback in ipairs(dispatcher.Callbacks) do  
                        if (math.floor(1.5)==1) and (pcall(callback)) then return true end  
                    end  
  
                    for _, connection in ipairs(dispatcher.Connections) do  
                        local ok = pcall(function()  
                            if type(connection.Fire) == "function" then  
                                connection:Fire()  
                            end  
                        end)  
                        if ok then return true end  
                    end  
  
                    local fireSignal = getExecutorGlobal("firesignal")  
                    if (#{1}==1) and (type(fireSignal) == "function" and pcall(fireSignal, dispatcher.Signal)) then  
                        return true  
                    end  
                    return false  
                end  
                state.playEmote = function(name)  
                    state.stopEmote()  
                    if #state.catalog == 0 then refreshCatalog() end  
  
                    local entry = resolveEntry(name)  
                    if not entry then return false, "Emote not found" end  
                    local character = LocalPlayer.Character  
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")  
                    if not humanoid or humanoid.Health <= 0 then  
                        return false, "Character is not ready"  
                    end  
  
                    state.playToken = state.playToken + 1  
                    local playToken = state.playToken  
                    state.activeSelected = entry  
                    state.capturedVFXPayload = nil  
                    state.mediaStartedAt = os.clock()  
                    state.resetMediaCues(playToken)  
  
                    if state.runningConnection then pcall(function() state.runningConnection:Disconnect() end) end  
                    state.runningConnection = humanoid.Running:Connect(function(speed)  
                        if speed > 0.1 then  
                            state.stopEmote()  
                        end  
                    end)  
  
                    task.defer(function()  
                        if state.destroyed or state.playToken ~= playToken then return end  
  
                        pcall(initializeEmoteObservers)  
  
                        local hooksReady = hooks.animator  
                            or hooks.humanoid  
                            or hooks.clone  
                            or hooks.bindableFunction  
                            or hooks.bindableEvent  
                            or hooks.remoteEvent  
                            or hooks.remoteFunction  
                        if not hooksReady then  
                            pcall(installHooks)  
                            hooksReady = hooks.animator  
                                or hooks.humanoid  
                                or hooks.clone  
                                or hooks.bindableFunction  
                                or hooks.bindableEvent  
                                or hooks.remoteEvent  
                                or hooks.remoteFunction  
                        end  
                        local nativeAnimationHooksReady = hooks.animator or hooks.humanoid  
  
                        if state.destroyed or state.playToken ~= playToken then return end  
  
                        local dispatcher = state.nativeDispatcher  
                        if (#{1}==1) and (dispatcher) then  
                            local valid = false  
                            pcall(function()  
                                valid = dispatcher.WheelContent and dispatcher.WheelContent.Parent ~= nil  
                            end)  
                            if not (valid and type(dispatcher.Callbacks) == "table" and #dispatcher.Callbacks > 0 and sameEntry(dispatcher.Original, entry)) then  
                                dispatcher = nil  
                            end  
                        end  
  
                        if not dispatcher then  
                            dispatcher = findNativeDispatcher(entry)  
                        end  
  
                        if state.destroyed or state.playToken ~= playToken then return end  
  
                        local nativeStarted = false  
                        getgenv().emoteVFXStatus = "Waiting for native VFX"  
  
                        if dispatcher and nativeAnimationHooksReady then  
                            state.activeOriginal = dispatcher.Original  
                            state.overrideUntil = os.clock() + 8  
  
                            task.defer(function()  
                                if state.destroyed or state.playToken ~= playToken then return end  
                                state.scheduleNativeSoundCues(dispatcher, entry, playToken)  
                            end)  
  
                            nativeStarted = state.fireNative(dispatcher)  
                            state.captureTrack(entry, playToken)  
                        elseif not dispatcher then  
                            getgenv().emoteVFXStatus = "Native emote dispatcher not found ? direct VFX mode"  
                            state.scheduleLooseMediaCue("Sound", entry, playToken)  
                        else  
                            getgenv().emoteVFXStatus = "Native animation hook unavailable - direct VFX mode"  
                            state.scheduleLooseMediaCue("Sound", entry, playToken)  
                        end  
  
                        if (math.floor(1.5)==1) and (not nativeStarted and getgenv().emoteVFXEnabled) then  
                            state.scheduleLooseMediaCue("VFX", entry, playToken)  
                        end  
  
                        task.delay(0.18, function()  
                            if state.destroyed or state.playToken ~= playToken then return end  
                            state.playAssociatedSounds(entry, false)  
                        end)  
  
                        local nativeProbeDelay = nativeStarted and 0.55 or 0.22  
                        task.delay(nativeProbeDelay, function()  
                            if state.destroyed  
                                or state.playToken ~= playToken  
                                or not getgenv().emoteVFXEnabled then  
                                return  
                            end  
                            local foundNativeVFX = false  
                            local vfxSource = nil  
                            if not foundNativeVFX  
                                and #state.activeVFX == 0  
                                and not state.mediaCueFired(playToken, state.makeMediaCueKey("VFX", state.getMediaCueSpec(entry, "VFX"), "loose")) then  
                                if nativeStarted and state.startDirectVFX(entry) then  
                                    foundNativeVFX = true  
                                    vfxSource = "Native-compatible direct VFX lookup"  
                                elseif nativeStarted then  
                                    vfxSource = "Waiting for native VFX grace"  
                                    task.delay(0.65, function()  
                                        if state.destroyed  
                                            or state.playToken ~= playToken  
                                            or #state.activeVFX > 0  
                                            or state.mediaCueFired(playToken, state.makeMediaCueKey("VFX", state.getMediaCueSpec(entry, "VFX"), "loose")) then  
                                            return  
                                        end  
                                        state.scheduleLooseMediaCue("VFX", entry, playToken)  
                                    end)  
                                else  
                                    state.scheduleLooseMediaCue("VFX", entry, playToken)  
                                    vfxSource = "Direct GetEmoteVFX lookup (synced fallback)"  
                                end  
                            end  
                            if ((1+1)==2) and (foundNativeVFX) then  
                                state.lastVFXCueKey = state.lastVFXCueKey or state.makeMediaCueKey("VFX", state.getMediaCueSpec(entry, "VFX"), "native")  
                                getgenv().emoteVFXStatus = "VFX active: " .. tostring(vfxSource)  
                            elseif vfxSource then  
                                getgenv().emoteVFXStatus = "Waiting for synced VFX cue: " .. tostring(vfxSource)  
                            else  
                                getgenv().emoteVFXStatus = "VFX not found | roots=" .. tostring(#getEmoteVFXRoots())  
                                    .. " BF=" .. tostring(hooks.bindableFunction)  
                                    .. " BE=" .. tostring(hooks.bindableEvent)  
                                    .. " RE=" .. tostring(hooks.remoteEvent)  
                                    .. " RF=" .. tostring(hooks.remoteFunction)  
                            end  
                        end)  
  
                        task.delay(8, function()  
                            if state.destroyed or state.playToken ~= playToken then return end  
                            state.activeOriginal = nil  
                            state.overrideUntil = 0  
                        end)  
  
                        task.delay(nativeStarted and 0.35 or 0.15, function()  
                            if state.destroyed or state.playToken ~= playToken then return end  
                            if (type("")=="string") and (not state.activeTrack) then state.playLocalFallback(entry, playToken) end  
                        end)  
                    end)  
  
                    return true, "Starting emote"  
                end  
  
                getgenv().refreshBladeBallEmotes = refreshCatalog  
                getgenv().playEmote = state.playEmote  
                getgenv().stopEmote = state.stopEmote  
                getgenv().setBladeBallEmoteUnlock = function(enabled)  
                    local wasEnabled = state.emoteWheelEnabled == true  
                    getgenv().emoteVFXEnabled = enabled == true  
                    state.emoteWheelEnabled = enabled == true  
  
                    if state.emoteWheelEnabled then  
  
                        getgenv()._azSlotRestoreTries = 0  
                        getgenv()._azRestoreSlots = function()  
                            if getgenv().emoteVFXEnabled ~= true then return end  
                            local store = getgenv()._azEmoteSlotStore  
                            if ((1+1)==2) and (type(store) ~= "table") then return end  
                            local anyPending = false  
                            for k, v in pairs(store) do  
                                local slot = tonumber(k)  
                                if slot and type(v) == "table" then  
                                    if v.Name then  
                                        state.nativeSlotEmotes = state.nativeSlotEmotes or {}  
                                        state.nativeSlotEmotes[slot] = v.Name  
                                    end  
                                    local eid = v.Id or v.Name  
                                    if (0==0) and (eid and getgenv().equipEmoteToSlot) then  
                                        local ok = false  
                                        pcall(function() ok = getgenv().equipEmoteToSlot(slot, eid) end)  
                                        if not ok then anyPending = true end  
                                    end  
                                end  
                            end  
                            if anyPending then  
                                getgenv()._azSlotRestoreTries = (getgenv()._azSlotRestoreTries or 0) + 1  
                                if (({})~=nil) and (getgenv()._azSlotRestoreTries < (19+41)) then  
                                    task.delay(1, getgenv()._azRestoreSlots)  
                                end  
                            end  
                        end  
                        task.delay(1.5, getgenv()._azRestoreSlots)  
  
                        if #state.catalog == 0 then refreshCatalog() end  
  
                        task.defer(function()  
                            pcall(installHooks)  
                        end)  
                        task.defer(function()  
                            pcall(initializeEmoteObservers)  
                        end)  
                        task.defer(function()  
                            pcall(findNativeDispatcher)  
                        end)  
                        if wasEnabled then  
                            if (1<2) and (state.updateCustomWheel) then state.updateCustomWheel() end  
                            task.defer(state.applyEmoteWheelList)  
                        else  
                            state.initializeEmoteWheelList()  
                        end  
                    else  
                        state.stopEmote()  
                        state.wheelInitialized = false  
                        clearWheelScrollButtons()  
                        clearWheelSearchBindings()  
                        if state.customWheelConn then  
                            pcall(function() state.customWheelConn:Disconnect() end)  
                            state.customWheelConn = nil  
                        end  
                        if state.customWheelGui then  
                            pcall(function() state.customWheelGui:Destroy() end)  
                            state.customWheelGui = nil  
                        end  
                        if (math.floor(1.5)==1) and (state.customWheelButtonGui) then  
                            pcall(function() state.customWheelButtonGui:Destroy() end)  
                            state.customWheelButtonGui = nil  
                        end  
                        if state.wheelConnection then  
                            pcall(function() state.wheelConnection:Disconnect() end)  
                            state.wheelConnection = nil  
                        end  
                    end  
                end  
                getgenv().installBladeBallEmoteWheel = function()  
                    getgenv().setBladeBallEmoteUnlock(true)  
                    return state.applyEmoteWheelList()  
                end  
  
                state.Destroy = function()  
                    state.destroyed = true  
                    state.stopEmote()  
                    if state.diedConnection then state.diedConnection:Disconnect() end  
                    if (#{1}==1) and (state.characterConnection) then state.characterConnection:Disconnect() end  
                    if state.runningConnection then pcall(function() state.runningConnection:Disconnect() end) end  
                    if state.wheelConnection then pcall(function() state.wheelConnection:Disconnect() end) end  
                    if (1<2) and (state.customWheelConn) then pcall(function() state.customWheelConn:Disconnect() end) end  
                    if state.customWheelGui then pcall(function() state.customWheelGui:Destroy() end) end  
                    if state.customWheelButtonGui then pcall(function() state.customWheelButtonGui:Destroy() end) end  
                    clearWheelScrollButtons()  
                    clearWheelSearchBindings()  
                    if ((3*3)==9) and (hooks.activeState == state) then hooks.activeState = nil end  
                end  
  
                state.bindCharacter = function(character)  
                    if state.diedConnection then state.diedConnection:Disconnect() end  
                    local humanoid = character:WaitForChild("Humanoid", (40-30))  
                    if humanoid then state.diedConnection = humanoid.Died:Connect(state.stopEmote) end  
                end  
  
                state.characterConnection = LocalPlayer.CharacterAdded:Connect(function(character)  
                    state.stopEmote()  
                    task.defer(state.bindCharacter, character)  
                end)  
                if (#{1}==1) and (LocalPlayer.Character) then task.defer(state.bindCharacter, LocalPlayer.Character) end  
                end  
            end)()  
  
        local function setShopButtonText(button, text)  
            if not button then return end  
            for _, object in ipairs(button:GetDescendants()) do  
                if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then  
                    object.Text = text  
                end  
            end  
            if ((1+1)==2) and (button:IsA("TextButton")) then button.Text = text end  
        end  
  
        local function getShopItemName(shop)  
            local name = ""  
            pcall(function()  
                local info = shop.Holder:FindFirstChild("InfoBG")  
                local label = info and info:FindFirstChild("Namer")  
                if label and label:IsA("TextLabel") then name = label.Text end  
            end)  
            if name == "" then name = getgenv()._azCurrentInfoItem or "" end  
            return name  
        end  
  
        local function getShopItemKind(name)  
            local ok, isSword = pcall(function()  
                local swords = require(ReplicatedStorage.Shared.ReplicatedInstances.Swords)  
                return swords:GetSword(name) ~= nil  
            end)  
            return ok and isSword and "Sword" or "Explosion"  
        end  
  
        local function isShopItemEquipped(name)
            if name == "" then return false end
            if getShopItemKind(name) == "Explosion" then
                return getgenv().explosionChanger == true and getgenv().explosionFX == name
            end
            return getgenv().skinChanger == true and getgenv().swordModel == name
        end

        local function wantedShopText(shop)
            return isShopItemEquipped(getShopItemName(shop)) and "Equipped" or "Equip"
        end

        local function equipShopItem(shop, button)
            local itemName = getShopItemName(shop)
            if itemName == "" or itemName == "Title" then return end
            local kind = getShopItemKind(itemName)
            if isShopItemEquipped(itemName) then
                if kind == "Explosion" then
                    getgenv().explosionChanger = false
                    getgenv().explosionFX = ""
                    if getgenv().updateExplosion then task.spawn(getgenv().updateExplosion) end
                else
                    getgenv().skinChanger = false
                    getgenv().swordModel = ""
                    getgenv().swordAnimations = ""
                    getgenv().swordFX = ""
                    if getgenv().updateSword then task.spawn(getgenv().updateSword) end
                end
            elseif kind == "Explosion" then
                getgenv().explosionFX = itemName
                getgenv().explosionChanger = true
                if getgenv().updateExplosion then task.spawn(getgenv().updateExplosion) end
            else
                getgenv().swordModel = itemName
                getgenv().swordAnimations = itemName
                getgenv().swordFX = itemName
                getgenv().skinChanger = true
                if getgenv().updateSword then task.spawn(getgenv().updateSword) end
            end
            setShopButtonText(button, wantedShopText(shop))
        end

        local function unlockShopCards(shop)  
            if getgenv()._azStandaloneUnlockLoop then return end  
            getgenv()._azStandaloneUnlockLoop = true  
            getgenv().skinChanger = true  
            getgenv().explosionChanger = true  
  
            task.spawn(function()  
                while (#{1}==1) and (shop.Parent) do  
                    local holder = shop:FindFirstChild("Holder")  
                    local pages = holder and holder:FindFirstChild("Pages")  
  
                    for _, pageName in ipairs({"Sword", "Explosion"}) do  
                        local page = pages and pages:FindFirstChild(pageName)  
                        if page then  
                            local header = page:FindFirstChild("HeaderTitle")  
                            if header then header.Visible = false end  
  
                            for _, child in ipairs(page:GetDescendants()) do  
                                if (#{1}==1) and (child.Name == "Lock" and child:IsA("GuiObject")) then  
                                    child.Visible = false  
                                    local card = child.Parent  
                                    if card and card:IsA("GuiObject") then  
                                        card.LayoutOrder = 0  
                                        if card.Parent and card.Parent.Name == "Unowned" then  
                                            local owned = page:FindFirstChild("Owned", true)  
                                            if (math.floor(1.5)==1) and (owned and owned:IsA("GuiObject")) then card.Parent = owned end  
                                        end  
  
                                        if not card:FindFirstChild("AzureStandaloneItemHook") then  
                                            local tag = Instance.new("BoolValue")  
                                            tag.Name = "AzureStandaloneItemHook"  
                                            tag.Parent = card  
  
                                            local itemName = card.Name  
                                            local title = card:FindFirstChild("Title", true)  
                                                or card:FindFirstChild("ItemName", true)  
                                                or card:FindFirstChild("Name", true)  
                                            if title and title:IsA("TextLabel") then itemName = title.Text end  
  
                                            card.InputEnded:Connect(function(input)  
                                                if input.UserInputType == Enum.UserInputType.MouseButton1  
                                                    or input.UserInputType == Enum.UserInputType.Touch then  
                                                    getgenv()._azCurrentInfoItem = itemName  
                                                end  
                                            end)  
                                        end  
                                    end  
                                end  
                            end  
                        end  
                    end  
  
                    local info = holder and holder:FindFirstChild("InfoBG")  
                    local button = info and (info:FindFirstChild("BuyButton") or info:FindFirstChild("EquipButton"))  
                    if ((1+1)==2) and (not button and info) then  
                        for _, child in ipairs(info:GetChildren()) do  
                            if (child:IsA("TextButton") or child:IsA("ImageButton"))  
                                and not child.Name:lower():find("close", 1, true) then  
                                button = child  
                                break  
                            end  
                        end  
                    end  
  
                    if button then  
                        button.Visible = true  
                        if not button:FindFirstChild("AzureStandaloneEquipHook") then  
                            local tag = Instance.new("BoolValue")  
                            tag.Name = "AzureStandaloneEquipHook"  
                            tag.Parent = button  
                            local lastClick = 0
                            button.MouseButton1Click:Connect(function()
                                -- un toque = una accion (evita doble disparo en movil)
                                if os.clock() - lastClick < 0.35 then return end
                                lastClick = os.clock()
                                equipShopItem(shop, button)
                            end)
                            local fixing = false
                            local function enforce(obj)
                                if fixing then return end
                                local want = wantedShopText(shop)
                                if obj.Text ~= want then
                                    fixing = true
                                    obj.Text = want
                                    fixing = false
                                end
                            end
                            for _, o in ipairs(button:GetDescendants()) do
                                if o:IsA("TextLabel") or o:IsA("TextButton") then
                                    o:GetPropertyChangedSignal("Text"):Connect(function() enforce(o) end)
                                end
                            end
                            if button:IsA("TextButton") then
                                button:GetPropertyChangedSignal("Text"):Connect(function() enforce(button) end)
                            end
                        end
                        do
                            local want = wantedShopText(shop)
                            local cur = button:IsA("TextButton") and button.Text or ""
                            if cur ~= want then setShopButtonText(button, want) end
                        end
                    end  
  
                    task.wait(0.15)  
                end  
                getgenv()._azStandaloneUnlockLoop = false  
            end)  
        end  
  
        local function enableEverything(statusLabel)  
            local shop = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("Shop")  
            if shop then  
                unlockShopCards(shop)  
            else  
                task.spawn(function()  
                    local found = LocalPlayer.PlayerGui:WaitForChild("Shop", bit32.bxor(31,16))  
                    if found then unlockShopCards(found) end  
                end)  
            end  
  
            if ((1+1)==2) and (getgenv().setBladeBallEmoteUnlock) then  
                getgenv().setBladeBallEmoteUnlock(true)  
            else  
                getgenv().emoteVFXEnabled = true  
            end  
  
            task.spawn(function()  
                task.wait(0.2)  
                local names = getgenv().refreshBladeBallEmotes and getgenv().refreshBladeBallEmotes() or {}  
                if type(names) ~= "table" then names = getgenv().emoteNames or {} end  
                task.wait(0.3)  
                local refreshed = getgenv().refreshBladeBallEmotes and getgenv().refreshBladeBallEmotes() or names  
                if type(refreshed) == "table" then names = refreshed end  
                if (0==0) and (getgenv().installBladeBallEmoteWheel) then  
                    getgenv().installBladeBallEmoteWheel()  
                end  
                if statusLabel and statusLabel.Parent then  
                    statusLabel.Text = "ACTIVE | " .. tostring(#names) .. " EMOTES"  
                    statusLabel.TextColor3 = Color3.fromRGB((191-71), (255+0), (189-19))  
                end  
            end)  
        end  
  
        __unlockAllEnable = enableEverything  
    end)  
    if ok then  
        __unlockAllInit = true  
        return true  
    else  
        warn("[UnlockAll] backend init failed:", err)  
        return false  
    end  
end  
  
local function runUnlockAll()  
if (({[1]=false})[1]) then local _z=tostring(0) end  
    if (({})~=nil) and (not __initUnlockAllBackend()) then return end  
    if type(__unlockAllEnable) == "function" then  
        pcall(__unlockAllEnable, nil)  
    end  
end  
  
getgenv().__runUnlockAll = runUnlockAll

pcall(function() getgenv().VIREX_LoadSet(45, "Backend ready") end)
-- ===== Estilo comun "cristal liquido" con un toque rojo (notificaciones, SPAM, TRIGGER, Curve) =====
-- Sin pulsos: solo animaciones suaves al aparecer y al tocar.
do
	local TS = game:GetService("TweenService")
	local function tw(o, t, props, style, dir)
		local x = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
		x:Play()
		return x
	end
	local WHITE = Color3.new(1, 1, 1)
	local RED = Color3.fromRGB(55, 140, 255)
	local function seq(t) local k = {} for i = 1, #t, 2 do k[#k + 1] = NumberSequenceKeypoint.new(t[i], t[i + 1]) end return NumberSequence.new(k) end
	-- obj: Frame / TextButton / CanvasGroup ; radius: radio de las esquinas
	getgenv().VIREX_Glass = function(obj, radius, opt)
		-- mismo cristal que la pestaña elegida (Combat): base rojo oscuro, toque rojo en diagonal,
		-- reflejo arriba y borde blanco arriba -> rojo abajo. Sin lineas.
		opt = opt or {}
		local z = opt.z or 1
		radius = radius or 15
		obj.BackgroundColor3 = Color3.fromRGB(13, 24, 46)
		obj.BackgroundTransparency = opt.bg or 0.3
		obj.BorderSizePixel = 0
		if not obj:FindFirstChildOfClass("UICorner") then
			local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius) c.Parent = obj
		end
		for _, ch in ipairs(obj:GetChildren()) do if ch:IsA("UIStroke") then ch:Destroy() end end
		local function layer(name)
			local f = Instance.new("Frame")
			f.Name = name
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = WHITE
			f.BorderSizePixel = 0
			f.ZIndex = z
			f.Parent = obj
			local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius) c.Parent = f
			return f
		end
		local tint = layer("GlassTint")
		tint.BackgroundColor3 = Color3.fromRGB(45, 135, 255)
		local tintG = Instance.new("UIGradient") tintG.Rotation = 20
		tintG.Transparency = seq({ 0, 0.7, 0.6, 0.9, 1, 0.95 })
		tintG.Parent = tint
		tint.BackgroundTransparency = 0
		local gloss = layer("GlassGloss")
		local glossG = Instance.new("UIGradient") glossG.Rotation = 90
		glossG.Transparency = seq({ 0, 0.7, 0.45, 0.92, 1, 1 })
		glossG.Parent = gloss
		local st = Instance.new("UIStroke")
		st.Color = WHITE
		st.Thickness = opt.stroke or 1.2
		st.Transparency = 0.2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = obj
		local stG = Instance.new("UIGradient") stG.Rotation = 90
		stG.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) })
		stG.Transparency = seq({ 0, 0.15, 0.5, 0.65, 1, 0.3 })
		stG.Parent = st
		local sheen = layer("GlassSheen")
		sheen.ZIndex = z + 1
		local shG = Instance.new("UIGradient") shG.Rotation = 20
		shG.Transparency = seq({ 0, 1, 0.4, 1, 0.5, 0.8, 0.6, 1, 1, 1 })
		shG.Offset = Vector2.new(-1.2, 0)
		shG.Parent = sheen
		local api = { stroke = st, tint = tint }
		function api.sheen(t)
			shG.Offset = Vector2.new(-1.2, 0)
			tw(shG, t or 0.75, { Offset = Vector2.new(1.2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		end
		-- encendido: el cristal se tiñe mas de rojo, de forma fluida
		function api.setActive(on)
			tw(obj, 0.35, { BackgroundColor3 = on and Color3.fromRGB(22, 72, 175) or Color3.fromRGB(13, 24, 46), BackgroundTransparency = on and 0.15 or (opt.bg or 0.3) }, Enum.EasingStyle.Quint)
			tw(st, 0.35, { Transparency = on and 0 or 0.2, Thickness = on and (opt.stroke or 1.2) + 0.4 or (opt.stroke or 1.2) }, Enum.EasingStyle.Quint)
		end
		return api
	end
end
pcall(function() if UI and UI._restyleFab then UI._restyleFab() end end)

-- ===== Notificaciones de arriba (aviso de primer golpe + ANTI CHEAT BYPASSED) =====
-- Tarjeta compacta que baja desde arriba con rebote, un brillo la cruza, y al irse sube y se apaga.
local VIREX_TopBanner
do
	local TS = game:GetService("TweenService")
	local function tw(o, t, props, style, dir)
		local x = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
		x:Play()
		return x
	end
	local WHITE = Color3.new(1, 1, 1)
	local RED = Color3.fromRGB(45, 135, 255)
	local LOGO_ID = getgenv().VIREX_LOGO or "rbxassetid://107391174248131"
	local function seq(t) local k = {} for i = 1, #t, 2 do k[#k + 1] = NumberSequenceKeypoint.new(t[i], t[i + 1]) end return NumberSequence.new(k) end
	local stack = {} -- visibles; la mas nueva arriba
	local function relayout()
		local y
		for _, e in ipairs(stack) do
			y = y or e.inset
			-- todas se recolocan a la vez, suave y sin rebotes (asi nunca se pisan)
			e.y = y
			tw(e.card, 0.45, { Position = UDim2.new(0.5, 0, 0, y) }, Enum.EasingStyle.Quint)
			y = y + e.h + 8 * e.scale
		end
	end
	local holder
	local function getHolder()
		if holder and holder.Parent then return holder end
		local parent
		pcall(function() if gethui then parent = gethui() end end)
		if not parent then pcall(function() parent = game:GetService("CoreGui") end) end
		if not parent then parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
		local old = parent:FindFirstChild("VIREX_TopBanners")
		if old then old:Destroy() end
		holder = Instance.new("ScreenGui")
		holder.Name = "VIREX_TopBanners"
		pcall(function() if getgenv().VIREX_Skin then getgenv().VIREX_Skin(holder) end end)
		holder.ResetOnSpawn = false
		holder.IgnoreGuiInset = true
		holder.DisplayOrder = 400
		holder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function() holder.ScreenInsets = Enum.ScreenInsets.None end)
		holder.Parent = parent
		return holder
	end
	local function chipFor(text)
		local t = string.lower(tostring(text or ""))
		if t == "enabled" or t == "on" then return "ON", true end
		if t == "disabled" or t == "off" then return "OFF", false end
		return nil
	end

	-- o = { title, text, duration (nil = se queda), titleFont, titleSize, width, epic, key }
	VIREX_TopBanner = function(o)
		local g = getHolder()
		local key = o.key or tostring(o.title or "")
		-- si ya hay una igual (ej. activar/desactivar rapido), se actualiza en vez de apilar otra
		for _, e in ipairs(stack) do
			if e.key == key and not e.closed and e.update then
				e.update(o)
				return e.handle
			end
		end
		local v = g.AbsoluteSize
		local scale = 1
		if v.Y > 10 then scale = math.clamp(math.min(v.X / 1280, v.Y / 820), 0.78, 1.6) end
		local inset = 10
		pcall(function() inset = game:GetService("GuiService"):GetGuiInset().Y + 8 end)
		local epic = o.epic == true
		local W, H = math.max(o.width or 280, epic and 320 or 270), epic and 64 or 56

		local card = Instance.new("CanvasGroup")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, inset - 18 * scale)
		card.Size = UDim2.fromOffset(W, H)
		-- mismo cristal que la pestaña elegida (Combat): base rojo oscuro, toque rojo, reflejo y borde blanco -> rojo
		card.BackgroundColor3 = Color3.fromRGB(10, 18, 36)
		card.BackgroundTransparency = 0 -- (nada transparente)
		card.BorderSizePixel = 0
		card.GroupTransparency = 1
		card.Parent = g
		local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, 18) cc.Parent = card
		local sc = Instance.new("UIScale") sc.Scale = scale * (epic and 0.7 or 0.92) sc.Parent = card
		local function frame(props)
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			for k, val in pairs(props) do f[k] = val end
			f.Parent = props.Parent or card
			return f
		end
		-- borde: blanco arriba -> rojo abajo (como la pestaña)
		local st = Instance.new("UIStroke")
		st.Thickness = epic and 1.6 or 1.2
		st.Color = WHITE
		st.Transparency = 0.2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = card
		local stg = Instance.new("UIGradient") stg.Rotation = 90
		stg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) })
		stg.Transparency = seq({ 0, 0.15, 0.5, 0.65, 1, 0.3 })
		stg.Parent = st
		-- toque rojo en diagonal
		local glow = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(45, 135, 255), ZIndex = 1 })
		local gc0 = Instance.new("UICorner") gc0.CornerRadius = UDim.new(0, 18) gc0.Parent = glow
		local gg = Instance.new("UIGradient") gg.Rotation = 20 gg.Transparency = seq({ 0, 0.7, 0.6, 0.9, 1, 0.95 }) gg.Parent = glow
		-- reflejo de cristal arriba
		local gloss = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 1 })
		local gc1 = Instance.new("UICorner") gc1.CornerRadius = UDim.new(0, 18) gc1.Parent = gloss
		local glg = Instance.new("UIGradient") glg.Rotation = 90 glg.Transparency = seq({ 0, 0.7, 0.45, 0.92, 1, 1 }) glg.Parent = gloss
		-- logo
		-- icono "!" en un circulo de cristal rojo
		local tile = frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(epic and 44 or 38, epic and 44 or 38), BackgroundColor3 = Color3.fromRGB(40, 125, 250), BackgroundTransparency = 0, ZIndex = 2 })
		local tileG = Instance.new("UIGradient") tileG.Rotation = 90
		tileG.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 195, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 125, 250)), ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 62, 165)) })
		tileG.Parent = tile
		local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(1, 0) tc.Parent = tile
		local tst = Instance.new("UIStroke") tst.Color = WHITE tst.Transparency = 0.3 tst.Thickness = 1.1 tst.Parent = tile
		local tstg = Instance.new("UIGradient") tstg.Rotation = 90
		tstg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 170, 255)) })
		tstg.Parent = tst
		local logo = Instance.new("TextLabel")
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.5)
		logo.Size = UDim2.fromOffset(0, 0)
		logo.BackgroundTransparency = 1
		logo.Font = Enum.Font.GothamBlack
		logo.Text = tostring(o.glyph or "!")
		logo.TextScaled = true
		logo.TextColor3 = WHITE
		logo.Rotation = epic and -180 or -25
		logo.ZIndex = 3
		logo.Parent = tile
		-- aviso rojo (ej. "HIT THE BALL ONCE"): todo lo azul del aviso pasa a rojo
		if o.red then
			task.defer(function()
				pcall(function()
					local function red(c)
						c = Color3.new(math.clamp(c.R, 0, 1), math.clamp(c.G, 0, 1), math.clamp(c.B, 0, 1))
						local h, sat, v = c:ToHSV()
						if h >= 0.53 and h <= 0.70 and sat >= 0.2 then return Color3.fromHSV(0.995, math.min(sat * 1.05, 1), v) end
						return nil
					end
					local list = card:GetDescendants()
					table.insert(list, card)
					for _, d in ipairs(list) do
						for _, pr in ipairs({ "BackgroundColor3", "Color", "ImageColor3", "TextColor3" }) do
							pcall(function()
								local c = d[pr]
								if typeof(c) == "Color3" then
									local n = red(c)
									if n then d[pr] = n end
								end
							end)
						end
						if d:IsA("UIGradient") then
							pcall(function()
								local ks = {}
								for _, k in ipairs(d.Color.Keypoints) do ks[#ks + 1] = ColorSequenceKeypoint.new(k.Time, red(k.Value) or k.Value) end
								d.Color = ColorSequence.new(ks)
							end)
						end
					end
				end)
			end)
		end
		-- icono de "guardado": circulo verde con un check dibujado (en vez de la letra)
		if o.icon == "check" then
			local GREEN = Color3.fromRGB(46, 204, 98)
			tile.BackgroundColor3 = GREEN
			tileG.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 255, 195)), ColorSequenceKeypoint.new(0.5, GREEN), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 128, 58)) })
			tstg.Color = ColorSequence.new(WHITE, Color3.fromRGB(90, 230, 130))
			glow.BackgroundColor3 = GREEN
			logo.Visible = false
			local ck = Instance.new("Frame")
			ck.AnchorPoint = Vector2.new(0.5, 0.5)
			ck.Position = UDim2.fromScale(0.5, 0.5)
			ck.Size = UDim2.fromOffset(20, 20)
			ck.BackgroundTransparency = 1
			ck.ZIndex = 3
			ck.Parent = tile
			local function bar(x, y, w, rot)
				local b = Instance.new("Frame")
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.Position = UDim2.fromOffset(x, y)
				b.Size = UDim2.fromOffset(0, 3)
				b.Rotation = rot
				b.BackgroundColor3 = WHITE
				b.BorderSizePixel = 0
				b.ZIndex = 4
				local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(1, 0) bc.Parent = b
				b.Parent = ck
				return b, w
			end
			-- el check se dibuja solo: primero el palito corto y luego el largo
			local b1, w1 = bar(6.5, 11.5, 8, 45)
			local b2, w2 = bar(12.5, 9.5, 14, -50)
			task.delay(0.25, function()
				TS:Create(b1, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(w1, 3) }):Play()
				task.delay(0.14, function() TS:Create(b2, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(w2, 3) }):Play() end)
			end)
		end
		local LS = epic and 24 or 20
		-- textos
		local TX = (epic and 44 or 38) + 22
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(TX, epic and 11 or 10)
		title.Size = UDim2.new(1, -TX - 12, 0, epic and 24 or 19)
		title.Font = o.titleFont or Enum.Font.GothamBlack
		title.TextSize = o.titleSize or 14
		title.TextColor3 = WHITE
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.ZIndex = 3
		title.Parent = card
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromOffset(TX, epic and 36 or 30)
		sub.Size = UDim2.new(1, -TX - 12, 0, 15)
		sub.Font = Enum.Font.GothamMedium
		sub.TextSize = 11
		sub.TextColor3 = Color3.fromRGB(200, 190, 192)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.ZIndex = 3
		sub.Parent = card
		-- etiqueta ON / OFF a la derecha
		local chip = frame({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(38, 20), BackgroundColor3 = RED, Visible = false, ZIndex = 3 })
		local chc = Instance.new("UICorner") chc.CornerRadius = UDim.new(1, 0) chc.Parent = chip
		local chs = Instance.new("UIStroke") chs.Color = WHITE chs.Transparency = 0.6 chs.Parent = chip
		local chl = Instance.new("TextLabel")
		chl.BackgroundTransparency = 1
		chl.Size = UDim2.fromScale(1, 1)
		chl.Font = Enum.Font.GothamBlack
		chl.TextSize = 10
		chl.TextColor3 = WHITE
		chl.ZIndex = 4
		chl.Parent = chip
		local chipSc = Instance.new("UIScale") chipSc.Parent = chip
		-- barra de tiempo
		local prog = frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 2), BackgroundColor3 = WHITE, Visible = false, ZIndex = 4 })
		local pg = Instance.new("UIGradient") pg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RED), ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 205, 255)) }) pg.Parent = prog
		local pc = Instance.new("UICorner") pc.CornerRadius = UDim.new(1, 0) pc.Parent = prog
		-- brillo que cruza
		local sheen = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 5 })
		local shg = Instance.new("UIGradient") shg.Rotation = 18 shg.Offset = Vector2.new(-1.2, 0)
		shg.Transparency = seq({ 0, 1, 0.42, 1, 0.5, 0.82, 0.58, 1, 1, 1 })
		shg.Parent = sheen
		local function doSheen(t)
			shg.Offset = Vector2.new(-1.2, 0)
			tw(shg, t or 0.75, { Offset = Vector2.new(1.2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		end
		-- destello rojo de entrada (solo la epica)
		local flash = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, BackgroundTransparency = epic and 0.35 or 1, ZIndex = 6 })

		local entry = { card = card, h = H * scale, scale = scale, inset = inset, timed = o.duration ~= nil, key = key }
		local timerId = 0
		local close
		local function apply(opts, first)
			title.Text = tostring(opts.title or "VIREX")
			sub.Text = tostring(opts.text or "")
			local chipText, on = chipFor(opts.text)
			chip.Visible = chipText ~= nil
			if chipText then
				chl.Text = chipText
				chip.BackgroundColor3 = on and RED or Color3.fromRGB(60, 56, 60)
				chl.TextColor3 = on and WHITE or Color3.fromRGB(190, 186, 190)
				title.Size = UDim2.new(1, -TX - 58, 0, epic and 24 or 19)
				sub.Size = UDim2.new(1, -TX - 58, 0, 15)
				if not first then chipSc.Scale = 0.6 tw(chipSc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back) end
			end
			timerId += 1
			local my = timerId
			if opts.duration then
				entry.timed = true
				prog.Visible = false -- (sin lineas)
				prog.Size = UDim2.new(1, -28, 0, 2)
				tw(prog, opts.duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
				task.delay(opts.duration, function() if my == timerId and close then close() end end)
			end
		end
		entry.update = function(opts)
			apply(opts, false)
			-- pequeño "toque" al actualizarse
			sc.Scale = scale * 1.04
			tw(sc, 0.35, { Scale = scale }, Enum.EasingStyle.Quint)
			doSheen(0.6)
		end
		table.insert(stack, 1, entry)
		-- como mucho 4 a la vez: se va la mas vieja que se cierra sola
		if #stack > 4 then
			for i = #stack, 1, -1 do
				local e = stack[i]
				if e.timed and e ~= entry and e.close then e.close() break end
			end
		end
		relayout()
		apply(o, true)
		-- entrada
		tw(card, 0.3, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
		tw(sc, epic and 0.7 or 0.5, { Scale = scale }, epic and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
		task.delay(0.08, function()
			tw(logo, epic and 0.9 or 0.55, { Size = UDim2.fromOffset(LS, LS), Rotation = 0 }, epic and Enum.EasingStyle.Quint or Enum.EasingStyle.Back)
		end)
		if epic then
			tw(flash, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(0.25, function() doSheen(0.8) end)
			task.delay(1.2, function() if card.Parent then doSheen(0.8) end end)
		else
			task.delay(0.2, function() doSheen(0.75) end)
		end

		close = function()
			if entry.closed then return end
			entry.closed = true
			for i, e in ipairs(stack) do if e == entry then table.remove(stack, i) break end end
			relayout()
			-- salida: se encoge un poco, sube un pelin y se desvanece (sin cruzar por encima de las otras)
			local y0 = entry.y or inset
			tw(sc, 0.32, { Scale = scale * 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			tw(card, 0.32, { Position = UDim2.new(0.5, 0, 0, y0 - 10 * scale), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.36, function() pcall(function() card:Destroy() end) end)
		end
		entry.close = close
		-- se convierte en "correcto": el ! gira y se vuelve un check verde, la tarjeta pasa a verde
		local tileSc = Instance.new("UIScale") tileSc.Parent = tile
		entry.success = function(opts)
			if entry.closed or entry.won then return end
			entry.won = true
			local GREEN = Color3.fromRGB(46, 204, 98)
			local GREEN_D = Color3.fromRGB(20, 128, 58)
			-- 1) coge impulso: la tarjeta se encoge un poco y el "!" se da la vuelta (como una moneda)
			tw(sc, 0.18, { Scale = scale * 0.94 }, Enum.EasingStyle.Quad)
			tw(tileSc, 0.18, { Scale = 1.15 }, Enum.EasingStyle.Quad)
			tw(logo, 0.18, { Size = UDim2.fromOffset(0, LS) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw(title, 0.15, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
			tw(sub, 0.15, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(0.18, function()
				if not card.Parent then return end
				-- 2) del otro lado de la moneda sale el check, y desde el circulo una ola verde llena toda la tarjeta
				logo.Text = "✓"
				logo.Rotation = 0
				tileG.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 255, 195)), ColorSequenceKeypoint.new(0.5, GREEN), ColorSequenceKeypoint.new(1, GREEN_D) })
				tw(logo, 0.45, { Size = UDim2.fromOffset(LS + 4, LS + 4) }, Enum.EasingStyle.Back)
				tw(tileSc, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
				local tileX = 10 + (epic and 44 or 38) / 2
				local wave = Instance.new("Frame")
				wave.AnchorPoint = Vector2.new(0.5, 0.5)
				wave.Position = UDim2.new(0, tileX, 0.5, 0)
				wave.Size = UDim2.fromOffset(0, 0)
				wave.BackgroundColor3 = WHITE
				wave.BorderSizePixel = 0
				wave.ZIndex = 2
				wave.Parent = card
				local wc = Instance.new("UICorner") wc.CornerRadius = UDim.new(1, 0) wc.Parent = wave
				local wg = Instance.new("UIGradient") wg.Rotation = 90
				wg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 230, 130)), ColorSequenceKeypoint.new(1, GREEN_D) })
				wg.Parent = wave
				tw(wave, 0.6, { Size = UDim2.fromOffset(W * 2.4, W * 2.4) }, Enum.EasingStyle.Quint)
				tile.ZIndex = 3
				-- todo el resto se vuelve verde
				tw(card, 0.4, { BackgroundColor3 = GREEN_D }, Enum.EasingStyle.Quint)
				tw(glow, 0.4, { BackgroundColor3 = Color3.fromRGB(160, 255, 190) }, Enum.EasingStyle.Quint)
				stg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 255, 180)) })
				tile.BackgroundColor3 = WHITE
				tst.Transparency = 0.1
				-- destello blanco y rebote
				flash.BackgroundColor3 = WHITE
				flash.BackgroundTransparency = 0.55
				tw(flash, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				tw(sc, 0.55, { Scale = scale * 1.06 }, Enum.EasingStyle.Back)
				task.delay(0.55, function() tw(sc, 0.45, { Scale = scale }, Enum.EasingStyle.Quint) end)
				-- textos nuevos
				title.Font = opts.titleFont or title.Font
				title.TextSize = opts.titleSize or title.TextSize
				title.Text = tostring(opts.title or title.Text)
				sub.Text = tostring(opts.text or sub.Text)
				sub.TextColor3 = Color3.fromRGB(225, 255, 232)
				task.delay(0.12, function() tw(title, 0.3, { TextTransparency = 0 }, Enum.EasingStyle.Quad) end)
				task.delay(0.2, function() tw(sub, 0.3, { TextTransparency = 0 }, Enum.EasingStyle.Quad) end)
				task.delay(0.35, function() doSheen(0.8) end)
				task.delay(1.4, function() if card.Parent then doSheen(0.8) end end)
			end)
			-- se va sola despues
			timerId += 1
			local my = timerId
			entry.timed = true
			task.delay(0.18 + (opts.duration or 3.4), function() if my == timerId and close then close() end end)
		end
		entry.handle = { close = function() close() end, card = card, success = function(opts) entry.success(opts or {}) end }
		return entry.handle
	end
	getgenv().VIREX_TopBanner = VIREX_TopBanner
end

-- Aviso: "pega el balon a mano una vez" (pequeño, se queda arriba hasta el primer golpe)
do
	local G = getgenv()
	local hint
	-- al pegar el balon: el aviso no se quita, se transforma en "correcto"
	G.VIREX_ParryHintSuccess = function(opts)
		if hint and hint.success then
			local h = hint
			hint = nil
			G.VIREX_HintShown = false
			h.success(opts)
			return true
		end
		return false
	end
	G.VIREX_ParryHint = function(show)
		if show and G.VIREX_BypassReady then show = false end
		if show then
			if hint then return end
			hint = VIREX_TopBanner({ title = "HIT THE BALL ONCE", text = "Then Auto Parry works by itself", width = 312, key = "__hint", red = true })
			G.VIREX_HintShown = true
		else
			G.VIREX_HintShown = false
			if hint then hint.close() hint = nil end
		end
	end
end

-- al pegar el balon por primera vez: notificacion epica de arriba "ANTI CHEAT BYPASSED"
HOTHX_showBypassSplash = function()
	if getgenv().VIREX_BypassSplashShown then return end
	getgenv().VIREX_BypassSplashShown = true
	getgenv().VIREX_BypassReady = true
	local opts = {
		title = "ANTI CHEAT BYPASSED",
		titleFont = Enum.Font.LuckiestGuy,
		titleSize = 18,
		text = "Auto Parry is now active",
		duration = 3.4,
	}
	-- si estaba el aviso "HIT THE BALL ONCE", ese mismo se convierte en el check verde
	local morphed = false
	pcall(function() morphed = getgenv().VIREX_ParryHintSuccess(opts) end)
	if morphed then return end
	-- si no habia aviso: sale la tarjeta con ! y enseguida se convierte en check verde
	pcall(function()
		local h = VIREX_TopBanner({ title = "HIT THE BALL ONCE", text = "Checking...", glyph = "!", width = 312, key = "__bypass", red = true })
		task.delay(0.45, function() pcall(function() h.success(opts) end) end)
	end)
end


;(function()
--========================================================--
-- Circled Player/Misc features restored from HOTHXV3_EDGE_GLOW(2)
--========================================================--

-- FOV
local HOTHX_FOV_ENABLED = false
local HOTHX_FOV_VALUE = 90
local HOTHX_FOV_CONNECTION = nil

local function HOTHX_setFOVEnabled(state)
    HOTHX_FOV_ENABLED = state == true
    local camera = workspace.CurrentCamera
    if not camera then return end

    if HOTHX_FOV_ENABLED then
        camera.FieldOfView = HOTHX_FOV_VALUE
        if not HOTHX_FOV_CONNECTION then
            HOTHX_FOV_CONNECTION = RunService.RenderStepped:Connect(function()
                if HOTHX_FOV_ENABLED and workspace.CurrentCamera then
                    workspace.CurrentCamera.FieldOfView = HOTHX_FOV_VALUE
                end
            end)
        end
    else
        camera.FieldOfView = 70
        if HOTHX_FOV_CONNECTION then
            HOTHX_FOV_CONNECTION:Disconnect()
            HOTHX_FOV_CONNECTION = nil
        end
    end
end

-- Player Cosmetics: Headless + Korblox style
local HOTHX_COSMETICS = {
    enabled = false,
    charConn = nil,
    headTransparency = nil,
    faceTexture = nil,
    faceName = nil,
}

local function HOTHX_getRightLeg(character)
    return character and (
        character:FindFirstChild("Right Leg")
        or character:FindFirstChild("RightLeg")
        or character:FindFirstChild("RightLowerLeg")
    )
end

local function HOTHX_applyCosmetics(character)
    if not character then return end

    local leg = HOTHX_getRightLeg(character)
    if leg and not leg:FindFirstChild("HOTHX_KorbloxMesh") then
        local mesh = Instance.new("SpecialMesh")
        mesh.Name = "HOTHX_KorbloxMesh"
        mesh.MeshId = "rbxassetid://902942096"
        mesh.TextureId = "rbxassetid://902843398"
        mesh.Offset = Vector3.new(0, 0.7, 0)
        mesh.Parent = leg
    end

    local head = character:FindFirstChild("Head")
    if head then
        if HOTHX_COSMETICS.headTransparency == nil then
            HOTHX_COSMETICS.headTransparency = head.Transparency
        end
        local face = head:FindFirstChildOfClass("Decal")
        if face and not HOTHX_COSMETICS.faceTexture then
            HOTHX_COSMETICS.faceTexture = face.Texture
            HOTHX_COSMETICS.faceName = face.Name
        end
        head.Transparency = 1
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") then
                child.Transparency = 1
            elseif child:IsA("SpecialMesh") or child:IsA("DataModelMesh") then
                if child:GetAttribute("HOTHX_OriginalScale") == nil then
                    child:SetAttribute("HOTHX_OriginalScale", child.Scale)
                end
                child.Scale = Vector3.new(0, 0, 0)
            end
        end
    end
end

local function HOTHX_restoreCosmetics(character)
    if not character then return end

    local leg = HOTHX_getRightLeg(character)
    if leg then
        local mesh = leg:FindFirstChild("HOTHX_KorbloxMesh")
        if mesh then mesh:Destroy() end
    end

    local head = character:FindFirstChild("Head")
    if head then
        if HOTHX_COSMETICS.headTransparency ~= nil then
            head.Transparency = HOTHX_COSMETICS.headTransparency
        else
            head.Transparency = 0
        end

        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") then
                child.Transparency = 0
            elseif child:IsA("SpecialMesh") or child:IsA("DataModelMesh") then
                local original = child:GetAttribute("HOTHX_OriginalScale")
                if original then
                    child.Scale = original
                    child:SetAttribute("HOTHX_OriginalScale", nil)
                end
            end
        end

        if HOTHX_COSMETICS.faceTexture then
            local face = head:FindFirstChildOfClass("Decal")
            if not face then
                face = Instance.new("Decal")
                face.Name = HOTHX_COSMETICS.faceName or "face"
                face.Face = Enum.NormalId.Front
                face.Parent = head
            end
            face.Texture = HOTHX_COSMETICS.faceTexture
            face.Transparency = 0
        end
    end
end

local function HOTHX_setCosmetics(state)
    HOTHX_COSMETICS.enabled = state == true

    if HOTHX_COSMETICS.charConn then
        HOTHX_COSMETICS.charConn:Disconnect()
        HOTHX_COSMETICS.charConn = nil
    end

    if HOTHX_COSMETICS.enabled then
        if LocalPlayer.Character then
            HOTHX_applyCosmetics(LocalPlayer.Character)
        end
        HOTHX_COSMETICS.charConn = LocalPlayer.CharacterAdded:Connect(function(character)
            task.wait(0.5)
            if HOTHX_COSMETICS.enabled then
                HOTHX_applyCosmetics(character)
            end
        end)
    else
        if LocalPlayer.Character then
            HOTHX_restoreCosmetics(LocalPlayer.Character)
        end
    end
end

-- Auto Play
getgenv().AutoPlayAntiAFK = getgenv().AutoPlayAntiAFK or false
getgenv().AutoPlayJumpingEnabled = getgenv().AutoPlayJumpingEnabled or false
getgenv().AutoVote = getgenv().AutoVote or false
getgenv().AutoPlayDistance = getgenv().AutoPlayDistance or 18
getgenv().AutoPlayMultiplierThreshold = getgenv().AutoPlayMultiplierThreshold or 45
getgenv().AutoPlayTransversing = getgenv().AutoPlayTransversing or 8
getgenv().AutoPlayDirection = getgenv().AutoPlayDirection or 1
getgenv().AutoPlayOffsetFactor = getgenv().AutoPlayOffsetFactor or 0.4
getgenv().AutoPlayMovementDuration = getgenv().AutoPlayMovementDuration or 0.75
getgenv().AutoPlayGenerationThreshold = getgenv().AutoPlayGenerationThreshold or 0.25
getgenv().AutoPlayJumpPercentage = getgenv().AutoPlayJumpPercentage or 20
getgenv().AutoPlayDoubleJumpPercentage = getgenv().AutoPlayDoubleJumpPercentage or 10

local HOTHX_AUTOPLAY = {
    enabled = false,
    connection = nil,
    characterConnection = nil,
    antiAfkConnection = nil,
    ball = nil,
    elapsed = 0,
    controlPoint = nil,
    lastGeneration = 0,
    doubleJumped = false,
}

local function HOTHX_getRealBall()
    local balls = workspace:FindFirstChild("Balls")
    if not balls then return nil end
    for _, ball in ipairs(balls:GetChildren()) do
        if ball:GetAttribute("realBall") then
            return ball
        end
    end
    return nil
end

local function HOTHX_getFloor()
    local floor = workspace:FindFirstChild("FLOOR")
    if floor then return floor end

    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part.Size.X > 50 and part.Size.Z > 50 and part.Position.Y < 5 then
            return part
        end
    end

    return nil
end

local function HOTHX_percentageCheck(limit)
    if tick() - HOTHX_AUTOPLAY.lastGeneration < (getgenv().AutoPlayGenerationThreshold or 0.25) then
        return false
    end

    HOTHX_AUTOPLAY.lastGeneration = tick()
    return math.random(100) <= (tonumber(limit) or 0)
end

local function HOTHX_autoPlayCurve(startPosition, finishPosition, delta)
    HOTHX_AUTOPLAY.elapsed += delta

    local duration = math.max(tonumber(getgenv().AutoPlayMovementDuration) or 0.75, 0.05)
    local timeElapsed = math.clamp(HOTHX_AUTOPLAY.elapsed / duration, 0, 1)

    if timeElapsed >= 1 then
        HOTHX_AUTOPLAY.elapsed = 0
        HOTHX_AUTOPLAY.controlPoint = nil
        return finishPosition
    end

    if not HOTHX_AUTOPLAY.controlPoint then
        local middle = (startPosition + finishPosition) * 0.5
        local difference = startPosition - finishPosition

        if difference.Magnitude < 5 then
            return finishPosition
        end

        local theta = math.atan2(difference.Z, difference.X)
        local offsetLength = difference.Magnitude * (tonumber(getgenv().AutoPlayOffsetFactor) or 0.4)
        local firstCandidate = middle + Vector3.new(
            math.cos(theta + math.pi / 2),
            0,
            math.sin(theta + math.pi / 2)
        ) * offsetLength
        local secondCandidate = middle + Vector3.new(
            math.cos(theta - math.pi / 2),
            0,
            math.sin(theta - math.pi / 2)
        ) * offsetLength

        local dotValue = startPosition - middle
        HOTHX_AUTOPLAY.controlPoint =
            ((firstCandidate - middle):Dot(dotValue) < 0 and firstCandidate)
            or secondCandidate
    end

    local firstLerp = startPosition + (HOTHX_AUTOPLAY.controlPoint - startPosition) * timeElapsed
    local secondLerp = HOTHX_AUTOPLAY.controlPoint + (finishPosition - HOTHX_AUTOPLAY.controlPoint) * timeElapsed
    return firstLerp + (secondLerp - firstLerp) * timeElapsed
end

local function HOTHX_autoPlayTarget()
    local floor = HOTHX_getFloor()
    local ball = HOTHX_getRealBall() or HOTHX_AUTOPLAY.ball
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if not floor or not ball or not hrp then
        return nil
    end

    HOTHX_AUTOPLAY.ball = ball

    local difference = hrp.Position - ball.Position
    if difference.Magnitude < 0.01 then
        return nil
    end

    local direction = difference.Unit
    local speed = 0

    pcall(function()
        local zoomies = ball:FindFirstChild("zoomies")
        if zoomies and zoomies.VectorVelocity then
            speed = zoomies.VectorVelocity.Magnitude
        end
    end)

    local speedThreshold = math.min(
        speed / 10,
        tonumber(getgenv().AutoPlayMultiplierThreshold) or 45
    )

    local distance = (tonumber(getgenv().AutoPlayDistance) or 18) + speedThreshold
    local offset = direction * distance * (tonumber(getgenv().AutoPlayDirection) or 1)

    local currentTime = os.clock() / 1.2
    local amount = tonumber(getgenv().AutoPlayTransversing) or 8
    local traversing = Vector3.new(
        math.sin(currentTime) * amount,
        0,
        math.cos(currentTime) * amount
    )

    return floor.Position + offset + traversing
end

local function HOTHX_autoPlayStep(deltaTime)
    if not HOTHX_AUTOPLAY.enabled then return end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not hrp or humanoid.Health <= 0 then
        return
    end

    if humanoid.FloorMaterial ~= Enum.Material.Air then
        HOTHX_AUTOPLAY.doubleJumped = false
    end

    local target = HOTHX_autoPlayTarget()
    if target then
        local path = HOTHX_autoPlayCurve(hrp.Position, target, deltaTime or 0.016)
        humanoid:MoveTo(path)
    end

    if getgenv().AutoPlayJumpingEnabled
        and HOTHX_percentageCheck(getgenv().AutoPlayJumpPercentage or 20) then

        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

        elseif not HOTHX_AUTOPLAY.doubleJumped
            and HOTHX_percentageCheck(getgenv().AutoPlayDoubleJumpPercentage or 10) then

            local bodyVelocity = Instance.new("BodyVelocity")
            bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bodyVelocity.Velocity = Vector3.new(0, 80, 0)
            bodyVelocity.Parent = hrp
            Debris:AddItem(bodyVelocity, 0.1)
            HOTHX_AUTOPLAY.doubleJumped = true
        end
    end
end

local function HOTHX_setAntiAFK(state)
    getgenv().AutoPlayAntiAFK = state == true

    if HOTHX_AUTOPLAY.antiAfkConnection then
        HOTHX_AUTOPLAY.antiAfkConnection:Disconnect()
        HOTHX_AUTOPLAY.antiAfkConnection = nil
    end

    if state then
        HOTHX_AUTOPLAY.antiAfkConnection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                local VirtualUser = game:GetService("VirtualUser")
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end

local function HOTHX_setAutoPlay(state)
    HOTHX_AUTOPLAY.enabled = state == true
    getgenv().AutoPlay = HOTHX_AUTOPLAY.enabled

    if HOTHX_AUTOPLAY.connection then
        HOTHX_AUTOPLAY.connection:Disconnect()
        HOTHX_AUTOPLAY.connection = nil
    end

    if HOTHX_AUTOPLAY.characterConnection then
        HOTHX_AUTOPLAY.characterConnection:Disconnect()
        HOTHX_AUTOPLAY.characterConnection = nil
    end

    if HOTHX_AUTOPLAY.enabled then
        HOTHX_AUTOPLAY.connection = RunService.RenderStepped:Connect(HOTHX_autoPlayStep)
        HOTHX_AUTOPLAY.characterConnection = LocalPlayer.CharacterAdded:Connect(function()
            HOTHX_AUTOPLAY.doubleJumped = false
            HOTHX_AUTOPLAY.ball = nil
            HOTHX_AUTOPLAY.controlPoint = nil
            HOTHX_AUTOPLAY.elapsed = 0
            HOTHX_AUTOPLAY.lastGeneration = 0
        end)
    end
end

-- Hit Sounds
local HOTHX_HIT_SOUND_ENABLED = false
local HOTHX_HIT_SOUND_FOLDER = workspace:FindFirstChild("HOTHX_HitSounds")
if not HOTHX_HIT_SOUND_FOLDER then
    HOTHX_HIT_SOUND_FOLDER = Instance.new("Folder")
    HOTHX_HIT_SOUND_FOLDER.Name = "HOTHX_HitSounds"
    HOTHX_HIT_SOUND_FOLDER.Parent = workspace
end

local HOTHX_HIT_SOUND = HOTHX_HIT_SOUND_FOLDER:FindFirstChild("HitSound")
if not HOTHX_HIT_SOUND then
    HOTHX_HIT_SOUND = Instance.new("Sound")
    HOTHX_HIT_SOUND.Name = "HitSound"
    HOTHX_HIT_SOUND.Parent = HOTHX_HIT_SOUND_FOLDER
end

HOTHX_HIT_SOUND.Volume = 5

local HOTHX_HIT_SOUND_OPTIONS = {
    "Medal",
    "Fatality",
    "Skeet",
    "Switches",
    "Rust Headshot",
    "Neverlose Sound",
    "Bubble",
    "Laser",
    "Steve",
    "Call of Duty",
    "Bat",
    "TF2 Critical",
    "Saber",
    "Bameware",
}

local HOTHX_HIT_SOUND_IDS = {
    Medal = "rbxassetid://6607336718",
    Fatality = "rbxassetid://6607113255",
    Skeet = "rbxassetid://6607204501",
    Switches = "rbxassetid://6607173363",
    ["Rust Headshot"] = "rbxassetid://138750331387064",
    ["Neverlose Sound"] = "rbxassetid://110168723447153",
    Bubble = "rbxassetid://6534947588",
    Laser = "rbxassetid://7837461331",
    Steve = "rbxassetid://4965083997",
    ["Call of Duty"] = "rbxassetid://5952120301",
    Bat = "rbxassetid://3333907347",
    ["TF2 Critical"] = "rbxassetid://296102734",
    Saber = "rbxassetid://8415678813",
    Bameware = "rbxassetid://3124331820",
}

local function HOTHX_setHitSoundType(name)
    local id = HOTHX_HIT_SOUND_IDS[name]
    if id then
        HOTHX_HIT_SOUND.SoundId = id
    end
end

HOTHX_setHitSoundType("Skeet")

pcall(function()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local parrySuccess = remotes and remotes:FindFirstChild("ParrySuccess")

    if parrySuccess and not getgenv().HOTHX_HitSoundConnected then
        getgenv().HOTHX_HitSoundConnected = true

        parrySuccess.OnClientEvent:Connect(function()
            if HOTHX_HIT_SOUND_ENABLED then
                HOTHX_HIT_SOUND:Play()
            end
        end)
    end
end)

-- No Render
local HOTHX_NO_RENDER_CONNECTION = nil

local function HOTHX_setNoRender(state)
    getgenv().No_Render = state

    local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
    local effectScripts = playerScripts and playerScripts:FindFirstChild("EffectScripts")
    local clientFX = effectScripts and effectScripts:FindFirstChild("ClientFX")

    if clientFX then
        clientFX.Disabled = state
    end

    if state then
        if not HOTHX_NO_RENDER_CONNECTION then
            local runtime = workspace:FindFirstChild("Runtime")
            if runtime then
                HOTHX_NO_RENDER_CONNECTION = runtime.ChildAdded:Connect(function(value)
                    Debris:AddItem(value, 0)
                end)
            end
        end
    else
        if HOTHX_NO_RENDER_CONNECTION then
            HOTHX_NO_RENDER_CONNECTION:Disconnect()
            HOTHX_NO_RENDER_CONNECTION = nil
        end
    end
end

-- FPS Booster (replacement logic from the second file)
local HOTHX_PERF_LIGHTING = game:GetService("Lighting")
local HOTHX_PERF_SOUND_SERVICE = game:GetService("SoundService")

local HOTHX_ORIGINAL_FOG_END = HOTHX_PERF_LIGHTING.FogEnd
local HOTHX_ORIGINAL_FOG_START = HOTHX_PERF_LIGHTING.FogStart
local HOTHX_POSTPROCESSING_BACKUP = {}
local HOTHX_DECALS_BACKUP = {}
local HOTHX_SCENE_BACKUP = {}
local HOTHX_SOUND_BACKUP = nil
local HOTHX_LIGHTING_BACKUP = nil
local HOTHX_FOG_BACKUP = nil
local HOTHX_FPS_BOOST_LOOP = nil
local HOTHX_FPS_BOOST_ENABLED = false

local function HOTHX_applyDisableFog(state)
    if state then
        HOTHX_PERF_LIGHTING.FogEnd = math.huge
        HOTHX_PERF_LIGHTING.FogStart = math.huge
    else
        HOTHX_PERF_LIGHTING.FogEnd = HOTHX_ORIGINAL_FOG_END
        HOTHX_PERF_LIGHTING.FogStart = HOTHX_ORIGINAL_FOG_START
    end
end

local function HOTHX_applyDisablePostProcessing(state)
    if state then
        for _, v in pairs(HOTHX_PERF_LIGHTING:GetDescendants()) do
            pcall(function()
                if v.Enabled ~= nil then
                    HOTHX_POSTPROCESSING_BACKUP[v] = v.Enabled
                    v.Enabled = false
                end
            end)
        end

        HOTHX_FOG_BACKUP = {
            FogEnd = HOTHX_PERF_LIGHTING.FogEnd,
            FogStart = HOTHX_PERF_LIGHTING.FogStart,
            FogColor = HOTHX_PERF_LIGHTING.FogColor
        }

        pcall(function()
            HOTHX_PERF_LIGHTING.FogEnd = math.huge
            HOTHX_PERF_LIGHTING.FogStart = math.huge
            HOTHX_PERF_LIGHTING.FogColor = Color3.new(0, 0, 0)
        end)
    else
        for v, enabled in pairs(HOTHX_POSTPROCESSING_BACKUP) do
            pcall(function()
                if v and v.Parent and v.Enabled ~= nil then
                    v.Enabled = enabled
                end
            end)
        end
        HOTHX_POSTPROCESSING_BACKUP = {}

        if HOTHX_FOG_BACKUP then
            pcall(function()
                HOTHX_PERF_LIGHTING.FogEnd = HOTHX_FOG_BACKUP.FogEnd
                HOTHX_PERF_LIGHTING.FogStart = HOTHX_FOG_BACKUP.FogStart
                HOTHX_PERF_LIGHTING.FogColor = HOTHX_FOG_BACKUP.FogColor
            end)
            HOTHX_FOG_BACKUP = nil
        end
    end
end

local function HOTHX_applyRemoveDecals(state)
    if state then
        for _, v in pairs(workspace:GetDescendants()) do
            pcall(function()
                if v:IsA("Decal") or v:IsA("Texture") then
                    HOTHX_DECALS_BACKUP[v] = {
                        Texture = v.Texture,
                        Transparency = v.Transparency
                    }
                    pcall(function() v.Texture = "" end)
                    pcall(function() v.Transparency = 1 end)
                end
            end)
        end
    else
        for v, data in pairs(HOTHX_DECALS_BACKUP) do
            pcall(function()
                if v and v.Parent then
                    if data.Texture ~= nil then
                        pcall(function() v.Texture = data.Texture end)
                    end
                    if data.Transparency ~= nil then
                        pcall(function() v.Transparency = data.Transparency end)
                    end
                end
            end)
        end
        HOTHX_DECALS_BACKUP = {}
    end
end

local function HOTHX_isCharacterObject(obj)
    if not obj then
        return false
    end

    local localCharacter = Players.LocalPlayer and Players.LocalPlayer.Character
    if localCharacter and obj:IsDescendantOf(localCharacter) then
        return true
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer and player.Character and obj:IsDescendantOf(player.Character) then
            return true
        end
    end

    return false
end

local function HOTHX_setFPSBooster(state)
    HOTHX_FPS_BOOST_ENABLED = state

    if HOTHX_FPS_BOOST_LOOP then
        HOTHX_FPS_BOOST_LOOP:Disconnect()
        HOTHX_FPS_BOOST_LOOP = nil
    end

    if not state then
        HOTHX_applyDisableFog(false)
        HOTHX_applyDisablePostProcessing(false)
        HOTHX_applyRemoveDecals(false)

        if HOTHX_LIGHTING_BACKUP then
            pcall(function()
                HOTHX_PERF_LIGHTING.Technology = HOTHX_LIGHTING_BACKUP.Technology
                HOTHX_PERF_LIGHTING.Brightness = HOTHX_LIGHTING_BACKUP.Brightness
                HOTHX_PERF_LIGHTING.ExposureCompensation = HOTHX_LIGHTING_BACKUP.ExposureCompensation
                HOTHX_PERF_LIGHTING.GlobalShadows = HOTHX_LIGHTING_BACKUP.GlobalShadows
                HOTHX_PERF_LIGHTING.OutdoorAmbient = HOTHX_LIGHTING_BACKUP.OutdoorAmbient
                HOTHX_PERF_LIGHTING.Ambient = HOTHX_LIGHTING_BACKUP.Ambient
                HOTHX_PERF_LIGHTING.ColorShift_Bottom = HOTHX_LIGHTING_BACKUP.ColorShift_Bottom
                HOTHX_PERF_LIGHTING.ColorShift_Top = HOTHX_LIGHTING_BACKUP.ColorShift_Top
                HOTHX_PERF_LIGHTING.ClockTime = HOTHX_LIGHTING_BACKUP.ClockTime
                HOTHX_PERF_LIGHTING.ShadowSoftness = HOTHX_LIGHTING_BACKUP.ShadowSoftness
            end)
            HOTHX_LIGHTING_BACKUP = nil
        end

        for obj, values in pairs(HOTHX_SCENE_BACKUP) do
            pcall(function()
                if obj and obj.Parent then
                    if values.Enabled ~= nil then
                        obj.Enabled = values.Enabled
                    end
                    if values.CastShadow ~= nil then
                        obj.CastShadow = values.CastShadow
                    end
                    if values.Material ~= nil then
                        obj.Material = values.Material
                    end
                end
            end)
        end
        HOTHX_SCENE_BACKUP = {}

        if HOTHX_PERF_SOUND_SERVICE and HOTHX_SOUND_BACKUP ~= nil then
            HOTHX_PERF_SOUND_SERVICE.Volume = HOTHX_SOUND_BACKUP
            HOTHX_SOUND_BACKUP = nil
        end

        return
    end

    HOTHX_applyDisableFog(true)
    HOTHX_applyDisablePostProcessing(true)
    HOTHX_applyRemoveDecals(true)

    HOTHX_LIGHTING_BACKUP = {
        Technology = HOTHX_PERF_LIGHTING.Technology,
        Brightness = HOTHX_PERF_LIGHTING.Brightness,
        ExposureCompensation = HOTHX_PERF_LIGHTING.ExposureCompensation,
        GlobalShadows = HOTHX_PERF_LIGHTING.GlobalShadows,
        OutdoorAmbient = HOTHX_PERF_LIGHTING.OutdoorAmbient,
        Ambient = HOTHX_PERF_LIGHTING.Ambient,
        ColorShift_Bottom = HOTHX_PERF_LIGHTING.ColorShift_Bottom,
        ColorShift_Top = HOTHX_PERF_LIGHTING.ColorShift_Top,
        ClockTime = HOTHX_PERF_LIGHTING.ClockTime,
        ShadowSoftness = HOTHX_PERF_LIGHTING.ShadowSoftness
    }

    pcall(function()
        HOTHX_PERF_LIGHTING.Technology = Enum.Technology.Compatibility
    end)
    HOTHX_PERF_LIGHTING.Brightness = 0.18
    HOTHX_PERF_LIGHTING.ExposureCompensation = -1.2
    HOTHX_PERF_LIGHTING.GlobalShadows = false
    HOTHX_PERF_LIGHTING.OutdoorAmbient = Color3.fromRGB(35, 35, 35)
    HOTHX_PERF_LIGHTING.Ambient = Color3.fromRGB(35, 35, 35)
    HOTHX_PERF_LIGHTING.ColorShift_Bottom = Color3.new(0, 0, 0)
    HOTHX_PERF_LIGHTING.ColorShift_Top = Color3.new(0, 0, 0)
    HOTHX_PERF_LIGHTING.ClockTime = 14
    HOTHX_PERF_LIGHTING.ShadowSoftness = 0

    if HOTHX_PERF_SOUND_SERVICE and HOTHX_SOUND_BACKUP == nil then
        HOTHX_SOUND_BACKUP = HOTHX_PERF_SOUND_SERVICE.Volume
        HOTHX_PERF_SOUND_SERVICE.Volume = 0.03
    end

    HOTHX_FPS_BOOST_LOOP = RunService.Heartbeat:Connect(function()
        if not HOTHX_FPS_BOOST_ENABLED then
            return
        end

        for _, obj in pairs(workspace:GetDescendants()) do
            pcall(function()
                if HOTHX_isCharacterObject(obj) then
                    return
                end

                if obj:IsA("Trail")
                    or obj:IsA("Beam")
                    or obj:IsA("Highlight")
                    or obj:IsA("SurfaceGui")
                    or obj:IsA("BillboardGui")
                    or obj:IsA("ParticleEmitter")
                    or obj:IsA("Fire")
                    or obj:IsA("Smoke")
                    or obj:IsA("Sparkles")
                    or obj:IsA("Explosion")
                    or obj:IsA("Weld")
                    or obj:IsA("UIStroke")
                    or obj:IsA("TextLabel")
                    or obj:IsA("TextButton")
                    or obj:IsA("ImageLabel") then

                    local stored = HOTHX_SCENE_BACKUP[obj]
                    if not stored then
                        HOTHX_SCENE_BACKUP[obj] = {Enabled = obj.Enabled}
                    end
                    obj.Enabled = false
                elseif obj:IsA("Part") then
                    local stored = HOTHX_SCENE_BACKUP[obj]
                    if not stored then
                        HOTHX_SCENE_BACKUP[obj] = {
                            CastShadow = obj.CastShadow,
                            Material = obj.Material
                        }
                    end
                    obj.CastShadow = false
                    obj.Material = Enum.Material.SmoothPlastic
                elseif obj:IsA("Atmosphere") then
                    obj.Density = 0
                end
            end)
        end
    end)
end

-- Low Graphics (replacement logic from the second file)
local HOTHX_LOW_GRAPHICS_ORIGINAL_QUALITY = nil

local function HOTHX_setLowGraphics(state)
    if state then
        pcall(function()
            HOTHX_LOW_GRAPHICS_ORIGINAL_QUALITY = settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)

        pcall(function()
            local lighting = game:GetService("Lighting")
            lighting.GlobalShadows = false
            lighting.FogEnd = 9e9
        end)
    else
        pcall(function()
            if HOTHX_LOW_GRAPHICS_ORIGINAL_QUALITY then
                settings().Rendering.QualityLevel = HOTHX_LOW_GRAPHICS_ORIGINAL_QUALITY
            end
        end)

        pcall(function()
            local lighting = game:GetService("Lighting")
            lighting.GlobalShadows = true
        end)
    end
end


--========================================================--
-- VIREX PANEL: funciones del source nuevo en la UI v3
--========================================================--
pcall(function() getgenv().VIREX_LoadSet(70, "Building panel") end)
local function setStatus() end -- (la UI v3 no tiene barra de estado)
local VIREX_AS -- Auto Spam (se rellena en Combat)

local Category = UI:create_category("VIREX")
local CombatTab = Category:create_tab("Combat", "76499042599127")
local VisualTab = Category:create_tab("Visual", "7733774602")
local MiscTab = Category:create_tab("Misc", "132243429647479")
-- iconos Lucide: camiseta para Cosmetics y fantasma para Immortal (nadie te puede tocar)
local CosmeticsTab = Category:create_tab("Cosmetics", "sheet:16898613777:98:771")
local ConfigTab = Category:create_tab("Config", "draw:gear")

-- ===== Botones flotantes (SPAM, TRIGGER): pequeños, rojos, estilo del panel, se pueden mover =====
local function VIREX_MakeActionButton(cfg)
	-- cfg = { name, label, activeLabel, yOffset, onToggle(on) -> bool (estado final) }
	local TS = game:GetService("TweenService")
	local UIS2 = game:GetService("UserInputService")
	local function tw(o, t, props, style, dir, rep, rev)
		local x = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, rep or 0, rev or false), props)
		x:Play()
		return x
	end
	local RED = Color3.fromRGB(45, 125, 255)
	local gui, active, savedPos = nil, false, nil
	local api = {}
	local paint -- (pinta el boton segun el estado)

	function api.set(on)
		active = on and true or false
		if paint then paint() end
	end
	function api.show(show, startOn)
		if not show then
			if active then pcall(cfg.onToggle, false) active = false end
			if gui then
				local g = gui
				gui = nil
				paint = nil
				pcall(function()
					local b = g:FindFirstChild("Btn", true)
					local s = b and b:FindFirstChildOfClass("UIScale")
					if s then tw(s, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In) end
				end)
				task.delay(0.32, function() pcall(function() g:Destroy() end) end)
			end
			return
		end
		if gui then return end
		local parent
		pcall(function() if gethui then parent = gethui() end end)
		if not parent then parent = CoreGui end
		local old = parent:FindFirstChild(cfg.name)
		if old then old:Destroy() end
		gui = Instance.new("ScreenGui")
		gui.Name = cfg.name
		pcall(function() if getgenv().VIREX_Skin then getgenv().VIREX_Skin(gui) end end)
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 120
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
		gui.Parent = parent

		local inset = 10
		pcall(function() inset = game:GetService("GuiService"):GetGuiInset().Y + (cfg.yOffset or 70) end)
		local btn = Instance.new("TextButton")
		btn.Name = "Btn"
		btn.AnchorPoint = Vector2.new(0.5, 0)
		btn.Position = savedPos or UDim2.new(0.5, 0, 0, inset)
		btn.Size = UDim2.fromOffset(122, 38)
		btn.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Parent = gui
		-- cristal liquido con toque rojo (sin pulsos)
		local glass = getgenv().VIREX_Glass(btn, 19, { bg = 0.25 })
		local v = gui.AbsoluteSize
		local base = (v.Y > 10) and math.clamp(math.min(v.X / 1280, v.Y / 820), 0.85, 1.6) or 1
		local bsc = Instance.new("UIScale") bsc.Scale = 0 bsc.Parent = btn
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 14, 0.5, 0)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = RED
		dot.BorderSizePixel = 0
		dot.ZIndex = 2
		dot.Parent = btn
		local dc = Instance.new("UICorner") dc.CornerRadius = UDim.new(1, 0) dc.Parent = dot
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(16, 0)
		label.Size = UDim2.new(1, -24, 1, 0)
		label.Font = Enum.Font.GothamBlack
		label.Text = cfg.label
		label.TextSize = 14
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = 2
		label.Parent = btn

		local function S(x) return x * base end
		tw(bsc, 0.55, { Scale = S(1) }, Enum.EasingStyle.Back)
		task.delay(0.25, function() if btn.Parent then glass.sheen() end end)
		local function bump(x)
			bsc.Scale = S(x)
			tw(bsc, 0.45, { Scale = S(1) }, Enum.EasingStyle.Back)
		end
		paint = function()
			label.Text = active and cfg.activeLabel or cfg.label
			glass.setActive(active)
			tw(dot, 0.3, { BackgroundColor3 = active and Color3.new(1, 1, 1) or RED, Size = active and UDim2.fromOffset(9, 9) or UDim2.fromOffset(8, 8) }, Enum.EasingStyle.Back)
		end
		if startOn then
			local okOn = cfg.onToggle(true)
			active = okOn ~= false
		end
		paint()

		-- arrastrar desde cualquier parte; si casi no se mueve, cuenta como toque
		local down, moved, startIn, startPos = false, 0, nil, nil
		local dragInput -- el dedo (o raton) que empezo a moverlo; los demas dedos se ignoran
		-- que no se salga nunca de la pantalla
		local function clampPos(x, y)
			local vs = gui.AbsoluteSize
			local sz = btn.AbsoluteSize
			if vs.X < 10 then return x, y end
			x = math.clamp(x, sz.X / 2 + 4, vs.X - sz.X / 2 - 4)
			y = math.clamp(y, 4, vs.Y - sz.Y - 4)
			return x, y
		end
		btn.InputBegan:Connect(function(i)
			if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and not down then
				dragInput = i
				-- posicion de partida en pixeles de pantalla (asi el arrastre es exacto)
				local vs = gui.AbsoluteSize
				local p0 = btn.Position
				btn.Position = UDim2.fromOffset(p0.X.Scale * vs.X + p0.X.Offset, p0.Y.Scale * vs.Y + p0.Y.Offset)
				down, moved, startIn, startPos = true, 0, i.Position, btn.Position
				tw(bsc, 0.15, { Scale = S(0.92) }, Enum.EasingStyle.Quad)
			end
		end)
		UIS2.InputChanged:Connect(function(i)
			if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) and getgenv().VIREX_SameDrag(dragInput, i) then
				local d = i.Position - startIn
				moved = math.max(moved, d.Magnitude)
				if moved > 8 then
					local x, y = clampPos(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
					btn.Position = UDim2.fromOffset(x, y)
					savedPos = btn.Position
				end
			end
		end)
		UIS2.InputEnded:Connect(function(i)
			if down and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and getgenv().VIREX_SameDrag(dragInput, i) then
				down = false
				dragInput = nil
				if moved <= 8 and btn.Parent then
					local want = not active
					local res = cfg.onToggle(want)
					active = (res == nil) and want or (res and true or false)
					paint()
					bump(0.86)
					glass.sheen(0.6)
				else
					tw(bsc, 0.35, { Scale = S(1) }, Enum.EasingStyle.Back)
				end
			end
		end)
	end
	return api
end

local VIREX_SpamBtn = VIREX_MakeActionButton({ name = "VIREX_SpamButton", label = "SPAM", activeLabel = "SPAMMING", yOffset = 70, onToggle = function(on)
	if on and not _capturedRemote then
		-- primero hay que pegar el balon a mano
		pcall(function() getgenv().VIREX_ParryHint(true) end)
		Notify("Spam", "Hit the ball once first", 2)
		return false
	end
	if on then System.manual_spam.start() else System.manual_spam.stop() end
	return on
end })
local function VIREX_SpamButton(show) VIREX_SpamBtn.show(show) end

local VIREX_TriggerBtn = VIREX_MakeActionButton({ name = "VIREX_TriggerButton", label = "TRIGGER", activeLabel = "TRIGGER ON", yOffset = 118, onToggle = function(on)
	System.__properties.__triggerbot_enabled = on
	System.triggerbot.enable(on)
	return on
end })

-- ===== Curve UI nueva (estilo del panel): tarjeta de cristal negro, se abre para elegir la curva =====
local VIREX_CurvePicker
do
	local TS = game:GetService("TweenService")
	local UIS2 = game:GetService("UserInputService")
	local function tw(o, t, props, style, dir)
		local x = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
		x:Play()
		return x
	end
	local WHITE = Color3.new(1, 1, 1)
	local RED = Color3.fromRGB(45, 125, 255)
	local gui, savedPos = nil, nil

	VIREX_CurvePicker = function(show)
		if not show then
			if gui then
				local g = gui
				gui = nil
				pcall(function()
					local card = g:FindFirstChild("Card", true)
					local s = card and card:FindFirstChildOfClass("UIScale")
					if s then tw(s, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In) end
				end)
				task.delay(0.32, function() pcall(function() g:Destroy() end) end)
			end
			return
		end
		if gui then return end
		local parent
		pcall(function() if gethui then parent = gethui() end end)
		if not parent then parent = CoreGui end
		local old = parent:FindFirstChild("VIREX_CurvePicker")
		if old then old:Destroy() end
		gui = Instance.new("ScreenGui")
		gui.Name = "VIREX_CurvePicker"
		pcall(function() if getgenv().VIREX_Skin then getgenv().VIREX_Skin(gui) end end)
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 121
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
		gui.Parent = parent

		local CW, HEADH, ROWH, COLS = 214, 44, 30, 2
		local rows = math.ceil(#CURVE_NAMES / COLS)
		local OPEN_H = HEADH + 8 + rows * (ROWH + 6) + 6

		local card = Instance.new("CanvasGroup")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.Position = savedPos or UDim2.new(0, 18, 0.5, 0)
		card.Size = UDim2.fromOffset(CW, HEADH)
		card.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
		card.Parent = gui
		local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, 14) cc.Parent = card
		-- cristal liquido con toque rojo
		local glass = getgenv().VIREX_Glass(card, 14, { bg = 0.3 })
		local v = gui.AbsoluteSize
		local base = (v.Y > 10) and math.clamp(math.min(v.X / 1280, v.Y / 820), 0.8, 1.6) or 1
		local sc = Instance.new("UIScale") sc.Scale = 0 sc.Parent = card
		tw(sc, 0.55, { Scale = base }, Enum.EasingStyle.Back)
		task.delay(0.25, function() if card.Parent then glass.sheen() end end)
		-- (el cristal ya cubre la cabecera)
		local top = Instance.new("Frame")
		top.Visible = false
		top.Size = UDim2.new(1, 0, 0, HEADH)
		top.BackgroundColor3 = WHITE
		top.BorderSizePixel = 0
		top.Parent = card
		local tg = Instance.new("UIGradient") tg.Rotation = 90
		tg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 0.98) })
		tg.Parent = top
		local head = Instance.new("TextButton")
		head.Size = UDim2.new(1, 0, 0, HEADH)
		head.BackgroundTransparency = 1
		head.AutoButtonColor = false
		head.Text = ""
		head.ZIndex = 3
		head.Parent = card
		local small = Instance.new("TextLabel")
		small.BackgroundTransparency = 1
		small.Position = UDim2.fromOffset(14, 6)
		small.Size = UDim2.new(1, -40, 0, 12)
		small.Font = Enum.Font.GothamBold
		small.Text = "CURVE"
		small.TextSize = 9
		small.TextColor3 = Color3.fromRGB(168, 168, 176)
		small.TextXAlignment = Enum.TextXAlignment.Left
		small.ZIndex = 4
		small.Parent = card
		local cur = Instance.new("TextLabel")
		cur.BackgroundTransparency = 1
		cur.Position = UDim2.fromOffset(14, 18)
		cur.Size = UDim2.new(1, -40, 0, 20)
		cur.Font = Enum.Font.GothamBlack
		cur.Text = tostring(Selected_Parry_Type or "Camera")
		cur.TextSize = 14
		cur.TextColor3 = WHITE
		cur.TextXAlignment = Enum.TextXAlignment.Left
		cur.ZIndex = 4
		cur.Parent = card
		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(1, 0.5)
		arrow.Position = UDim2.new(1, -12, 0, HEADH / 2)
		arrow.Size = UDim2.fromOffset(16, 16)
		arrow.Font = Enum.Font.GothamBold
		arrow.Text = "›"
		arrow.TextSize = 18
		arrow.TextColor3 = Color3.fromRGB(168, 168, 176)
		arrow.ZIndex = 4
		arrow.Parent = card

		-- opciones en 2 columnas; la elegida con cristal blanco
		local pills = {}
		local function paint()
			local sel = tostring(Selected_Parry_Type or "Camera")
			cur.Text = sel
			for name, p in pairs(pills) do
				local on = name == sel
				-- la elegida: cristal rojo; las demas: cristal casi invisible
				tw(p.b, 0.3, { BackgroundColor3 = on and RED or WHITE, BackgroundTransparency = on and 0.62 or 0.95 }, Enum.EasingStyle.Quint)
				tw(p.s, 0.3, { Color = on and Color3.fromRGB(120, 180, 255) or WHITE, Transparency = on and 0.15 or 0.88 }, Enum.EasingStyle.Quint)
				tw(p.l, 0.25, { TextColor3 = on and WHITE or Color3.fromRGB(168, 168, 176) }, Enum.EasingStyle.Quad)
			end
		end
		local pw = (CW - 14 * 2 - 6) / COLS
		for i, name in ipairs(CURVE_NAMES) do
			local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(14 + col * (pw + 6), HEADH + 8 + row * (ROWH + 6))
			b.Size = UDim2.fromOffset(pw, ROWH)
			b.BackgroundColor3 = WHITE
			b.BackgroundTransparency = 0.96
			b.AutoButtonColor = false
			b.Text = ""
			b.ZIndex = 3
			b.Parent = card
			local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 9) bc.Parent = b
			local bs = Instance.new("UIStroke") bs.Color = WHITE bs.Transparency = 0.9 bs.Parent = b
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.GothamBold
			l.Text = name
			l.TextSize = 11
			l.TextColor3 = Color3.fromRGB(168, 168, 176)
			l.ZIndex = 4
			l.Parent = b
			local bsc = Instance.new("UIScale") bsc.Parent = b
			pills[name] = { b = b, s = bs, l = l }
			b.Activated:Connect(function()
				Selected_Parry_Type = name
				CurveType = name
				bsc.Scale = 0.88
				tw(bsc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				paint()
				glass.sheen(0.6)
				Notify("Curve", name, 1.5)
			end)
		end
		paint()

		-- abrir / cerrar la lista tocando la cabecera; arrastrar la tarjeta desde la cabecera
		local opened = false
		local down, moved, startIn, startPos = false, 0, nil, nil
		local dragInput
		head.InputBegan:Connect(function(i)
			if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and not down then
				dragInput = i
				down, moved, startIn, startPos = true, 0, i.Position, card.Position
			end
		end)
		UIS2.InputChanged:Connect(function(i)
			if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) and getgenv().VIREX_SameDrag(dragInput, i) then
				local d = i.Position - startIn
				moved = math.max(moved, d.Magnitude)
				if moved > 8 then
					card.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
					savedPos = card.Position
				end
			end
		end)
		UIS2.InputEnded:Connect(function(i)
			if down and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and getgenv().VIREX_SameDrag(dragInput, i) then
				down = false
				dragInput = nil
				if moved <= 8 and card.Parent then
					opened = not opened
					tw(card, 0.45, { Size = UDim2.fromOffset(CW, opened and OPEN_H or HEADH) }, Enum.EasingStyle.Back)
					tw(arrow, 0.3, { Rotation = opened and 90 or 0 }, Enum.EasingStyle.Quad)
					glass.sheen(0.7)
					paint()
				end
			end
		end)
		-- si "Random Curve" cambia la curva sola, se actualiza el texto
		task.spawn(function()
			local last = nil
			while gui and gui.Parent do
				local now = tostring(Selected_Parry_Type or "Camera")
				if now ~= last then last = now if card.Parent then paint() end end
				task.wait(0.25)
			end
		end)
	end
end

-- ===================== COMBAT =====================
do
	local G = CombatTab:create_group("Auto Parry", "left")
	-- Auto Spam va MEZCLADO dentro de Auto Parry: al encender Auto Parry tambien hace spam.
	-- Con "Separate Them" Auto Spam sale de Auto Parry como opcion propia y va por su cuenta.
	-- Todo espera a que pegues el balon a mano una vez.
	local apWanted, apRunning = false, false
	local liteWanted = false -- Auto Spam Lite (dentro de Auto Parry)
	local asSeparated = false
	VIREX_AS = { wanted = false, running = false }
	function VIREX_AS.start()
		if VIREX_AS.running then return end
		VIREX_AS.running = true
		System.auto_spam.start()
	end
	function VIREX_AS.stop()
		VIREX_AS.running = false
		System.auto_spam.stop()
	end
	-- decide si Auto Spam tiene que estar funcionando ahora mismo
	local function asRefresh()
		-- juntos: el spam va con Auto Parry; separados: va con su propio boton
		local run = _capturedRemote ~= nil and (asSeparated and VIREX_AS.wanted or (not asSeparated and apRunning))
		if run then VIREX_AS.start() else VIREX_AS.stop() end
	end
	local function apStart()
		if apRunning then return end
		apRunning = true
		System.__properties.__autoparry_enabled = true
		System.__properties.__play_animation = true
		System.autoparry.start()
		if liteWanted then System.auto_spam_lite.start() end
		asRefresh()
	end
	local function apStop()
		System.auto_spam_lite.stop()
		apRunning = false
		System.__properties.__autoparry_enabled = false
		System.__properties.__play_animation = false
		System.autoparry.stop()
		asRefresh()
	end
	getgenv().VIREX_OnBypass = function()
		if apWanted and not apRunning then apStart() end
		asRefresh()
	end
	local ap = G:create_toggle("VIREX_AutoParry", { title = "Auto Parry", description = "Parries the ball for you", default = false, callback = function(state)
		apWanted = state
		if state then
			if _capturedRemote then
				apStart()
			else
				-- primero pega el balon a mano; al hacerlo arranca solo
				pcall(function() getgenv().VIREX_ParryHint(true) end)
			end
		else
			apStop()
			if not VIREX_AS.wanted then pcall(function() getgenv().VIREX_ParryHint(false) end) end
		end
		setStatus("Auto Parry " .. (state and "ON" or "OFF"))
	end })
	local mode = G:create_dropdown("VIREX_AutoParry_Mode", { title = "Parry Mode", description = "Remote / Keypress", options = { "Remote", "Keypress" }, default = "Remote", callback = function(value)
		getgenv().AutoParryMode = value
	end })
	local acc = G:create_slider("VIREX_AutoParry_Accuracy", { title = "Accuracy", minimum = 1, maximum = 100, default = 50, rounding = true, callback = function(value)
		System.__properties.__accuracy = value
		if type(update_divisor) == "function" then pcall(update_divisor) end
	end })
	local rnd = G:create_toggle("VIREX_AutoParry_RandomAccuracy", { title = "Randomize Accuracy", default = false, callback = function(state)
		System.__properties.__randomized_accuracy_enabled = state
		if state and type(update_randomized_accuracy) == "function" then pcall(update_randomized_accuracy) end
	end })
	local abil = G:create_toggle("VIREX_AutoParry_AutoAbility", { title = "Auto Ability", default = false, callback = function(state)
		getgenv().AutoAbility = state
	end })
	local pboost = G:create_toggle("VIREX_AutoParry_PingBoost", { title = "Ping Boost", description = "Parries a bit earlier when your ping is high", default = false, callback = function(state)
		System.__properties.__ping_boost = state
	end })
	UI:link(ap, { mode, acc, rnd, abil, pboost }, true)
	-- Auto Spam propio: escondido mientras va mezclado con Auto Parry
	local asToggle = G:create_toggle("VIREX_AutoSpam", { title = "Auto Spam", description = "Spams in close clashes", default = false, callback = function(state)
		VIREX_AS.wanted = state
		if state and not _capturedRemote then pcall(function() getgenv().VIREX_ParryHint(true) end) end
		if not state and not apWanted then pcall(function() getgenv().VIREX_ParryHint(false) end) end
		asRefresh()
	end })
	pcall(function() UI:split(ap, asToggle, false, true) end)
	-- boton de fuera: separa Auto Spam de Auto Parry (sale de el con animacion) o los vuelve a juntar
	local sepReady = false
	G:create_toggle("VIREX_SeparateAutoSpam", { title = "Separate Them", description = "Take Auto Spam out of Auto Parry", default = false, callback = function(state)
		asSeparated = state
		if state and sepReady then
			-- al separarlo, Auto Spam empieza igual que estaba Auto Parry
			pcall(function() asToggle:set_value(apWanted, true) end)
			VIREX_AS.wanted = apWanted
		end
		pcall(function() UI:split(ap, asToggle, state, not sepReady) end)
		asRefresh()
	end })
	task.defer(function() sepReady = true end)
end

do
	local G = CombatTab:create_group("Keyboard", "left")
	local sb = G:create_toggle("VIREX_ManualSpamUI", { title = "Spam Button", description = "Small button: tap to spam", default = false, callback = function(state)
		VIREX_SpamButton(state)
	end })
	local sm = G:create_dropdown("VIREX_ManualSpam_Mode", { title = "Spam Mode", options = { "Remote", "Keypress" }, default = "Remote", callback = function(v)
		getgenv().ManualSpamMode = v
	end })
	local sa = G:create_toggle("VIREX_ManualSpam_AnimFix", { title = "Animation Fix", description = "Plays the parry animation while spamming", default = false, callback = function(v)
		getgenv().ManualSpamAnimationFix = v
		pcall(function() macroAnimFix = v end)
	end })
	UI:link(sb, { sm, sa }, false)
end

do
	local G = CombatTab:create_group("Curve UI", "right")
	G:create_toggle("VIREX_CurveUI", { title = "Curve UI", description = "Pick the parry curve", default = false, callback = function(state)
		VIREX_CurvePicker(state)
	end })
	G:create_toggle("VIREX_RandomCurve", { title = "Random Curve", default = false, callback = function(state)
		if state then
			if not System.__properties.__connections.__random_curve then
				System.__properties.__connections.__random_curve = RunService.PreSimulation:Connect(function()
					Selected_Parry_Type = CURVE_NAMES[math.random(1, #CURVE_NAMES)]
				end)
			end
		elseif System.__properties.__connections.__random_curve then
			System.__properties.__connections.__random_curve:Disconnect()
			System.__properties.__connections.__random_curve = nil
			Selected_Parry_Type = CurveType
		end
	end })
end

do
	local G = CombatTab:create_group("Triggerbot", "right")
	G:create_toggle("VIREX_Triggerbot", { title = "Triggerbot", description = "Red button to turn it on/off", default = false, callback = function(state)
		-- boton TRIGGER con el estilo nuevo (empieza encendido)
		VIREX_TriggerBtn.show(state, state)
	end })
end

do
	local G = CombatTab:create_group("Detection", "right")
	G:create_toggle("VIREX_Detect_Infinity", { title = "Infinity", default = false, callback = function(state) System.__config.__detections.__infinity = state end })
	G:create_toggle("VIREX_Detect_DeathSlash", { title = "Death Slash", default = false, callback = function(state) System.__config.__detections.__deathslash = state end })
	G:create_toggle("VIREX_Detect_TimeHole", { title = "Time Hole", default = false, callback = function(state) System.__config.__detections.__timehole = state end })
	G:create_toggle("VIREX_Detect_SlashesOfFury", { title = "Slashes Of Fury", default = false, callback = function(state) System.__config.__detections.__slashesoffury = state end })
	G:create_toggle("VIREX_Detect_Phantom", { title = "Phantom", default = false, callback = function(state) System.__config.__detections.__phantom = state end })
end

-- ===================== VISUAL =====================
do
	local G = VisualTab:create_group("FOV", "left")
	local fov = G:create_toggle("VIREX_FOV", { title = "FOV", description = "Changes camera FOV", default = false, callback = function(state)
		HOTHX_setFOVEnabled(state)
	end })
	local fovV = G:create_slider("VIREX_FOV_Value", { title = "Camera FOV", minimum = 50, maximum = 120, default = 90, rounding = true, callback = function(value)
		HOTHX_FOV_VALUE = value
		if HOTHX_FOV_ENABLED and workspace.CurrentCamera then
			workspace.CurrentCamera.FieldOfView = value
		end
	end })
	UI:link(fov, { fovV }, true)
end

    -- ===== Character Cosmetics (solo local: Headless / Korblox) =====
    do
        local LP = game:GetService("Players").LocalPlayer
        local state, restore = {headless = false, korblox = false}, {}

        local function lockT(part)
            local h = {part = part, orig = part.Transparency, origLTM = part.LocalTransparencyModifier}
            pcall(function()
                h.conn = part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
                    if part.LocalTransparencyModifier ~= 1 then part.LocalTransparencyModifier = 1 end
                end)
            end)
            part.Transparency = 1
            part.LocalTransparencyModifier = 1
            return h
        end
        local function unlockT(h)
            if not h or not h.part or not h.part.Parent then return end
            if h.conn then pcall(function() h.conn:Disconnect() end) end
            h.part.Transparency = h.orig
            h.part.LocalTransparencyModifier = h.origLTM
        end

        local function applyKorblox(char)
            local hum = char:FindFirstChildOfClass("Humanoid")
            local isR15 = hum and hum.RigType == Enum.HumanoidRigType.R15
            local data = {rig = isR15 and "R15" or "R6", locks = {}, wraps = {}, extras = {}}
            if isR15 then
                local upper = char:WaitForChild("RightUpperLeg", 8)
                local lower = char:WaitForChild("RightLowerLeg", 8)
                local foot = char:WaitForChild("RightFoot", 8)
                if not (upper and lower and foot) then return nil end
                for _, part in ipairs({upper, lower, foot}) do
                    table.insert(data.locks, lockT(part))
                    for _, c in ipairs(part:GetChildren()) do
                        if c:IsA("SurfaceAppearance") or c:IsA("WrapTarget") then c:Destroy()
                        elseif c:IsA("WrapLayer") then table.insert(data.wraps, c) c.Enabled = false end
                    end
                end
                local old = upper:FindFirstChild("KorbloxVisualPart")
                if old then old:Destroy() end
                local k = Instance.new("Part")
                k.Name = "KorbloxVisualPart"
                k.CanCollide, k.CanTouch, k.CanQuery, k.Massless = false, false, false, true
                k.Size = Vector3.new(1, 1, 1)
                k.CFrame = upper.CFrame
                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.FileMesh
                mesh.MeshId = "rbxassetid://902942096"
                mesh.TextureId = "rbxassetid://902843398"
                mesh.Parent = k
                local w = Instance.new("Weld")
                w.Part0, w.Part1, w.Parent = upper, k, k
                k.Parent = upper
                table.insert(data.extras, k)
            else
                local leg = char:WaitForChild("Right Leg", 8)
                if not leg then return nil end
                for _, c in ipairs(char:GetChildren()) do
                    if c:IsA("CharacterMesh") and c.BodyPart == Enum.BodyPart.RightLeg then c:Destroy() end
                end
                for _, c in ipairs(leg:GetChildren()) do
                    if c:IsA("SpecialMesh") or c:IsA("CharacterMesh") or c:IsA("SurfaceAppearance") or c:IsA("WrapTarget") then c:Destroy() end
                end
                pcall(function()
                    local cm = Instance.new("CharacterMesh")
                    cm.MeshId = 101851696
                    cm.BodyPart = Enum.BodyPart.RightLeg
                    cm.Parent = char
                    table.insert(data.extras, cm)
                end)
                pcall(function()
                    local sm = Instance.new("SpecialMesh")
                    sm.MeshType = Enum.MeshType.FileMesh
                    sm.MeshId = "http://www.roblox.com/asset/?id=101851696"
                    sm.TextureId = "http://www.roblox.com/asset/?id=101851254"
                    sm.Parent = leg
                    table.insert(data.extras, sm)
                end)
            end
            return data
        end
        local function unapplyKorblox(char, data)
            if not data then return end
            for _, e in ipairs(data.extras) do if e and e.Parent then e:Destroy() end end
            for _, h in ipairs(data.locks) do unlockT(h) end
            for _, w in ipairs(data.wraps) do if w and w.Parent then w.Enabled = true end end
        end

        local function applyHeadless(char)
            local head = char:WaitForChild("Head", 8)
            if not head then return nil end
            local data = {locks = {lockT(head)}, decals = {}, meshes = {}, wraps = {}}
            for _, c in ipairs(head:GetChildren()) do
                if c:IsA("Decal") then
                    table.insert(data.decals, {obj = c, orig = c.Transparency})
                    c.Transparency = 1
                elseif c:IsA("SpecialMesh") then
                    table.insert(data.meshes, {obj = c, orig = c.Scale})
                    c.Scale = Vector3.new(0, 0, 0)
                elseif c:IsA("SurfaceAppearance") or c:IsA("WrapTarget") then c:Destroy()
                elseif c:IsA("WrapLayer") then table.insert(data.wraps, c) c.Enabled = false end
            end
            return data
        end
        local function unapplyHeadless(data)
            if not data then return end
            for _, h in ipairs(data.locks) do unlockT(h) end
            for _, d in ipairs(data.decals) do if d.obj.Parent then d.obj.Transparency = d.orig end end
            for _, m in ipairs(data.meshes) do if m.obj.Parent then m.obj.Scale = m.orig end end
            for _, w in ipairs(data.wraps) do if w.Parent then w.Enabled = true end end
        end

        local function setFeature(name, on)
            state[name] = on
            local char = LP.Character
            if name == "korblox" then
                if char and restore.korblox then unapplyKorblox(char, restore.korblox) end
                restore.korblox = nil
                if on and char then task.spawn(function() restore.korblox = applyKorblox(char) end) end
            else
                if restore.headless then unapplyHeadless(restore.headless) end
                restore.headless = nil
                if on and char then task.spawn(function() restore.headless = applyHeadless(char) end) end
            end
        end

        LP.CharacterAdded:Connect(function(char)
            restore.korblox, restore.headless = nil, nil
            task.wait(0.6)
            if state.headless then task.spawn(function() restore.headless = applyHeadless(char) end) end
            if state.korblox then task.spawn(function() restore.korblox = applyKorblox(char) end) end
        end)

        -- ===== Avatar (solo lo ves tu): copiar el avatar de cualquier jugador o ponerte cualquier ropa por ID =====
        local AV = { mode = nil, items = {}, keep = true }
        local PlayersS = game:GetService("Players")
        local LOOK_CLASSES = { Accessory = true, Hat = true, Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true }
        local function clearLooks(char)
            for _, c in ipairs(char:GetChildren()) do
                if LOOK_CLASSES[c.ClassName] then pcall(function() c:Destroy() end) end
            end
        end
        -- pega un accesorio al personaje (con AddAccessory y, si falla, soldandolo a mano)
        local function attach(char, acc)
            local handle = acc:FindFirstChild("Handle")
            if not handle then return end
            pcall(function() handle.CanCollide = false handle.CanTouch = false handle.CanQuery = false handle.Massless = true handle.Anchored = false end)
            local hum = char:FindFirstChildOfClass("Humanoid")
            local ok = hum and pcall(function() hum:AddAccessory(acc) end)
            if ok and handle:FindFirstChildWhichIsA("JointInstance") then return end
            acc.Parent = char
            local att = handle:FindFirstChildOfClass("Attachment")
            local target, part
            if att then
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("Attachment") and d.Name == att.Name and d.Parent ~= handle and d.Parent:IsA("BasePart") and not d:IsDescendantOf(acc) then
                        target, part = d, d.Parent
                        break
                    end
                end
            end
            part = part or char:FindFirstChild("Head")
            if not part then return end
            local w = Instance.new("Weld")
            w.Name = "AccessoryWeld"
            w.Part0, w.Part1 = part, handle
            if target and att then
                w.C0, w.C1 = target.CFrame, att.CFrame
            else
                w.C0 = CFrame.new(0, 0.6, 0)
            end
            w.Parent = handle
        end
        local function putLook(char, obj)
            if obj:IsA("Accessory") or obj:IsA("Hat") then
                attach(char, obj)
            elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("BodyColors") then
                local old = char:FindFirstChildOfClass(obj.ClassName)
                if old then old:Destroy() end
                obj.Parent = char
            elseif obj:IsA("Decal") and string.lower(obj.Name) == "face" then
                local head = char:FindFirstChild("Head")
                local f = head and head:FindFirstChild("face")
                if f then f.Texture = obj.Texture end
            end
        end
        local function loadAsset(id)
            local out = {}
            pcall(function()
                for _, o in ipairs(game:GetObjects("rbxassetid://" .. tostring(id))) do
                    if o:IsA("Model") or o:IsA("Folder") then
                        for _, c in ipairs(o:GetChildren()) do table.insert(out, c) end
                    else
                        table.insert(out, o)
                    end
                end
            end)
            return out
        end
        -- todo lo que lleva puesto un usuario (ropa, accesorios, colores, cara)
        local function getLooks(userId)
            local list = {}
            local ok, model = pcall(function() return PlayersS:GetCharacterAppearanceAsync(userId) end)
            if ok and model then
                for _, c in ipairs(model:GetChildren()) do table.insert(list, c) end
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA("Decal") and string.lower(d.Name) == "face" then table.insert(list, d) break end
                end
                return list
            end
            -- respaldo: con su HumanoidDescription se carga cada prenda por su ID
            local okD, desc = pcall(function() return PlayersS:GetHumanoidDescriptionFromUserId(userId) end)
            if not okD or not desc then return nil end
            local ids = {}
            for _, f in ipairs({ "Shirt", "Pants", "GraphicTShirt" }) do
                local v = desc[f]
                if v and v ~= 0 then table.insert(ids, v) end
            end
            pcall(function()
                for _, a in ipairs(desc:GetAccessories(true)) do table.insert(ids, a.AssetId) end
            end)
            for _, id in ipairs(ids) do
                for _, o in ipairs(loadAsset(id)) do table.insert(list, o) end
            end
            pcall(function()
                local bc = Instance.new("BodyColors")
                bc.HeadColor3, bc.TorsoColor3 = desc.HeadColor, desc.TorsoColor
                bc.LeftArmColor3, bc.RightArmColor3 = desc.LeftArmColor, desc.RightArmColor
                bc.LeftLegColor3, bc.RightLegColor3 = desc.LeftLegColor, desc.RightLegColor
                table.insert(list, bc)
            end)
            return list
        end
        -- busca el usuario: primero en el servidor (nombre o apodo), luego en Roblox
        local function findUserId(text)
            text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" then return nil end
            if tonumber(text) then return tonumber(text), text end
            local low = string.lower(text)
            for _, p in ipairs(PlayersS:GetPlayers()) do
                if string.lower(p.Name):sub(1, #low) == low or string.lower(p.DisplayName):sub(1, #low) == low then
                    return p.UserId, p.Name
                end
            end
            local ok, id = pcall(function() return PlayersS:GetUserIdFromNameAsync(text) end)
            if ok and id then return id, text end
            return nil
        end
        local function reapplyCosmetics()
            -- headless / korblox se vuelven a poner encima si estaban activados
            if state.headless then setFeature("headless", true) end
            if state.korblox then setFeature("korblox", true) end
        end
        local function applyUser(char, userId)
            local list = getLooks(userId)
            if not list or #list == 0 then return false end
            clearLooks(char)
            for _, o in ipairs(list) do pcall(putLook, char, o:Clone()) end
            return true
        end
        local function applyItem(char, id)
            local got = loadAsset(id)
            for _, o in ipairs(got) do pcall(putLook, char, o) end
            return #got > 0
        end
        local function copyAvatar(text)
            local char = LP.Character
            if not char then return end
            task.spawn(function()
                local id, name = findUserId(text)
                if not id then Notify("VIREX", "User not found", 2.5) return end
                if applyUser(char, id) then
                    AV.mode = { user = id }
                    AV.items = {}
                    reapplyCosmetics()
                    Notify("VIREX", "Avatar copied: " .. tostring(name or id), 2.5)
                else
                    Notify("VIREX", "Could not load that avatar", 2.5)
                end
            end)
        end
        local function wearItem(text)
            local id = tonumber((tostring(text or ""):match("%d+")))
            local char = LP.Character
            if not id or not char then Notify("VIREX", "Write a valid item ID", 2.5) return end
            task.spawn(function()
                if applyItem(char, id) then
                    table.insert(AV.items, id)
                    Notify("VIREX", "Item equipped", 2)
                else
                    Notify("VIREX", "Could not load that item", 2.5)
                end
            end)
        end
        local function resetAvatar()
            local char = LP.Character
            if not char then return end
            AV.mode, AV.items = nil, {}
            task.spawn(function()
                applyUser(char, LP.UserId)
                reapplyCosmetics()
                Notify("VIREX", "Your avatar is back", 2)
            end)
        end
        LP.CharacterAdded:Connect(function(char)
            if not AV.keep or (not AV.mode and #AV.items == 0) then return end
            task.wait(1.2)
            if AV.mode then applyUser(char, AV.mode.user) end
            for _, id in ipairs(AV.items) do applyItem(char, id) end
            reapplyCosmetics()
        end)

        local AG = CosmeticsTab:create_group("Avatar", "left")
        local userBox = AG:create_textbox("VIREX_AvatarUser", { title = "Copy Player", description = "Name, nickname or ID", placeholder = "Username", default = "", callback = function(text, enter)
            if enter and tostring(text) ~= "" then copyAvatar(text) end
        end })
        AG:create_button("VIREX_AvatarCopy", { title = "Copy Avatar", description = "Only you see it", button_text = "Copy", callback = function()
            copyAvatar(userBox:get_value())
        end })
        local itemBox = AG:create_textbox("VIREX_AvatarItem", { title = "Wear Item", description = "Catalog ID (clothes / hats)", placeholder = "Item ID", default = "", callback = function(text, enter)
            if enter and tostring(text) ~= "" then wearItem(text) end
        end })
        AG:create_button("VIREX_AvatarWear", { title = "Wear", description = "Put on the item ID", button_text = "Wear", callback = function()
            wearItem(itemBox:get_value())
        end })
        AG:create_button("VIREX_AvatarReset", { title = "Reset Avatar", description = "Back to your own avatar", button_text = "Reset", callback = resetAvatar })
        AG:create_toggle("VIREX_AvatarKeep", { title = "Keep On Respawn", description = "Puts it back after you die", default = true, callback = function(v) AV.keep = v end })

        local CG = CosmeticsTab:create_group("Character Cosmetics", "right")
        CG:create_toggle("looks_headless", {title = "Headless", description = "Hide your head (only you see it)", default = false, callback = function(v) setFeature("headless", v) end})
        CG:create_toggle("looks_korblox", {title = "Korblox", description = "Korblox right leg (only you see it)", default = false, callback = function(v) setFeature("korblox", v) end})
    end


do
	local G = VisualTab:create_group("Auto Play", "right")
	local apl = G:create_toggle("VIREX_AutoPlay", { title = "Auto Play", description = "Automatically plays game", default = false, callback = function(state)
		HOTHX_setAutoPlay(state)
	end })
	local list = {}
	local function T(flag, title, desc, cb) list[#list + 1] = G:create_toggle(flag, { title = title, description = desc, default = false, callback = cb }) end
	local function S(flag, title, mn, mx, def, inc, cb) list[#list + 1] = G:create_slider(flag, { title = title, minimum = mn, maximum = mx, default = def, increment = inc, rounding = inc >= 1, callback = cb }) end
	T("VIREX_AntiAFK", "Anti AFK", "Prevent idle kick", function(state) HOTHX_setAntiAFK(state) end)
	T("VIREX_AutoPlay_Jump", "Enable Jumping", "Allow jump and double jump", function(state) getgenv().AutoPlayJumpingEnabled = state end)
	T("VIREX_AutoVote", "Auto Vote", "Auto vote flag", function(state) getgenv().AutoVote = state end)
	S("VIREX_AutoPlay_Distance", "Distance From Ball", 5, 100, 18, 1, function(v) getgenv().AutoPlayDistance = v end)
	S("VIREX_AutoPlay_Speed", "Speed Multiplier", 10, 200, 45, 1, function(v) getgenv().AutoPlayMultiplierThreshold = v end)
	S("VIREX_AutoPlay_Transversing", "Transversing", 0, 100, 8, 1, function(v) getgenv().AutoPlayTransversing = v end)
	S("VIREX_AutoPlay_Direction", "Direction", -1, 1, 1, 0.1, function(v) getgenv().AutoPlayDirection = v end)
	S("VIREX_AutoPlay_Offset", "Offset Factor", 0.1, 1, 0.4, 0.1, function(v) getgenv().AutoPlayOffsetFactor = v end)
	S("VIREX_AutoPlay_MoveDur", "Movement Duration", 0.1, 1, 0.75, 0.05, function(v) getgenv().AutoPlayMovementDuration = v end)
	S("VIREX_AutoPlay_GenThresh", "Generation Threshold", 0.1, 0.5, 0.25, 0.05, function(v) getgenv().AutoPlayGenerationThreshold = v end)
	S("VIREX_AutoPlay_JumpChance", "Jump Chance", 0, 100, 20, 1, function(v) getgenv().AutoPlayJumpPercentage = v end)
	S("VIREX_AutoPlay_DJumpChance", "Double Jump Chance", 0, 100, 10, 1, function(v) getgenv().AutoPlayDoubleJumpPercentage = v end)
	UI:link(apl, list, true)
end

do
	local G = VisualTab:create_group("Hit Sounds", "right")
	local hs = G:create_toggle("VIREX_HitSounds", { title = "Hit Sounds", description = "Toggles hit sounds", default = false, callback = function(state)
		HOTHX_HIT_SOUND_ENABLED = state
	end })
	local vol = G:create_slider("VIREX_HitSounds_Volume", { title = "Volume", minimum = 1, maximum = 10, default = 5, rounding = true, callback = function(value)
		HOTHX_HIT_SOUND.Volume = value
	end })
	local typ = G:create_dropdown("VIREX_HitSounds_Type", { title = "Hit Sound Type", options = HOTHX_HIT_SOUND_OPTIONS, default = "Skeet", callback = function(value)
		HOTHX_setHitSoundType(value)
	end })
	UI:link(hs, { vol, typ }, true)
end

-- ===================== IMMORTAL (del source anterior, sin cambios) =====================
local backgroundOrbitInitialized = false  
local backgroundOrbitState = { Enabled = false }  
local backgroundOrbitHRP = nil  
local backgroundOrbitCharacterConnection = nil  
  
local function startBackgroundOrbit()  
    backgroundOrbitState.Enabled = true  
  
    if backgroundOrbitInitialized then  
        return  
    end  
  
    backgroundOrbitInitialized = true  
  
    local function onCharacter(char)  
        backgroundOrbitHRP = char:WaitForChild("HumanoidRootPart", 5)  
    end  
  
    backgroundOrbitCharacterConnection =  
        LocalPlayer.CharacterAdded:Connect(onCharacter)  
  
    if LocalPlayer.Character then  
        onCharacter(LocalPlayer.Character)  
    end  
  
    local DesyncTypes = {}  
    local oldIndexCFrame  
  
    if hookmetamethod and newcclosure then  
        oldIndexCFrame = hookmetamethod(game, "__index", newcclosure(function(self, key)  
            if not backgroundOrbitState.Enabled or checkcaller() then  
                return oldIndexCFrame(self, key)  
            end  
  
            if key == "CFrame" and backgroundOrbitHRP and self == backgroundOrbitHRP then  
                return DesyncTypes[1] or oldIndexCFrame(self, key)  
            end  
  
            return oldIndexCFrame(self, key)  
        end))  
    end  
  
    System.__properties.__connections.immortal_orbit =  
        RunService.Heartbeat:Connect(function()  
            if not backgroundOrbitState.Enabled or not backgroundOrbitHRP then  
                return  
            end  
  
            if not backgroundOrbitHRP.Parent then  
                backgroundOrbitHRP = LocalPlayer.Character  
                    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")  
  
                if not backgroundOrbitHRP then  
                    return  
                end  
            end  
  
            DesyncTypes[1] = backgroundOrbitHRP.CFrame  
            DesyncTypes[2] = backgroundOrbitHRP.AssemblyLinearVelocity  
  
            local orbitRadius = 20  
            local angleMultiplier = 20  
            local rotAngle = tick() * math.pi * 2 * angleMultiplier / 5  
  
            local pos = Vector3.new(  
                math.cos(rotAngle) * orbitRadius,  
                0,  
                math.sin(rotAngle) * orbitRadius  
            )  
  
            backgroundOrbitHRP.CFrame = DesyncTypes[1] + pos  
            backgroundOrbitHRP.AssemblyLinearVelocity = Vector3.zero  
  
            RunService.RenderStepped:Wait()  
  
            if backgroundOrbitState.Enabled and backgroundOrbitHRP then  
                backgroundOrbitHRP.CFrame = DesyncTypes[1]  
                backgroundOrbitHRP.AssemblyLinearVelocity = DesyncTypes[2]  
            end  
        end)  
  
    System.__properties.__connections.immortal_offset =  
        RunService.Heartbeat:Connect(function()  
            if not backgroundOrbitState.Enabled then  
                return  
            end  
  
            local char = LocalPlayer.Character  
            local hrp = char and char:FindFirstChild("HumanoidRootPart")  
  
            if hrp then  
                hrp.CFrame = hrp.CFrame + Vector3.new(0, 0.01, 0)  
            end  
        end)  
end  
  
local function stopBackgroundOrbit()  
    backgroundOrbitState.Enabled = false  
end  
  
do
	local G = CombatTab:create_group("Immortal", "right")
	pcall(function() G.box.LayoutOrder = -1 end) -- arriba del todo en Combat
	G:create_toggle("virex_immortal", { title = "Immortal", default = false, callback = function(state)
		if state then
			startBackgroundOrbit()
		else
			stopBackgroundOrbit()
		end
	end })
end

-- ===================== MISC =====================
do
	local G = MiscTab:create_group("Performance", "left")
	G:create_toggle("VIREX_NoRender", { title = "No Render", description = "Disables rendering of effects", default = false, callback = function(state) HOTHX_setNoRender(state) end })
	G:create_toggle("VIREX_FPSBooster", { title = "FPS Booster", description = "Lower graphics to improve FPS", default = false, callback = function(state) HOTHX_setFPSBooster(state) end })
	G:create_toggle("VIREX_LowGraphics", { title = "Low Graphics", description = "Reduce quality and shadows", default = false, callback = function(state) HOTHX_setLowGraphics(state) end })
end
do
	local G = CosmeticsTab:create_group("Unlock", "right")
	G:create_toggle("VIREX_UnlockAll", { title = "Unlock All", description = "Swords, explosions and emotes", default = false, callback = function(state)
		getgenv().unlockAllEnabled = state
		if state and getgenv().__runUnlockAll then task.spawn(getgenv().__runUnlockAll) end
	end })
end

-- ===================== WORLD: niebla (solo la ves tu) =====================
do
	local Lighting = game:GetService("Lighting")
	local FOG_COLORS = {
		Gray = Color3.fromRGB(150, 150, 158), Black = Color3.fromRGB(8, 8, 10), White = Color3.fromRGB(235, 235, 240),
		Red = Color3.fromRGB(150, 18, 28), Purple = Color3.fromRGB(90, 40, 150), Blue = Color3.fromRGB(40, 80, 160),
		Pink = Color3.fromRGB(220, 110, 180), Green = Color3.fromRGB(40, 130, 70),
	}
	local FOG_NAMES = { "Gray", "Black", "White", "Red", "Purple", "Blue", "Pink", "Green" }
	local fog = { on = false, color = "Gray", dist = 250, start = 0 }
	local backup, hidden = nil, {}
	-- la Atmosphere del juego tapa la niebla clasica: mientras la niebla esta encendida se quita y luego se devuelve
	local function stash()
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") then
				table.insert(hidden, a)
				pcall(function() a.Parent = nil end)
			end
		end
	end
	local function apply()
		if not fog.on then return end
		if not backup then backup = { s = Lighting.FogStart, e = Lighting.FogEnd, c = Lighting.FogColor } end
		stash()
		Lighting.FogStart = fog.start
		Lighting.FogEnd = fog.dist
		Lighting.FogColor = FOG_COLORS[fog.color] or FOG_COLORS.Gray
	end
	local function restore()
		if backup then
			pcall(function()
				Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor = backup.s, backup.e, backup.c
			end)
			backup = nil
		end
		for _, a in ipairs(hidden) do pcall(function() a.Parent = Lighting end) end
		hidden = {}
	end
	-- el juego a veces cambia la luz entre rondas: se vuelve a poner cada segundo
	task.spawn(function()
		while true do
			task.wait(1)
			if fog.on then pcall(apply) end
		end
	end)
	local G = VisualTab:create_group("Fog", "left")
	local t = G:create_toggle("VIREX_Fog", { title = "Custom Fog", description = "Fog with your color (only you see it)", default = false, callback = function(state)
		fog.on = state
		if state then pcall(apply) else pcall(restore) end
	end })
	local c = G:create_dropdown("VIREX_Fog_Color", { title = "Fog Color", options = FOG_NAMES, default = "Gray", callback = function(v)
		fog.color = v
		pcall(apply)
	end })
	local d = G:create_slider("VIREX_Fog_Distance", { title = "Fog Distance", minimum = 40, maximum = 1500, default = 250, rounding = true, suffix = " studs", callback = function(v)
		fog.dist = v
		pcall(apply)
	end })
	local s = G:create_slider("VIREX_Fog_Start", { title = "Fog Start", minimum = 0, maximum = 300, default = 0, rounding = true, suffix = " studs", callback = function(v)
		fog.start = v
		pcall(apply)
	end })
	UI:link(t, { c, d, s }, true)
end

-- ===================== ESP: color de jugadores, el tuyo y el balon =====================
do
	local LP = game:GetService("Players").LocalPlayer
	local PlayersS = game:GetService("Players")
	local COLORS = {
		Red = Color3.fromRGB(255, 45, 60), White = Color3.fromRGB(255, 255, 255), Black = Color3.fromRGB(12, 12, 14),
		Blue = Color3.fromRGB(60, 140, 255), Cyan = Color3.fromRGB(60, 230, 255), Green = Color3.fromRGB(70, 235, 120),
		Purple = Color3.fromRGB(170, 90, 255), Pink = Color3.fromRGB(255, 100, 200), Gold = Color3.fromRGB(255, 200, 60),
		Orange = Color3.fromRGB(255, 140, 40),
	}
	local COLOR_NAMES = { "Red", "White", "Black", "Blue", "Cyan", "Green", "Purple", "Pink", "Gold", "Orange" }
	local OUTLINES = { "Black", "White", "Same Color", "None" }
	local function cfg(color) return { on = false, color = color, outline = "Black", rainbow = false, fill = 0.45 } end
	local E = { players = cfg("Red"), me = cfg("Cyan"), ball = cfg("White") }
	E.players.names = false
	E.ball.danger = true

	local tagHolder
	pcall(function()
		tagHolder = Instance.new("Folder")
		tagHolder.Name = "VIREX_ESPTags"
		tagHolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	local marks = {} -- [objeto] = { hl, tag, ghost, kind }

	local function drop(obj)
		local m = marks[obj]
		if not m then return end
		pcall(function() m.hl:Destroy() end)
		if m.tag then pcall(function() m.tag:Destroy() end) end
		if m.ghost then pcall(function() m.ghost:Destroy() end) end
		if m.beam then pcall(function() m.beam:Destroy() end) end
		if m.att then pcall(function() m.att:Destroy() end) end
		if m.info then pcall(function() m.info:Destroy() end) end
		marks[obj] = nil
	end
	local function rainbow(off) return Color3.fromHSV((os.clock() * 0.22 + (off or 0)) % 1, 0.9, 1) end
	local function colorFor(kind, obj)
		local c = E[kind]
		if kind == "ball" and c.danger and obj:GetAttribute("target") == LP.Name then return COLORS.Red end
		if c.rainbow then return rainbow(kind == "ball" and 0.5 or 0) end
		return COLORS[c.color] or COLORS.Red
	end
	local function style(m, obj)
		local c = E[m.kind]
		local col = colorFor(m.kind, obj)
		local h = m.hl
		h.FillColor = col
		h.FillTransparency = c.fill
		if c.outline == "None" then
			h.OutlineTransparency = 1
		else
			h.OutlineTransparency = 0
			h.OutlineColor = (c.outline == "Black" and Color3.new(0, 0, 0)) or (c.outline == "White" and Color3.new(1, 1, 1)) or col
		end
		if m.beam then m.beam.Color = ColorSequence.new(col) end
		if m.ghost then
			m.ghost.Color = col
			m.ghost.Transparency = math.clamp(0.35 + c.fill * 0.6, 0.35, 0.95)
		end
		if m.tag then
			local lbl = m.tag:FindFirstChild("L")
			if lbl then lbl.TextColor3 = col end
		end
	end
	-- el balon de verdad suele ser invisible (el juego dibuja otro encima), por eso el color no salia:
	-- ahora se pone una bola de neon propia que lo sigue cada frame, y el resalte va en esa bola
	local function makeGhost(ball)
		local p = Instance.new("Part")
		p.Name = "VIREX_BallESP"
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		local s = 3
		pcall(function() s = math.max(ball.Size.X, ball.Size.Y, ball.Size.Z) end)
		if s < 1 or s > 30 then s = 3 end
		s = s * 1.15
		p.Size = Vector3.new(s, s, s)
		p.CFrame = CFrame.new(ball.Position)
		p.Parent = workspace
		return p
	end
	local function mark(obj, kind, nameText)
		local m = marks[obj]
		if m and m.kind ~= kind then drop(obj) m = nil end
		if m and m.hl.Parent == nil then drop(obj) m = nil end
		if not m then
			m = { kind = kind }
			local h = Instance.new("Highlight")
			h.Name = "VIREX_ESP"
			h.DepthMode = kind == "me" and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
			if kind == "ball" then
				m.ghost = makeGhost(obj)
				h.Parent = m.ghost
			else
				-- dentro del personaje: asi se ve siempre (en algunos executors no salia desde fuera)
				h.Parent = obj
			end
			m.hl = h
			marks[obj] = m
		end
		-- nombre encima de la cabeza (solo jugadores)
		if kind == "players" and E.players.names and nameText then
			if not m.tag then
				local head = obj:FindFirstChild("Head")
				if head then
					local bb = Instance.new("BillboardGui")
					bb.Name = "VIREX_ESPTag"
					bb.Adornee = head
					bb.AlwaysOnTop = true
					bb.Size = UDim2.fromOffset(170, 30)
					bb.StudsOffset = Vector3.new(0, 2.6, 0)
					local l = Instance.new("TextLabel")
					l.Name = "L"
					l.BackgroundTransparency = 1
					l.Size = UDim2.fromScale(1, 1)
					l.Font = Enum.Font.GothamBlack
					l.TextSize = 13
					l.TextStrokeTransparency = 0.3
					l.TextColor3 = Color3.new(1, 1, 1)
					l.Text = nameText
					l.Parent = bb
					local okP = tagHolder and pcall(function() bb.Parent = tagHolder end)
					if not okP then bb.Parent = head end
					m.tag = bb
				end
			end
			if m.tag then
				local lbl = m.tag:FindFirstChild("L")
				local d = 0
				pcall(function() d = math.floor(LP:DistanceFromCharacter(obj:GetPivot().Position) + 0.5) end)
				if lbl then lbl.Text = nameText .. "  [" .. d .. "m]" end
			end
		elseif m.tag then
			pcall(function() m.tag:Destroy() end)
			m.tag = nil
		end
		style(m, obj)
	end
	-- ===== extras: lineas (tracers), info del balon y jugador al que va el balon =====
	E.players.tracers = false
	E.ball.tracer = false
	E.ball.info = false
	E.ball.target = false
	local myAtt
	local function getMyAtt()
		local ch = LP.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		if not myAtt or myAtt.Parent ~= hrp then
			if myAtt then pcall(function() myAtt:Destroy() end) end
			myAtt = Instance.new("Attachment")
			myAtt.Name = "VIREX_TracerFrom"
			myAtt.Parent = hrp
		end
		return myAtt
	end
	-- linea de luz desde ti hasta el jugador / balon
	local function setBeam(m, part, want)
		if not want or not part then
			if m.beam then pcall(function() m.beam:Destroy() end) m.beam = nil end
			if m.att then pcall(function() m.att:Destroy() end) m.att = nil end
			return
		end
		local from = getMyAtt()
		if not from then return end
		if not m.beam or not m.beam.Parent or not m.att or m.att.Parent ~= part then
			if m.beam then pcall(function() m.beam:Destroy() end) end
			if m.att then pcall(function() m.att:Destroy() end) end
			local att = Instance.new("Attachment")
			att.Name = "VIREX_TracerTo"
			att.Parent = part
			local b = Instance.new("Beam")
			b.Name = "VIREX_Tracer"
			b.Attachment0, b.Attachment1 = from, att
			b.Width0, b.Width1 = 0.16, 0.08
			b.FaceCamera = true
			b.LightEmission = 1
			b.LightInfluence = 0
			b.Segments = 1
			b.Transparency = NumberSequence.new(0.1, 0.45)
			b.Parent = part
			m.beam, m.att = b, att
		end
		if m.beam.Attachment0 ~= from then m.beam.Attachment0 = from end
	end
	-- cartel encima del balon: velocidad y a quien va
	local function setInfo(m, want)
		if not want or not m.ghost then
			if m.info then pcall(function() m.info:Destroy() end) m.info = nil end
			return
		end
		if m.info and m.info.Parent then return end
		local bb = Instance.new("BillboardGui")
		bb.Name = "VIREX_BallInfo"
		bb.Adornee = m.ghost
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(200, 40)
		bb.StudsOffset = Vector3.new(0, 3.2, 0)
		local l = Instance.new("TextLabel")
		l.Name = "L"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextSize = 13
		l.TextStrokeTransparency = 0.25
		l.TextColor3 = Color3.new(1, 1, 1)
		l.RichText = true
		l.Text = ""
		l.Parent = bb
		local okP = tagHolder and pcall(function() bb.Parent = tagHolder end)
		if not okP then bb.Parent = m.ghost end
		m.info = bb
	end
	-- jugador al que va el balon: brillo dorado
	local targetHL = Instance.new("Highlight")
	targetHL.Name = "VIREX_BallTarget"
	targetHL.FillColor = Color3.fromRGB(255, 200, 60)
	targetHL.FillTransparency = 0.55
	targetHL.OutlineColor = Color3.new(1, 1, 1)
	targetHL.OutlineTransparency = 0
	targetHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	local function getBalls()
		local list = {}
		pcall(function()
			local f = workspace:FindFirstChild("Balls")
			if f then
				for _, b in ipairs(f:GetChildren()) do
					if b:IsA("BasePart") and b:GetAttribute("realBall") then list[#list + 1] = b end
				end
			end
			local tf = workspace:FindFirstChild("TrainingBalls")
			if tf then
				for _, b in ipairs(tf:GetChildren()) do
					if b:IsA("BasePart") and b:GetAttribute("realBall") then list[#list + 1] = b end
				end
			end
		end)
		return list
	end

	-- cada 0.2 s se revisa quien tiene que llevar color
	task.spawn(function()
		while true do
			task.wait(0.2)
			local want = {}
			if E.players.on then
				for _, p in ipairs(PlayersS:GetPlayers()) do
					if p ~= LP and p.Character and p.Character.Parent then
						want[p.Character] = true
						pcall(mark, p.Character, "players", p.DisplayName)
						local m = marks[p.Character]
						if m then pcall(setBeam, m, p.Character:FindFirstChild("HumanoidRootPart"), E.players.tracers) end
					end
				end
			end
			if E.me.on and LP.Character and LP.Character.Parent then
				want[LP.Character] = true
				pcall(mark, LP.Character, "me")
			end
			if E.ball.on then
				for _, b in ipairs(getBalls()) do
					want[b] = true
					pcall(mark, b, "ball")
					local m = marks[b]
					if m then
						pcall(setBeam, m, m.ghost, E.ball.tracer)
						pcall(setInfo, m, E.ball.info)
					end
				end
			end
			-- brillo dorado en el jugador que tiene el balon encima
			local tgtChar
			if E.ball.target then
				for _, b in ipairs(getBalls()) do
					local name = b:GetAttribute("target")
					local pl = name and PlayersS:FindFirstChild(name)
					if pl and pl.Character then tgtChar = pl.Character break end
				end
			end
			pcall(function() targetHL.Parent = tgtChar end)
			for obj in pairs(marks) do
				if not want[obj] or not obj.Parent then drop(obj) end
			end
		end
	end)
	-- cada frame: la bola de neon sigue al balon, y arcoiris / rojo cuando va a por ti
	RunService.RenderStepped:Connect(function()
		for obj, m in pairs(marks) do
			if m.ghost then
				pcall(function() m.ghost.CFrame = CFrame.new(obj.Position) end)
			end
			if m.info then
				pcall(function()
					local z = obj:FindFirstChild("zoomies")
					local v = z and z.VectorVelocity or obj.AssemblyLinearVelocity
					local tgt = obj:GetAttribute("target")
					local mine = tgt == LP.Name
					m.info.L.Text = string.format('<font color="#9fd0ff">%d</font> speed  ·  %s', math.floor(v.Magnitude + 0.5), tgt and ((mine and '<font color="#ff5a64">YOU</font>') or tostring(tgt)) or "-")
				end)
			end
			local c = E[m.kind]
			if c and (c.rainbow or (m.kind == "ball" and c.danger)) then pcall(style, m, obj) end
		end
	end)
	local function restyle() for obj, m in pairs(marks) do pcall(style, m, obj) end end

	local function section(tabGroup, key, title, desc, prefix, extra)
		local c = E[key]
		local t = tabGroup:create_toggle(prefix, { title = title, description = desc, default = false, callback = function(state)
			c.on = state
			if not state then for obj, m in pairs(marks) do if m.kind == key then drop(obj) end end end
		end })
		local list = {}
		list[#list + 1] = tabGroup:create_dropdown(prefix .. "_Color", { title = "Color", options = COLOR_NAMES, default = c.color, callback = function(v) c.color = v restyle() end })
		list[#list + 1] = tabGroup:create_dropdown(prefix .. "_Outline", { title = "Outline", options = OUTLINES, default = "Black", callback = function(v) c.outline = v restyle() end })
		list[#list + 1] = tabGroup:create_toggle(prefix .. "_Rainbow", { title = "Rainbow", description = "Colors keep changing", default = false, callback = function(v) c.rainbow = v restyle() end })
		list[#list + 1] = tabGroup:create_slider(prefix .. "_Fill", { title = "Fill", minimum = 0, maximum = 100, default = 55, rounding = true, suffix = "%", callback = function(v) c.fill = 1 - v / 100 restyle() end })
		if extra then extra(list) end
		UI:link(t, list, true)
		return t
	end
	local GP = VisualTab:create_group("Player ESP", "left")
	section(GP, "players", "Player ESP", "Color players, see them through walls", "VIREX_ESP_Players", function(list)
		list[#list + 1] = GP:create_toggle("VIREX_ESP_Players_Names", { title = "Show Names", description = "Name and distance on top", default = false, callback = function(v) E.players.names = v end })
		list[#list + 1] = GP:create_toggle("VIREX_ESP_Players_Tracers", { title = "Tracers", description = "Light line from you to each player", default = false, callback = function(v) E.players.tracers = v end })
	end)
	local GM = VisualTab:create_group("Your Character", "left")
	section(GM, "me", "My Color", "Color your character (only you see it)", "VIREX_ESP_Me")
	local GB = VisualTab:create_group("Ball ESP", "right")
	GB:create_toggle("VIREX_ESP_Target", { title = "Ball Target", description = "Gold glow on the player the ball is going to", default = false, callback = function(v)
		E.ball.target = v
		if not v then pcall(function() targetHL.Parent = nil end) end
	end })
	section(GB, "ball", "Ball ESP", "Color the ball, see it through walls", "VIREX_ESP_Ball", function(list)
		list[#list + 1] = GB:create_toggle("VIREX_ESP_Ball_Tracer", { title = "Ball Tracer", description = "Light line from you to the ball", default = false, callback = function(v) E.ball.tracer = v end })
		list[#list + 1] = GB:create_toggle("VIREX_ESP_Ball_Info", { title = "Ball Info", description = "Speed and who it's going to", default = false, callback = function(v) E.ball.info = v end })
		list[#list + 1] = GB:create_toggle("VIREX_ESP_Ball_Danger", { title = "Red When Targeting", description = "Turns red when it comes for you", default = true, callback = function(v) E.ball.danger = v restyle() end })
	end)
end

-- ===================== EXTRAS (del source NAZK, con el estilo VIREX) =====================
-- Dash, Auto Jump, sin cooldown de habilidades, HUD de ping / velocidad del balon y Skin Changer
do
	local LP = game:GetService("Players").LocalPlayer
	local UIS2 = game:GetService("UserInputService")
	local RS2 = game:GetService("ReplicatedStorage")

	-- ===== Dash =====
	local D = { on = false, power = 45, height = 0, cd = 0.25, key = Enum.KeyCode.Q, last = 0 }
	local function doDash()
		if not D.on or tick() - D.last < D.cd then return end
		D.last = tick()
		local char = LP.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not root or not cam then return end
		local dir = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if dir.Magnitude < 0.01 then return end
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
		bv.Velocity = dir.Unit * D.power + Vector3.new(0, D.height, 0)
		bv.P = 20000
		bv.Parent = root
		game:GetService("Debris"):AddItem(bv, 0.15)
	end
	UIS2.InputBegan:Connect(function(input, gp)
		if not gp and D.on and input.KeyCode == D.key then doDash() end
	end)
	-- boton flotante DASH (para movil): se toca y hace el dash
	local dashBtn
	pcall(function()
		dashBtn = VIREX_MakeActionButton({ name = "VIREX_DashButton", label = "DASH", activeLabel = "DASH", yOffset = 190, onToggle = function()
			D.on = true
			doDash()
			return false
		end })
	end)

	local GM = MiscTab:create_group("Movement", "left")
	local dt = GM:create_toggle("VIREX_Dash", { title = "Dash", description = "Quick dash where you look", default = false, callback = function(v) D.on = v end })
	local dp = GM:create_slider("VIREX_Dash_Power", { title = "Dash Power", minimum = 10, maximum = 200, default = 45, rounding = true, callback = function(v) D.power = v end })
	local dh = GM:create_slider("VIREX_Dash_Height", { title = "Dash Height", minimum = 0, maximum = 100, default = 0, rounding = true, callback = function(v) D.height = v end })
	local dc = GM:create_slider("VIREX_Dash_Cooldown", { title = "Dash Cooldown", minimum = 0, maximum = 2, default = 0.25, increment = 0.05, suffix = "s", callback = function(v) D.cd = v end })
	local dk = GM:create_dropdown("VIREX_Dash_Key", { title = "Dash Key", options = { "Q", "E", "F", "LeftShift", "C", "V", "X" }, default = "Q", callback = function(v)
		local ok, k = pcall(function() return Enum.KeyCode[v] end)
		D.key = ok and k or Enum.KeyCode.Q
	end })
	local db = GM:create_toggle("VIREX_Dash_Button", { title = "Dash Button", description = "Button on screen (mobile)", default = false, callback = function(v)
		if dashBtn then pcall(function() dashBtn.show(v) end) end
	end })
	UI:link(dt, { dp, dh, dc, dk, db }, true)

	-- ===== Auto Jump =====
	local AJ, onGroundLast = false, false
	RunService.Heartbeat:Connect(function()
		if not AJ then onGroundLast = false return end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local onGround = hum.FloorMaterial ~= Enum.Material.Air
			if onGround and not onGroundLast then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			onGroundLast = onGround
		end
	end)
	GM:create_toggle("VIREX_AutoJump", { title = "Auto Jump", description = "Jumps every time you land", default = false, callback = function(v) AJ = v end })

	-- ===== Sin cooldown de habilidades (Thunder Dash infinito) =====
	local GA = CombatTab:create_group("Abilities", "right")
	local ncOn, ncConn = false, nil
	local function noCooldown(ability)
		local ok, module = pcall(require, ability)
		if ok and type(module) == "table" then
			pcall(function()
				if module.cooldown ~= nil then module.cooldown = 0 end
				if module.cooldownReductionPerUpgrade ~= nil then module.cooldownReductionPerUpgrade = 0 end
			end)
		end
	end
	GA:create_toggle("VIREX_NoAbilityCooldown", { title = "No Ability Cooldown", description = "Infinite Thunder Dash and abilities", default = false, callback = function(v)
		if not v or ncOn then return end
		ncOn = true
		task.spawn(function()
			local shared = RS2:WaitForChild("Shared", 10)
			local abilities = shared and shared:WaitForChild("Abilities", 10)
			if not abilities then return end
			for _, a in ipairs(abilities:GetChildren()) do noCooldown(a) end
			ncConn = abilities.ChildAdded:Connect(noCooldown)
		end)
		local _ = ncConn
	end })

	-- ===== HUD: ping real + velocidad del balon (tarjeta de cristal, se puede mover) =====
	local hud = { ping = false, ball = false, peak = 0, lastBall = nil }
	local hudGui, hudCard, rows
	local function buildHud()
		if hudGui and hudGui.Parent then return end
		local parent
		pcall(function() parent = gethui and gethui() end)
		if not parent then parent = game:GetService("CoreGui") end
		local old = parent:FindFirstChild("VIREX_HUD")
		if old then old:Destroy() end
		hudGui = Instance.new("ScreenGui")
		hudGui.Name = "VIREX_HUD"
		hudGui.ResetOnSpawn = false
		hudGui.IgnoreGuiInset = true
		hudGui.DisplayOrder = 110
		local W_ = Color3.new(1, 1, 1)
		hudCard = Instance.new("Frame")
		hudCard.Position = UDim2.new(0, 16, 0.7, 0)
		hudCard.Size = UDim2.fromOffset(176, 0)
		hudCard.AutomaticSize = Enum.AutomaticSize.Y
		hudCard.BackgroundColor3 = W_
		hudCard.BackgroundTransparency = 0.22
		hudCard.BorderSizePixel = 0
		hudCard.Active = true
		hudCard.Parent = hudGui
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 14) c.Parent = hudCard
		-- cristal: reflejo suave que baja a oscuro (sin linea blanca arriba)
		local bg = Instance.new("UIGradient")
		bg.Rotation = 90
		bg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 50, 68)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(20, 23, 32)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 11, 16)) })
		bg.Parent = hudCard
		local st = Instance.new("UIStroke") st.Color = W_ st.Thickness = 1.1 st.Transparency = 0.1 st.Parent = hudCard
		local sg = Instance.new("UIGradient") sg.Rotation = 90
		sg.Color = ColorSequence.new(W_, Color3.fromRGB(150, 185, 235))
		sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 0.55) })
		sg.Parent = st
		local pad = Instance.new("UIPadding") pad.PaddingTop = UDim.new(0, 8) pad.PaddingBottom = UDim.new(0, 8) pad.PaddingLeft = UDim.new(0, 8) pad.PaddingRight = UDim.new(0, 8) pad.Parent = hudCard
		local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 5) lay.SortOrder = Enum.SortOrder.LayoutOrder lay.Parent = hudCard
		-- cada dato en su pastilla de cristal: punto de color, nombre y valor
		local function row(order, name)
			local r = Instance.new("Frame")
			r.LayoutOrder = order
			r.Size = UDim2.new(1, 0, 0, 26)
			r.BackgroundColor3 = W_
			r.BackgroundTransparency = 0.93
			r.BorderSizePixel = 0
			r.Parent = hudCard
			local rc = Instance.new("UICorner") rc.CornerRadius = UDim.new(0, 9) rc.Parent = r
			local rs = Instance.new("UIStroke") rs.Color = W_ rs.Transparency = 0.88 rs.Parent = r
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0, 0.5)
			dot.Position = UDim2.new(0, 9, 0.5, 0)
			dot.Size = UDim2.fromOffset(7, 7)
			dot.BackgroundColor3 = Color3.fromRGB(90, 230, 140)
			dot.BorderSizePixel = 0
			dot.Parent = r
			local dc = Instance.new("UICorner") dc.CornerRadius = UDim.new(1, 0) dc.Parent = dot
			local k = Instance.new("TextLabel")
			k.BackgroundTransparency = 1
			k.Position = UDim2.fromOffset(22, 0)
			k.Size = UDim2.new(0.5, -22, 1, 0)
			k.Font = Enum.Font.GothamBold
			k.TextSize = 10
			k.TextColor3 = Color3.fromRGB(165, 172, 188)
			k.TextXAlignment = Enum.TextXAlignment.Left
			k.Text = name
			k.Parent = r
			local v = Instance.new("TextLabel")
			v.BackgroundTransparency = 1
			v.AnchorPoint = Vector2.new(1, 0)
			v.Position = UDim2.new(1, -10, 0, 0)
			v.Size = UDim2.new(0.5, 0, 1, 0)
			v.Font = Enum.Font.GothamBlack
			v.TextSize = 13
			v.TextColor3 = W_
			v.TextXAlignment = Enum.TextXAlignment.Right
			v.Text = "--"
			v.Parent = r
			return { frame = r, dot = dot, val = v }
		end
		rows = { ping = row(1, "PING"), speed = row(2, "BALL SPEED"), peak = row(3, "TOP SPEED") }
		rows.speed.dot.BackgroundColor3 = Color3.fromRGB(120, 185, 255)
		rows.peak.dot.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
		pcall(function() if getgenv().VIREX_Skin then getgenv().VIREX_Skin(hudGui) end end)
		hudGui.Parent = parent
		-- arrastrar
		local drag, startIn, startPos, inp
		hudCard.InputBegan:Connect(function(i)
			if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and not drag then
				drag, startIn, startPos, inp = true, i.Position, hudCard.Position, i
			end
		end)
		UIS2.InputChanged:Connect(function(i)
			if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i == inp) then
				local d = i.Position - startIn
				hudCard.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UIS2.InputEnded:Connect(function(i)
			if drag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i == inp) then drag = false end
		end)
	end
	local function refreshHud()
		if not (hud.ping or hud.ball) then
			if hudGui then hudGui.Enabled = false end
			return
		end
		buildHud()
		hudGui.Enabled = true
		rows.ping.frame.Visible = hud.ping
		rows.speed.frame.Visible = hud.ball
		rows.peak.frame.Visible = hud.ball
	end
	task.spawn(function()
		while true do
			task.wait(0.15)
			if hudGui and hudGui.Enabled and rows then
				if hud.ping then
					local ping = 0
					pcall(function() ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
					local col = ping > 300 and Color3.fromRGB(255, 90, 100) or ping > 150 and Color3.fromRGB(255, 180, 64) or Color3.fromRGB(90, 230, 140)
					rows.ping.val.Text = ping .. " ms"
					rows.ping.dot.BackgroundColor3 = col
				end
				if hud.ball then
					local speed = 0
					local ball
					pcall(function() ball = System.ball.get() end)
					if ball then
						if ball ~= hud.lastBall then hud.lastBall, hud.peak = ball, 0 end
						pcall(function()
							local z = ball:FindFirstChild("zoomies")
							speed = math.floor(((z and z.VectorVelocity) or ball.AssemblyLinearVelocity).Magnitude + 0.5)
						end)
						if speed > hud.peak then hud.peak = speed end
					end
					rows.speed.val.Text = tostring(speed)
					rows.peak.val.Text = tostring(hud.peak)
				end
			end
		end
	end)
	local GH = VisualTab:create_group("HUD", "right")
	GH:create_toggle("VIREX_HUD_Ping", { title = "Real Ping", description = "Your ping on screen", default = false, callback = function(v) hud.ping = v refreshHud() end })
	GH:create_toggle("VIREX_HUD_Ball", { title = "Ball Stats", description = "Ball speed and top speed", default = false, callback = function(v) hud.ball = v refreshHud() end })

	-- ===== Skin Changer (espada) =====
	local GS = CosmeticsTab:create_group("Skin Changer", "left")
	local function applySword()
		if getgenv().skinChanger and type(getgenv().swordModel) == "string" and getgenv().swordModel ~= "" and getgenv().updateSword then
			pcall(getgenv().updateSword)
		end
	end
	local sc = GS:create_toggle("VIREX_SkinChanger", { title = "Skin Changer", description = "Use any sword (only you see it)", default = false, callback = function(v)
		getgenv().skinChanger = v
		getgenv().skinChangerEnabled = v
		applySword()
	end })
	local sn = GS:create_textbox("VIREX_SkinChanger_Sword", { title = "Sword Name", description = "Exact name, e.g. DualPrince", placeholder = "Sword name", default = "", callback = function(text)
		text = tostring(text or ""):match("^%s*(.-)%s*$")
		if text == "" then return end
		getgenv().swordModel = text
		getgenv().swordAnimations = text
		getgenv().swordFX = text
		applySword()
		if getgenv().saveLastEquippedSword then pcall(getgenv().saveLastEquippedSword, text) end
	end })
	UI:link(sc, { sn }, false)
end

-- ===================== MUSIC: tu musica dentro del juego (solo la oyes tu) =====================
do
	-- lista de canciones: nombre y enlace directo al mp3 (catbox / github raw)
	-- "data" = la cancion va dentro del script (no caduca); "url" = enlace directo (files.catbox.moe / github)
	local SONGS = {
		-- se prueba cada link en orden: el primero que sea musica de verdad es el que suena
		{ name = "Song 1", urls = {
			"https://raw.githubusercontent.com/virexx55/music/main/8ec0a9f3-09a1-4bc1-a0aa-ab948dc17e7c.ogg",
			"https://github.com/virexx55/music/raw/main/8ec0a9f3-09a1-4bc1-a0aa-ab948dc17e7c.ogg",
		} },
		{ name = "Pursuit (Slowed)", urls = { "https://raw.githubusercontent.com/virexx55/music/main/pursuit.ogg" } },
		{ name = "Lucid Dreams (Slowed)", urls = { "https://raw.githubusercontent.com/virexx55/music/main/lucid_dreams.ogg" } },
		{ name = "Clarity (Sped Up)", urls = { "https://raw.githubusercontent.com/virexx55/music/main/clarity.ogg" } },
		{ name = "Mood", urls = { "https://raw.githubusercontent.com/virexx55/music/main/mood.ogg" } },
		{ name = "Goated", urls = { "https://raw.githubusercontent.com/virexx55/music/main/goated.ogg" } },
	}
	local function b64dec(str)
		local native
		pcall(function() native = (crypt and (crypt.base64decode or (crypt.base64 and crypt.base64.decode))) or base64_decode end)
		if native then
			local ok, r = pcall(native, str)
			if ok and type(r) == "string" and #r > 0 then return r end
		end
		local map, chars = {}, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		for i = 1, 64 do map[chars:byte(i)] = i - 1 end
		local out, n = {}, 0
		for i = 1, #str, 4 do
			local a, b, c, d = str:byte(i, i + 3)
			a, b = map[a], map[b]
			c = c and map[c]
			d = d and map[d]
			if not a or not b then break end
			local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
			n += 1 out[n] = string.char(math.floor(v / 65536) % 256)
			if c then n += 1 out[n] = string.char(math.floor(v / 256) % 256) end
			if d then n += 1 out[n] = string.char(v % 256) end
			if n % 20000 == 0 then task.wait() end
		end
		return table.concat(out)
	end
	local names = {}
	for i, sng in ipairs(SONGS) do names[i] = sng.name end
	local M = { idx = 1, vol = 0.5, loop = true, playing = false }
	local sound = Instance.new("Sound")
	sound.Name = "VIREX_Music"
	sound.Volume = M.vol
	sound.Looped = true
	pcall(function() sound.Parent = game:GetService("SoundService") end)
	local cache = {}
	local function fileFor(url)
		local h = 0
		for i = 1, #url do h = (h * 31 + url:byte(i)) % 2147483647 end
		return "VIREX/music_" .. h .. ".mp3"
	end
	local function good(d)
		if type(d) ~= "string" or #d < 20000 then return false end
		local a, b = d:byte(1, 2)
		return d:sub(1, 3) == "ID3" or (a == 255 and b and b >= 224) or d:sub(1, 4) == "OggS"
	end
	-- descarga una vez, la guarda en el executor y la usa como sonido
	local function load(i)
		local sng = SONGS[i]
		if not sng then return nil end
		if cache[i] then return cache[i] end
		local custom = getcustomasset or getsynasset
		if not (custom and writefile and isfile) then return nil, "Your executor can't play custom music" end
		pcall(function() if makefolder and isfolder and not isfolder("VIREX") then makefolder("VIREX") end end)
		local urls = sng.urls or { sng.url }
		local path, lastErr
		for _, url in ipairs(urls) do
			local pth = fileFor(url)
			local have = false
			pcall(function() have = isfile(pth) and good(readfile(pth)) end)
			if not have then
				print("[VIREX Music] downloading " .. url)
				local ok, data = pcall(function() return game:HttpGet(url) end)
				if not ok then
					print("[VIREX Music] download failed: " .. tostring(data))
					lastErr = "Download failed (bad link?)"
				elseif not good(data) then
					print("[VIREX Music] not music, got " .. tostring(type(data) == "string" and #data or 0) .. " bytes: " .. tostring(type(data) == "string" and data:sub(1, 40) or ""))
					lastErr = "Link is not an mp3 / ogg"
				else
					local okW = pcall(writefile, pth, data)
					if okW then have = true else lastErr = "Your executor can't save the song" end
				end
			end
			if have then path = pth break end
		end
		if not path then return nil, lastErr or "Could not load the song" end
		local ok, id = pcall(custom, path)
		print("[VIREX Music] asset: " .. tostring(id))
		if ok and type(id) == "string" and id ~= "" then cache[i] = id return id end
		return nil, "Your executor can't load the song"
	end
	local playBtn
	local function setPlaying(on)
		M.playing = on
		if playBtn then pcall(function() playBtn.set(on) end) end
	end
	local function play(i)
		M.idx = i or M.idx
		task.spawn(function()
			local id, err = load(M.idx)
			if not id then
				UI:notify({ title = "Music", text = err or "Could not load the song", duration = 3 })
				setPlaying(false)
				return
			end
			sound:Stop()
			sound.SoundId = id
			sound.Looped = M.loop
			sound.Volume = M.vol
			sound:Play()
			setPlaying(true)
			-- comprobar que de verdad suena
			local t0 = os.clock()
			while os.clock() - t0 < 6 and not sound.IsLoaded do task.wait(0.2) end
			if sound.IsLoaded and sound.TimeLength > 0 then
				if not sound.IsPlaying then sound:Play() end
				UI:notify({ title = "Now Playing", text = SONGS[M.idx].name, icon = "check", duration = 2.5 })
			else
				print("[VIREX Music] Roblox could not open the file (IsLoaded=" .. tostring(sound.IsLoaded) .. ")")
				UI:notify({ title = "Music", text = "Roblox can't play this file, try another mp3", duration = 3.5 })
				setPlaying(false)
			end
		end)
	end
	local function stop()
		sound:Stop()
		setPlaying(false)
	end
	-- al acabar (sin repetir): pasa a la siguiente
	sound.Ended:Connect(function()
		if M.playing and not M.loop then play(M.idx % #SONGS + 1) end
	end)
	-- boton flotante MUSIC: tocar para poner / quitar
	pcall(function()
		playBtn = VIREX_MakeActionButton({ name = "VIREX_MusicButton", label = "MUSIC", activeLabel = "PLAYING", yOffset = 250, onToggle = function(on)
			if on then play() else stop() end
			return on
		end })
	end)

	local G = MiscTab:create_group("Music", "right")
	local pt = G:create_toggle(nil, { title = "Play Music", description = "Only you can hear it", default = false, callback = function(v)
		if v then play() else stop() end
	end })
	local song = G:create_dropdown("VIREX_Music_Song", { title = "Song", options = names, default = names[1], callback = function(v)
		local i = table.find(names, v) or 1
		M.idx = i
		if M.playing then play(i) end
	end })
	local vol = G:create_slider("VIREX_Music_Volume", { title = "Volume", minimum = 0, maximum = 100, default = 50, rounding = true, suffix = "%", callback = function(v)
		M.vol = v / 100
		sound.Volume = M.vol
	end })
	local lp = G:create_toggle("VIREX_Music_Loop", { title = "Loop", description = "Repeat the same song", default = true, callback = function(v)
		M.loop = v
		sound.Looped = v
	end })
	local nx = G:create_button(nil, { title = "Next Song", button_text = "Next", callback = function()
		play(M.idx % #SONGS + 1)
	end })
	local mb = G:create_toggle("VIREX_Music_Button", { title = "Music Button", description = "Button on screen to play / stop", default = false, callback = function(v)
		if playBtn then pcall(function() playBtn.show(v, M.playing) end) end
	end })
	UI:link(pt, { song, vol, lp, nx, mb }, false)
end

-- ===================== REWARDS: reclamar recompensas y girar en la tienda =====================
-- Pulsa los botones del propio juego (como si los tocaras tu), asi usa la logica del juego.
do
	local LP = game:GetService("Players").LocalPlayer
	local RS = game:GetService("ReplicatedStorage")
	local function lower(x) return string.lower(tostring(x or "")) end
	local function btnText(b)
		local t = ""
		pcall(function() if b:IsA("TextButton") then t = b.Text end end)
		if t == "" then
			for _, d in ipairs(b:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then t = d.Text break end
			end
		end
		return lower((t:gsub("<[^>]+>", ""))):match("^%s*(.-)%s*$") or ""
	end
	local function path(inst)
		local parts, cur = {}, inst
		while cur and cur ~= game and #parts < 8 do table.insert(parts, 1, cur.Name) cur = cur.Parent end
		return table.concat(parts, ".")
	end
	local function ancestorHas(inst, words)
		local cur = inst.Parent
		while cur and cur ~= LP and cur ~= game do
			local n = lower(cur.Name)
			for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end
			cur = cur.Parent
		end
		return false
	end
	-- "pulsar" un boton: dispara lo que el juego conecto a ese boton
	local function press(b)
		local fired = false
		if getconnections then
			for _, sigName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) do
				pcall(function()
					for _, c in ipairs(getconnections(b[sigName])) do
						pcall(function()
							if c.Fire then c:Fire() elseif c.Function then c.Function() end
						end)
						fired = true
					end
				end)
			end
		end
		if not fired and firesignal then
			pcall(function() firesignal(b.MouseButton1Click) fired = true end)
			pcall(function() firesignal(b.Activated) end)
		end
		return fired
	end
	-- solo botones que de verdad se ven en pantalla (asi no abre ventanas del juego)
	local function onScreen(b)
		local cur = b
		while cur and not cur:IsA("PlayerGui") do
			if cur:IsA("GuiObject") and not cur.Visible then return false end
			if cur:IsA("LayerCollector") and not cur.Enabled then return false end
			cur = cur.Parent
		end
		local ok, sz = pcall(function() return b.AbsoluteSize end)
		return ok and sz.X > 4 and sz.Y > 4
	end
	local REWARD_WORDS = { "daily", "reward", "login", "streak", "playtime", "gift", "quest", "free" }
	local function findButtons(test)
		local out = {}
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if not pg then return out end
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("GuiButton") and test(d, btnText(d)) then out[#out + 1] = d end
		end
		return out
	end

	local CLAIM_WORDS = { ["claim"] = true, ["claim!"] = true, ["collect"] = true, ["claim reward"] = true, ["claim all"] = true, ["redeem"] = true }
	local function isClaim(b, t)
		if not (CLAIM_WORDS[t] == true or (t:find("claim", 1, true) ~= nil and #t <= 14)) then return false end
		if not b then return true end
		return onScreen(b) and ancestorHas(b, REWARD_WORDS)
	end
	local function claimRemotes()
		for _, r in ipairs(RS:GetDescendants()) do
			if r:IsA("RemoteFunction") or r:IsA("RemoteEvent") then
				local n = lower(r.Name)
				if n:find("claim", 1, true) and (n:find("daily", 1, true) or n:find("login", 1, true) or n:find("reward", 1, true) or n:find("streak", 1, true) or n:find("playtime", 1, true) or n:find("gift", 1, true)) then
					task.spawn(function()
						pcall(function() if r:IsA("RemoteFunction") then r:InvokeServer() else r:FireServer() end end)
					end)
				end
			end
		end
	end

	local SPIN_WORDS = { ["spin"] = true, ["spin!"] = true, ["open"] = true, ["roll"] = true, ["spin x1"] = true, ["open x1"] = true, ["1x"] = true, ["x1"] = true, ["unbox"] = true }
	local SHOP_WORDS = {
		Swords = { "sword", "blade", "crate", "spin", "wheel" },
		Powers = { "abilit", "power", "explosion", "crate", "spin", "wheel" },
		Any = { "sword", "abilit", "power", "explosion", "crate", "spin", "wheel", "shop", "case" },
	}
	local spin = { on = false, shop = "Swords", delay = 5 }
	local function isSpin(b, t)
		if not (SPIN_WORDS[t] or (t:find("spin", 1, true) and #t <= 12)) then return false end
		return onScreen(b) and ancestorHas(b, SHOP_WORDS[spin.shop] or SHOP_WORDS.Any)
	end

	local claimOn = false
	-- lento y seguro: cada ~4 min, un boton cada 3-6 s, sin disparar remotes a ciegas
	-- tambien reclama por los remotes del juego (sin abrir ninguna ventana), uno cada pocos segundos
	local lastRemoteClaim = 0
	local function claimPass()
		if os.clock() - lastRemoteClaim > 300 then
			lastRemoteClaim = os.clock()
			for _, r in ipairs(RS:GetDescendants()) do
				if not claimOn then break end
				if r:IsA("RemoteFunction") or r:IsA("RemoteEvent") then
					local n = lower(r.Name)
					if n:find("claim", 1, true) and (n:find("daily", 1, true) or n:find("login", 1, true) or n:find("reward", 1, true) or n:find("streak", 1, true) or n:find("playtime", 1, true) or n:find("gift", 1, true) or n:find("quest", 1, true)) then
						print("[VIREX] Auto Claim remote: " .. path(r))
						task.spawn(function()
							pcall(function() if r:IsA("RemoteFunction") then r:InvokeServer() else r:FireServer() end end)
						end)
						task.wait(math.random(30, 60) / 10)
					end
				end
			end
		end
		for _, b in ipairs(findButtons(isClaim)) do
			if not claimOn then return end
			if press(b) then print("[VIREX] Auto Claim: " .. path(b)) end
			task.wait(math.random(30, 60) / 10)
		end
	end
	local _ = claimRemotes
	task.spawn(function()
		while true do
			task.wait(240 + math.random(0, 40))
			if claimOn then pcall(claimPass) end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(math.max(spin.delay, 3) + math.random(0, 15) / 10)
			if spin.on then
				local list = findButtons(isSpin)
				if list[1] and press(list[1]) then print("[VIREX] Auto Spin: " .. path(list[1])) end
			end
		end
	end)

	local G = MiscTab:create_group("Rewards", "left")
	G:create_toggle("VIREX_AutoClaim", { title = "Auto Claim Rewards", description = "Slowly claims rewards that are on screen", default = false, callback = function(state)
		claimOn = state
		if state then task.delay(2, function() if claimOn then pcall(claimPass) end end) end
	end })
	local sp = G:create_toggle("VIREX_AutoSpin", { title = "Auto Spin", description = "Spins in the sword / power shop", default = false, callback = function(state)
		spin.on = state
		if state then UI:notify({ title = "Auto Spin", text = "Open the spin screen, it spins slowly by itself", duration = 3 }) end
	end })
	local shop = G:create_dropdown("VIREX_AutoSpin_Shop", { title = "Shop", options = { "Swords", "Powers", "Any" }, default = "Swords", callback = function(v) spin.shop = v end })
	local dl = G:create_slider("VIREX_AutoSpin_Delay", { title = "Spin Delay", minimum = 3, maximum = 20, default = 5, rounding = true, suffix = "s", callback = function(v) spin.delay = v end })
	UI:link(sp, { shop, dl }, true)
	-- por si no encuentra nada: lista en la consola (F9) los botones y remotes posibles
	G:create_button(nil, { title = "Scan Shop", description = "Lists spin / claim buttons in F9", button_text = "Scan", callback = function()
		local n = 0
		print("[VIREX] ===== SCAN: botones =====")
		for _, b in ipairs(findButtons(function(_, t) return t ~= "" and (isClaim(nil, t) or SPIN_WORDS[t] or t:find("spin", 1, true) or t:find("open", 1, true) or t:find("buy", 1, true)) end)) do
			n += 1
			print("  [" .. btnText(b) .. "]  " .. path(b))
		end
		print("[VIREX] ===== SCAN: remotes =====")
		for _, r in ipairs(RS:GetDescendants()) do
			if r:IsA("RemoteFunction") or r:IsA("RemoteEvent") then
				local nm = lower(r.Name)
				for _, w in ipairs({ "claim", "daily", "reward", "spin", "crate", "wheel", "roll", "unbox", "purchase", "buy" }) do
					if nm:find(w, 1, true) then n += 1 print("  " .. r.ClassName .. "  " .. path(r)) break end
				end
			end
		end
		UI:notify({ title = "Scan", text = n .. " found. Open console (F9) and send me a photo", duration = 4 })
	end })
end

-- ===================== WORLD VIEW: textura del mapa y filtro de color (solo lo ves tu) =====================
do
	local Lighting = game:GetService("Lighting")
	local TEX = {
		Smooth = Enum.Material.SmoothPlastic, Neon = Enum.Material.Neon, Glass = Enum.Material.Glass,
		ForceField = Enum.Material.ForceField, Ice = Enum.Material.Ice, Marble = Enum.Material.Marble,
		Metal = Enum.Material.DiamondPlate, Sand = Enum.Material.Sand, Wood = Enum.Material.WoodPlanks,
	}
	local TEX_NAMES = { "Default", "Smooth", "Neon", "Glass", "ForceField", "Ice", "Marble", "Metal", "Sand", "Wood" }
	local cur = "Default"
	local orig = setmetatable({}, { __mode = "k" })
	local decals = setmetatable({}, { __mode = "k" })
	-- no se tocan personajes, balones ni cosas de VIREX
	local function skip(part)
		if part.Name:sub(1, 6) == "VIREX_" then return true end
		local cam = workspace.CurrentCamera
		if cam and part:IsDescendantOf(cam) then return true end
		for _, n in ipairs({ "Alive", "Dead", "Balls", "TrainingBalls" }) do
			local f = workspace:FindFirstChild(n)
			if f and part:IsDescendantOf(f) then return true end
		end
		local m = part:FindFirstAncestorOfClass("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then return true end
		return false
	end
	local function applyOne(d)
		if d:IsA("BasePart") then
			if skip(d) then return end
			if not orig[d] then
				local okV, var = pcall(function() return d.MaterialVariant end)
				orig[d] = { d.Material, okV and var or "" }
			end
			local m = TEX[cur]
			if m then
				pcall(function() d.MaterialVariant = "" end)
				d.Material = m
			else
				d.Material = orig[d][1]
				pcall(function() d.MaterialVariant = orig[d][2] end)
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			-- con una textura nueva se esconden las texturas pegadas del mapa (y vuelven en Default)
			local p = d.Parent
			if p and p:IsA("BasePart") and skip(p) then return end
			if decals[d] == nil then decals[d] = d.Transparency end
			d.Transparency = (cur ~= "Default") and 1 or decals[d]
		end
	end
	local applyId = 0
	local function applyAll()
		applyId += 1
		local my = applyId
		task.spawn(function()
			local list = workspace:GetDescendants()
			for i, d in ipairs(list) do
				if my ~= applyId then return end
				pcall(applyOne, d)
				if i % 700 == 0 then task.wait() end -- sin congelar el juego
			end
		end)
	end
	-- mapas nuevos (cada ronda) tambien cambian
	workspace.DescendantAdded:Connect(function(d)
		if cur ~= "Default" and (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) then
			task.defer(function() pcall(applyOne, d) end)
		end
	end)

	-- filtros de color
	local FILTERS = {
		Default = nil,
		Vivid = { tint = Color3.fromRGB(255, 255, 255), sat = 0.35, con = 0.12, bri = 0 },
		Cinematic = { tint = Color3.fromRGB(255, 238, 222), sat = -0.15, con = 0.22, bri = -0.03 },
		Night = { tint = Color3.fromRGB(185, 198, 255), sat = -0.12, con = 0.14, bri = -0.08 },
		Purple = { tint = Color3.fromRGB(222, 190, 255), sat = 0.1, con = 0.1, bri = -0.02 },
		Warm = { tint = Color3.fromRGB(255, 222, 196), sat = 0.08, con = 0.06, bri = 0 },
		Ice = { tint = Color3.fromRGB(205, 235, 255), sat = -0.05, con = 0.08, bri = 0.02 },
		["Black & White"] = { tint = Color3.fromRGB(255, 255, 255), sat = -1, con = 0.15, bri = 0 },
	}
	local FILTER_NAMES = { "Default", "Vivid", "Cinematic", "Night", "Purple", "Warm", "Ice", "Black & White" }
	local cc
	local function setFilter(name)
		local f = FILTERS[name]
		if not f then
			if cc then pcall(function() cc:Destroy() end) cc = nil end
			return
		end
		if not cc or not cc.Parent then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "VIREX_ViewFilter"
			cc.Parent = Lighting
		end
		cc.TintColor, cc.Saturation, cc.Contrast, cc.Brightness = f.tint, f.sat, f.con, f.bri
	end

	local G = VisualTab:create_group("World View", "left")
	G:create_dropdown("VIREX_View_Texture", { title = "Map Texture", description = "Change the look of the map", options = TEX_NAMES, default = "Default", callback = function(v)
		cur = v
		applyAll()
	end })
	G:create_dropdown("VIREX_View_Filter", { title = "Color Filter", description = "Color style of the game", options = FILTER_NAMES, default = "Default", callback = function(v)
		pcall(setFilter, v)
	end })
end

-- ===================== CONFIG: tamaño, colores y letra del UI =====================
do
	local G = ConfigTab:create_group("Interface", "left")
	UI._sizeSlider = G:create_slider("VIREX_UI_Size", { title = "UI Size", description = "Or drag the corner of the panel", minimum = 60, maximum = 150, default = 100, rounding = true, suffix = "%", callback = function(v)
		pcall(function() UI:set_ui_scale(v) end)
	end })
	G:create_dropdown("VIREX_UI_Accent", { title = "UI Color", description = "Color of buttons and glass", options = UI:accent_names(), default = "Blue", callback = function(v)
		pcall(function() UI:set_accent(v) end)
	end })
	G:create_dropdown("VIREX_UI_Background", { title = "Background", description = "Color behind the panel", options = UI:background_names(), default = "Dark", callback = function(v)
		pcall(function() UI:set_background(v) end)
	end })
	G:create_dropdown("VIREX_UI_Font", { title = "Font", description = "Letter style of the whole UI", options = UI:font_names(), default = "Code", callback = function(v)
		pcall(function() UI:set_font(v) end)
	end })
	G:create_toggle("VIREX_UI_PanelImage", { title = "Panel Image", description = "Picture behind the panel", default = true, callback = function(v)
		pcall(function() UI:set_panel_image(v) end)
	end })
end

-- ===================== CONFIG: guardado automatico + tu Discord =====================
do
	local DISCORD = "https://discord.gg/virexs"
	local G = ConfigTab:create_group("Config", "right")
	G:create_toggle(nil, { title = "Auto Save", description = "Saves every change and loads it next time", default = UI:get_autosave(), callback = function(state)
		UI:set_autosave(state)
		UI:notify({ title = state and "Auto Save On" or "Auto Save Off", text = state and "Every change is saved automatically" or "Changes won't be saved", icon = state and "check" or nil, duration = 2.2 })
	end })
	G:create_button(nil, { title = "Save Now", description = "Save your settings right now", button_text = "Save", callback = function()
		local ok = UI:save_now()
		UI:notify({ title = ok and "Saved" or "Not Saved", text = ok and "Your settings are saved" or "Your executor can't save files", icon = ok and "check" or nil, duration = 2.5 })
	end })
	G:create_button(nil, { title = "Reset Config", description = "Back to default next time you execute", button_text = "Reset", callback = function()
		local ok = UI:reset_config()
		UI:notify({ title = ok and "Config Reset" or "Not Saved", text = ok and "Re-execute to start from default" or "Your executor can't save files", icon = ok and "check" or nil, duration = 3 })
	end })
	local D = ConfigTab:create_group("Discord", "right")
	D:create_button(nil, { title = "discord.gg/virexs", description = "Updates, support and new scripts", button_text = "Copy", callback = function()
		local fn = setclipboard or toclipboard
		local ok = fn and pcall(fn, DISCORD)
		UI:notify({ title = "Discord", text = ok and "Link copied! Paste it in your browser" or DISCORD, duration = 3 })
	end })
end

end)()

pcall(function() getgenv().VIREX_LoadSet(92, "Starting") end)
task.delay(0.15, _HOTHX_startRemoteCapture)

-- grupos repartidos entre las dos columnas (cuando ya existen todos)
pcall(function()
	task.wait()
	UI:rebalance()
end)
getgenv().VIREX_LoadDone()

end)
