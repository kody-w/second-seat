--!strict
--[[
	WorldImporter.luau — rebuild the Second Seat nexus inside Roblox from world.json.

	This is not a port of the browser code. It is the same WORLD, re-derived from
	the same spec: ship the frame, let the destination rebuild. Give it world.json
	and it produces the same five realms, the same skylines, the same waypoints,
	the same portal and the same crowd — because it runs the same seeded RNG in
	the same consumption order, not because anything was copied across.

	HOW TO USE (Studio)
	  1. Put this file in ServerScriptService as a Script (or require it from one).
	  2. Either enable HttpService and let it fetch world.json from the live page,
	     or paste world.json into a ModuleScript and pass the table to build().
	  3. Press Play. The realm builds under workspace.SecondSeat.

	     local Importer = require(script.WorldImporter)
	     Importer.build(1)            -- realm index, 1..5
	     Importer.buildAll()          -- all five, offset apart

	WHAT THIS DOES NOT DO, deliberately: no recording, no OAuth, no localStorage
	frame chain. Those are listed under `does_not_port` in world.json and each one
	needs a Roblox-native answer (capture, player identity, DataStore) rather than
	a translation. Do not fake them.
]]

local HttpService = game:GetService("HttpService")

local WORLD_URL = "https://kody-w.github.io/second-seat/world.json"

local Importer = {}

-- ── the shared RNG ──────────────────────────────────────────────────────────
-- A 31-bit LCG. The browser build consumes it in a fixed order, so as long as
-- this consumes it in the SAME order from the SAME seed, both engines lay out
-- an identical world. (JS `&` coerces through ToInt32; bit32.band reduces mod
-- 2^32 the same way, so the sequences agree.)
local function makeRng(seed: number)
	local s = seed
	return function(): number
		s = bit32.band(s * 1103515245 + 12345, 0x7fffffff)
		return s / 0x7fffffff
	end
end

local function hexColor(hex: string): Color3
	return Color3.fromHex(hex)
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Roblox has no torus primitive, so a ring is built from segments. Same radius,
-- same tube thickness, same place in the world — it reads as the same marker.
local function ring(radius: number, tube: number, segments: number, cf: CFrame,
	color: Color3, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Ring"
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		local seg = 2 * math.pi * radius / segments
		local off = CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0)
			* CFrame.Angles(0, 0, a)
		part("Seg", Vector3.new(tube * 2, seg * 1.1, tube * 2), cf * off, color, m)
	end
	m.Parent = parent
	return m
end

-- ── the build ───────────────────────────────────────────────────────────────
function Importer.buildFrom(world, realmIndex: number, origin: Vector3): Model
	local realm = world.realms[realmIndex]
	assert(realm, "no such realm: " .. tostring(realmIndex))

	local root = Instance.new("Model")
	root.Name = "Realm_" .. realm.name:gsub("%s+", "_")

	local rng = makeRng(world.rng.default_seed)
	-- Realms before this one consumed the stream first; burn their draws so the
	-- layout matches the browser exactly.
	local sk, wp, cr = world.skyline, world.waypoints, world.crowd
	for _ = 1, realmIndex - 1 do
		for _ = 1, sk.count do for _ = 1, 6 do rng() end end
		rng()                                             -- the waypoint spin
		for _ = 1, wp.count do rng(); rng() end           -- radius, height
		for _ = 1, cr.count do rng(); rng(); rng() end    -- angle, radius, speed
	end

	local lo, hi = hexColor(realm.lo), hexColor(realm.hi)
	local air = hexColor(realm.air)

	local ground = part("Ground",
		Vector3.new(world.ground.size, 1, world.ground.size),
		CFrame.new(origin + Vector3.new(0, world.ground.y - 0.5, 0)),
		hexColor(realm.ground), root)
	ground.CanCollide = true

	-- skyline: height scales by the realm's `tall`, exactly as the browser does
	local spires = Instance.new("Folder"); spires.Name = "Skyline"; spires.Parent = root
	for _ = 1, sk.count do
		local h = (sk.height_min + rng() * sk.height_range) * realm.tall
		local isHi = rng() > (1 - sk.hi_colour_chance)
		local w = sk.width_min + rng() * sk.width_range
		local d = sk.depth_min + rng() * sk.depth_range
		local a = rng() * math.pi * 2
		local r = sk.radius_min + rng() * sk.radius_range
		part("Spire", Vector3.new(w, h, d),
			CFrame.new(origin + Vector3.new(math.cos(a) * r, h / 2, math.sin(a) * r)),
			isHi and hi or lo, spires)
	end

	-- waypoints
	local marks = Instance.new("Folder"); marks.Name = "Waypoints"; marks.Parent = root
	local spin = rng() * math.pi * 2
	local plan = {}
	for b = 1, wp.count do
		local ang = spin + ((b - 1) / wp.count) * math.pi * 2
		local rad = wp.radius_min + rng() * wp.radius_range
		local y = wp.height_min + rng() * wp.height_range
		local pos = origin + Vector3.new(math.cos(ang) * rad, y, math.sin(ang) * rad)
		plan[b] = { name = wp.names[b], position = pos }
		local r = ring(wp.ring_radius, wp.ring_tube, 24,
			CFrame.new(pos) * CFrame.Angles(-math.pi / 2, 0, 0), hi, marks)
		r.Name = wp.names[b]
	end
	root:SetAttribute("Waypoints", HttpService:JSONEncode(
		(function() local t = {} for i, p in plan do
			t[i] = { name = p.name, x = p.position.X, y = p.position.Y, z = p.position.Z }
		end return t end)()))

	-- the portal: the threshold, and where Heimdall stands
	local pp = world.portal.position
	local portalPos = origin + Vector3.new(pp[1], pp[2], pp[3])
	local portal = ring(world.portal.ring_radius, world.portal.ring_tube, 40,
		CFrame.new(portalPos), air, root)
	portal.Name = "Portal"
	local disc = part("Threshold",
		Vector3.new(world.portal.disc_radius * 2, world.portal.disc_radius * 2, 0.4),
		CFrame.new(portalPos), air, root)
	disc.Transparency = 1 - world.portal.disc_opacity
	disc.Material = Enum.Material.Neon

	-- the crowd: they wander, and they look up
	local crowd = Instance.new("Folder"); crowd.Name = "Crowd"; crowd.Parent = root
	for _ = 1, cr.count do
		local a = rng() * math.pi * 2
		local r = cr.spawn_radius_min + rng() * cr.spawn_radius_range
		local speed = cr.speed_min + rng() * cr.speed_range
		local base = origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)

		local agent = Instance.new("Model"); agent.Name = "Agent"; agent.Parent = crowd
		local torso = part("Torso",
			Vector3.new(cr.torso[1], cr.torso[2], cr.torso[3]),
			CFrame.new(base + Vector3.new(0, cr.torso_y, 0)), lo, agent)
		local head = part("Head",
			Vector3.new(cr.head[1], cr.head[2], cr.head[3]),
			CFrame.new(base + Vector3.new(0, cr.head_y, 0)), lo, agent)
		agent.PrimaryPart = torso
		agent:SetAttribute("Speed", speed)
		agent:SetAttribute("Watching", false)
		head.Name = "Head"
	end

	root:SetAttribute("Realm", realm.name)
	root:SetAttribute("SeeRange", cr.see_range)
	root:SetAttribute("Air", realm.air)
	return root
end

-- ── the crowd's one behaviour: look up ──────────────────────────────────────
-- Same rule as the browser: within see_range horizontally AND the craft above
-- see_requires_craft_above_y. The head tilts by the real elevation angle.
function Importer.bindCrowd(root: Model, world, craft: BasePart)
	local cr = world.crowd
	local watchColor = Color3.fromHex(root:GetAttribute("Air") :: string)
	local idleColor = (root:FindFirstChild("Crowd") :: Folder)
		:FindFirstChildOfClass("Model"):FindFirstChild("Torso") :: Part
	local idle = idleColor.Color

	game:GetService("RunService").Heartbeat:Connect(function(dt)
		for _, agent in (root.Crowd :: Folder):GetChildren() do
			local torso = agent:FindFirstChild("Torso") :: Part?
			local head = agent:FindFirstChild("Head") :: Part?
			if not torso or not head then continue end

			local d = craft.Position - torso.Position
			local flat = Vector3.new(d.X, 0, d.Z).Magnitude
			local sees = flat < cr.see_range
				and craft.Position.Y > cr.see_requires_craft_above_y

			if sees then
				local elev = math.atan2(craft.Position.Y - cr.head_y, math.max(1, flat))
				head.CFrame = CFrame.new(head.Position)
					* CFrame.Angles(math.min(cr.head_tilt_max_rad, elev), 0, 0)
				torso.CFrame = CFrame.lookAt(torso.Position,
					Vector3.new(craft.Position.X, torso.Position.Y, craft.Position.Z))
			end
			if agent:GetAttribute("Watching") ~= sees then
				agent:SetAttribute("Watching", sees)
				torso.Color = sees and watchColor or idle
				head.Color = sees and watchColor or idle
			end
		end
	end)
end

-- ── the flight model, unchanged ─────────────────────────────────────────────
-- Six controls and nothing else. A player writes into them; so does the
-- autopilot. Neither has a privileged path — that invariant is the whole point
-- and it must survive the port.
export type Controls = { fwd: number, back: number, left: number, right: number,
	up: number, boost: number }

function Importer.newFlight(world)
	local f = world.flight
	local state = {
		position = Vector3.new(world.craft.spawn[1], world.craft.spawn[2], world.craft.spawn[3]),
		velocity = Vector3.zero,
		heading = world.craft.spawn_heading_rad,
	}
	function state.step(controls: Controls, dt: number)
		state.heading += (controls.left - controls.right) * f.turn_rate_rad_s * dt
		local fwd = Vector3.new(math.sin(state.heading), 0, math.cos(state.heading))
		local thrust = (controls.fwd - controls.back)
			* (controls.boost == 1 and f.thrust_boost or f.thrust)
		state.velocity += fwd * (thrust * dt)
		state.velocity += Vector3.new(0, (controls.up == 1 and f.climb or f.gravity) * dt, 0)
		state.velocity *= f.drag_per_second ^ dt          -- frame-rate independent
		state.position += state.velocity * dt
		if state.position.Y < f.floor_y then
			state.position = Vector3.new(state.position.X, f.floor_y, state.position.Z)
			if state.velocity.Y < 0 then
				state.velocity = Vector3.new(state.velocity.X, 0, state.velocity.Z)
			end
		end
	end
	return state
end

-- The autopilot writes into the same six values a player would.
function Importer.autopilot(world, state, target: Vector3, controls: Controls)
	local a = world.flight.autopilot
	local to = target - state.position
	local want = math.atan2(to.X, to.Z)
	local diff = math.atan2(math.sin(want - state.heading), math.cos(want - state.heading))
	controls.left = diff > a.heading_deadband_rad and 1 or 0
	controls.right = diff < -a.heading_deadband_rad and 1 or 0
	controls.fwd = 1
	controls.back = 0
	controls.up = to.Y > a.climb_when_target_above and 1 or 0
	controls.boost = (to.Magnitude > a.boost_beyond_distance
		and math.abs(diff) < a.boost_max_heading_error_rad) and 1 or 0
end

-- ── entry points ────────────────────────────────────────────────────────────
function Importer.fetchWorld()
	local ok, res = pcall(function()
		return HttpService:JSONDecode(HttpService:GetAsync(WORLD_URL))
	end)
	assert(ok, "could not fetch world.json — enable HttpService, or pass the table "
		.. "to buildFrom() directly. (" .. tostring(res) .. ")")
	return res
end

function Importer.build(realmIndex: number, world)
	world = world or Importer.fetchWorld()
	local holder = workspace:FindFirstChild("SecondSeat")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "SecondSeat"
		holder.Parent = workspace
	end
	local root = Importer.buildFrom(world, realmIndex, Vector3.zero)
	root.Parent = holder

	game:GetService("Lighting").FogColor = Color3.fromHex(world.realms[realmIndex].fog)
	game:GetService("Lighting").FogEnd = 1500
	return root
end

function Importer.buildAll(world)
	world = world or Importer.fetchWorld()
	local holder = Instance.new("Folder")
	holder.Name = "SecondSeat"
	holder.Parent = workspace
	for i = 1, #world.realms do
		-- realms are laid out side by side so all five can be inspected at once;
		-- in play only one is ever live, exactly as the browser keeps one in the
		-- scene graph at a time.
		local root = Importer.buildFrom(world, i, Vector3.new((i - 1) * 4000, 0, 0))
		root.Parent = holder
	end
	return holder
end

return Importer
