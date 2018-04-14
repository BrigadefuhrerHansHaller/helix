
function GM:PlayerInitialSpawn(client)
	client.ixJoinTime = RealTime()

	if (client:IsBot()) then
		local botID = os.time()
		local index = math.random(1, table.Count(ix.faction.indices))
		local faction = ix.faction.indices[index]

		local character = ix.char.New({
			name = client:Name(),
			faction = faction and faction.uniqueID or "unknown",
			model = faction and table.Random(faction.models) or "models/gman.mdl"
		}, botID, client, client:SteamID64())
		character.isBot = true

		local inventory = ix.item.CreateInv(ix.config.Get("invW"), ix.config.Get("invH"), botID)
		inventory:SetOwner(botID)
		inventory.noSave = true

		character.vars.inv = {inventory}

		ix.char.loaded[os.time()] = character

		character:Setup()
		client:Spawn()

		ix.chat.Send(nil, "connect", client:SteamName())

		return
	end

	ix.config.Send(client)
	ix.date.Send(client)

	client:LoadData(function(data)
		if (!IsValid(client)) then return end

		local address = ix.util.GetAddress()
		local noCache = client:GetData("lastIP", address) != address
		client:SetData("lastIP", address)

		netstream.Start(client, "ixDataSync", data, client.ixPlayTime)

		ix.char.Restore(client, function(charList)
			if (!IsValid(client)) then return end

			MsgN("Loaded ("..table.concat(charList, ", ")..") for "..client:Name())

			for _, v in ipairs(charList) do
				ix.char.loaded[v]:Sync(client)
			end

			for _, v in ipairs(player.GetAll()) do
				if (v:GetChar()) then
					v:GetChar():Sync(client)
				end
			end

			client.ixCharList = charList
				netstream.Start(client, "charMenu", charList)
			client.ixLoaded = true

			client:SetData("intro", true)
		end, noCache)

		ix.chat.Send(nil, "connect", client:SteamName())
	end)

	client:SetNoDraw(true)
	client:SetNotSolid(true)
	client:Lock()

	timer.Simple(1, function()
		if (!IsValid(client)) then return end

		client:KillSilent()
		client:StripAmmo()
	end)
end

function GM:PlayerUse(client, entity)
	if (client:GetNetVar("restricted") or (isfunction(entity.GetEntityMenu) and entity:GetClass() != "ix_item")) then
		return false
	end

	return true
end

function GM:KeyPress(client, key)
	if (key == IN_RELOAD) then
		timer.Create("ixToggleRaise"..client:SteamID(), ix.config.Get("wepRaiseTime"), 1, function()
			if (IsValid(client)) then
				client:ToggleWepRaised()
			end
		end)
	elseif (key == IN_USE) then
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local entity = util.TraceLine(data).Entity

		if (IsValid(entity) and hook.Run("PlayerUse", client, entity)) then
			if (entity:IsDoor()) then
				local result = hook.Run("CanPlayerUseDoor", client, entity)

				if (result != false) then
					hook.Run("PlayerUseDoor", client, entity)
				end
			end
		end
	end
end

function GM:KeyRelease(client, key)
	if (key == IN_RELOAD) then
		timer.Remove("ixToggleRaise" .. client:SteamID())
	elseif (key == IN_USE) then
		timer.Remove("ixCharacterInteraction" .. client:SteamID())
	elseif (key == IN_ATTACK) then
		-- hack for engine grenades
		local weapon = client:GetActiveWeapon()

		if (IsValid(weapon)) then
			local ammoName = game.GetAmmoName(weapon:GetPrimaryAmmoType())

			if (ammoName and ammoName:lower() == "grenade") then
				timer.Simple(FrameTime() * 4, function()
					if (client:GetAmmoCount(ammoName) == 0) then
						if (weapon.ixItem and weapon.ixItem.Unequip) then
							weapon.ixItem:Unequip(client, false, true)
						end

						client:StripWeapon(weapon:GetClass())
					end
				end)
			end
		end
	end
end

function GM:CanPlayerInteractItem(client, action, item)
	if (client:GetNetVar("restricted")) then
		return false
	end

	if (action == "drop" and hook.Run("CanPlayerDropItem", client, item) == false) then
		return false
	end

	if (action == "take" and hook.Run("CanPlayerTakeItem", client, item) == false) then
		return false
	end

	if (type(item) == "Entity" and item.ixSteamID and item.ixCharID
	and item.ixSteamID == client:SteamID() and item.ixCharID != client:GetChar():GetID()) then
		client:NotifyLocalized("playerCharBelonging")
		return false
	end

	return client:Alive()
end

function GM:CanPlayerDropItem(client, item)

end

function GM:CanPlayerTakeItem(client, item)

end

function GM:PlayerSwitchWeapon(client, oldWeapon, newWeapon)
	client:SetWepRaised(false)
end

function GM:PlayerShouldTakeDamage(client, attacker)
	return client:GetChar() != nil
end

function GM:GetFallDamage(client, speed)
	return (speed - 580) * (100 / 444)
end

function GM:EntityTakeDamage(entity, dmgInfo)
	if (IsValid(entity.ixPlayer)) then
		if (dmgInfo:IsDamageType(DMG_CRUSH)) then
			if ((entity.ixFallGrace or 0) < CurTime()) then
				if (dmgInfo:GetDamage() <= 10) then
					dmgInfo:SetDamage(0)
				end

				entity.ixFallGrace = CurTime() + 0.5
			else
				return
			end
		end

		entity.ixPlayer:TakeDamageInfo(dmgInfo)
	end
end

function GM:PrePlayerLoadedChar(client, character, lastChar)
	-- Remove all skins
	client:SetBodyGroups("000000000")
	client:SetSkin(0)
end

function GM:PlayerLoadedChar(client, character, lastChar)
	if (lastChar) then
		local charEnts = lastChar:GetVar("charEnts") or {}

		for _, v in ipairs(charEnts) do
			if (v and IsValid(v)) then
				v:Remove()
			end
		end

		lastChar:SetVar("charEnts", nil)
	end

	if (character) then
		for _, v in pairs(ix.class.list) do
			if (v.faction == client:Team() and v.isDefault) then
				character:SetClass(v.index)

				break
			end
		end
	end

	if (IsValid(client.ixRagdoll)) then
		client.ixRagdoll.ixNoReset = true
		client.ixRagdoll.ixIgnoreDelete = true
		client.ixRagdoll:Remove()
	end

	local faction = ix.faction.indices[character:GetFaction()]
	local uniqueID = "ixSalary"..client:UniqueID()

	if (faction and faction.pay and faction.pay > 0) then
		timer.Create(uniqueID, faction.payTime or 300, 0, function()
			if (IsValid(client)) then
				if (hook.Run("CanPlayerEarnSalary", client, faction) != false) then
					local pay = hook.Run("GetSalaryAmount", client, faction) or faction.pay

					character:GiveMoney(pay)
					client:NotifyLocalized("salary", ix.currency.Get(pay))
				end
			else
				timer.Remove(uniqueID)
			end
		end)
	elseif (timer.Exists(uniqueID)) then
		timer.Remove(uniqueID)
	end

	hook.Run("PlayerLoadout", client)
end

function GM:CharacterLoaded(character)
	local client = character:GetPlayer()

	if (IsValid(client)) then
		local uniqueID = "ixSaveChar"..client:SteamID()

		timer.Create(uniqueID, ix.config.Get("saveInterval"), 0, function()
			if (IsValid(client) and client:GetChar()) then
				client:GetChar():Save()
			else
				timer.Remove(uniqueID)
			end
		end)
	end
end

function GM:PlayerSay(client, text)
	local chatType, message, anonymous = ix.chat.Parse(client, text, true)

	if (chatType == "ic") then
		if (ix.command.Parse(client, message)) then
			return ""
		end
	end

	ix.chat.Send(client, chatType, message, anonymous)
	ix.log.Add(client, "chat", chatType and chatType:upper() or "??",
		hook.Run("PlayerMessageSend", client, chatType, message, anonymous) or message
	)

	hook.Run("PostPlayerSay", client, message, chatType, anonymous)

	return ""
end

function GM:CanAutoFormatMessage(client, chatType, message)
	return chatType == "ic" or chatType == "w" or chatType == "y"
end

function GM:PlayerSpawn(client)
	client:SetNoDraw(false)
	client:UnLock()
	client:SetNotSolid(false)
	client:SetRagdolled(false)
	client:SetAction()
	client:SetDSP(1)

	hook.Run("PlayerLoadout", client)
end

-- Shortcuts for (super)admin only things.
local IsAdmin = function(_, client) return client:IsAdmin() end

-- Set the gamemode hooks to the appropriate shortcuts.
GM.PlayerGiveSWEP = IsAdmin
GM.PlayerSpawnEffect = IsAdmin
GM.PlayerSpawnSENT = IsAdmin

function GM:PlayerSpawnNPC(client, npcType, weapon)
	return client:IsAdmin() or client:GetChar():HasFlags("n")
end

function GM:PlayerSpawnSWEP(client, weapon, info)
	return client:IsAdmin()
end

function GM:PlayerSpawnProp(client)
	if (client:GetChar() and client:GetChar():HasFlags("e")) then
		return true
	end

	return false
end

function GM:PlayerSpawnRagdoll(client)
	if (client:GetChar() and client:GetChar():HasFlags("r")) then
		return true
	end

	return false
end

function GM:PlayerSpawnVehicle(client, model, name, data)
	if (client:GetChar()) then
		if (data.Category == "Chairs") then
			return client:GetChar():HasFlags("c")
		else
			return client:GetChar():HasFlags("C")
		end
	end

	return false
end

-- Called when weapons should be given to a player.
function GM:PlayerLoadout(client)
	if (client.ixSkipLoadout) then
		client.ixSkipLoadout = nil

		return
	end

	client:SetWeaponColor(Vector(client:GetInfo("cl_weaponcolor")))
	client:StripWeapons()
	client:SetLocalVar("blur", nil)

	local character = client:GetChar()

	-- Check if they have loaded a character.
	if (character) then
		client:SetupHands()
		-- Set their player model to the character's model.
		client:SetModel(character:GetModel())
		client:Give("ix_hands")
		client:SetWalkSpeed(ix.config.Get("walkSpeed"))
		client:SetRunSpeed(ix.config.Get("runSpeed"))

		local faction = ix.faction.indices[client:Team()]

		if (faction) then
			-- If their faction wants to do something when the player spawns, let it.
			if (faction.OnSpawn) then
				faction:OnSpawn(client)
			end

			-- @todo add docs for player:Give() failing if player already has weapon - which means if a player is given a weapon
			-- here due to the faction weapons table, the weapon's :Give call in the weapon base will fail since the player
			-- will already have it by then. This will cause issues for weapons that have pac data since the parts are applied
			-- only if the weapon returned by :Give() is valid

			-- If the faction has default weapons, give them to the player.
			if (faction.weapons) then
				for _, v in ipairs(faction.weapons) do
					client:Give(v)
				end
			end
		end

		-- Ditto, but for classes.
		local class = ix.class.list[client:GetChar():GetClass()]

		if (class) then
			if (class.OnSpawn) then
				class:OnSpawn(client)
			end

			if (class.weapons) then
				for _, v in ipairs(class.weapons) do
					client:Give(v)
				end
			end
		end

		-- Apply any flags as needed.
		ix.flag.OnSpawn(client)
		ix.attributes.Setup(client)

		hook.Run("PostPlayerLoadout", client)

		client:SelectWeapon("ix_hands")
	else
		client:SetNoDraw(true)
		client:Lock()
		client:SetNotSolid(true)
	end
end

function GM:PostPlayerLoadout(client)
	-- Reload All Attrib Boosts
	local character = client:GetCharacter()

	if (character:GetInv()) then
		for _, v in pairs(character:GetInv():GetItems()) do
			v:Call("OnLoadout", client)

			if (v:GetData("equip") and v.attribBoosts) then
				for attribKey, attribValue in pairs(v.attribBoosts) do
					character:AddBoost(v.uniqueID, attribKey, attribValue)
				end
			end
		end
	end
end

local deathSounds = {
	Sound("vo/npc/male01/pain07.wav"),
	Sound("vo/npc/male01/pain08.wav"),
	Sound("vo/npc/male01/pain09.wav")
}

function GM:DoPlayerDeath(client, attacker, damageinfo)
	client:AddDeaths(1)

	if (hook.Run("ShouldSpawnClientRagdoll", client) != false) then
		client:CreateRagdoll()
	end

	if (IsValid(attacker) and attacker:IsPlayer()) then
		if (client == attacker) then
			attacker:AddFrags(-1)
		else
			attacker:AddFrags(1)
		end
	end

	client:SetAction("@respawning", ix.config.Get("spawnTime", 5))
	client:SetDSP(31)
end

function GM:PlayerDeath(client, inflictor, attacker)
	if (client:GetChar()) then
		if (IsValid(client.ixRagdoll)) then
			client.ixRagdoll.ixIgnoreDelete = true
			client.ixRagdoll:Remove()
			client:SetLocalVar("blur", nil)
		end

		client:SetNetVar("deathStartTime", CurTime())
		client:SetNetVar("deathTime", CurTime() + ix.config.Get("spawnTime", 5))

		local deathSound = hook.Run("GetPlayerDeathSound", client) or deathSounds[math.random(1, #deathSounds)]

		if (client:IsFemale() and !deathSound:find("female")) then
			deathSound = deathSound:gsub("male", "female")
		end

		client:EmitSound(deathSound)

		ix.log.Add(client, "playerDeath", attacker:GetName() ~= "" and attacker:GetName() or attacker:GetClass())
	end
end

local painSounds = {
	Sound("vo/npc/male01/pain01.wav"),
	Sound("vo/npc/male01/pain02.wav"),
	Sound("vo/npc/male01/pain03.wav"),
	Sound("vo/npc/male01/pain04.wav"),
	Sound("vo/npc/male01/pain05.wav"),
	Sound("vo/npc/male01/pain06.wav")
}

local drownSounds = {
	Sound("player/pl_drown1.wav"),
	Sound("player/pl_drown2.wav"),
	Sound("player/pl_drown3.wav"),
}

function GM:GetPlayerPainSound(client)
	if (client:WaterLevel() >= 3) then
		return drownSounds[math.random(1, #drownSounds)]
	end
end

function GM:PlayerHurt(client, attacker, health, damage)
	if ((client.ixNextPain or 0) < CurTime()) then
		local painSound = hook.Run("GetPlayerPainSound", client) or painSounds[math.random(1, #painSounds)]

		if (client:IsFemale() and !painSound:find("female")) then
			painSound = painSound:gsub("male", "female")
		end

		client:EmitSound(painSound)
		client.ixNextPain = CurTime() + 0.33
	end

	ix.log.Add(client, "playerHurt", damage, attacker:GetName() ~= "" and attacker:GetName() or attacker:GetClass())
end

function GM:PlayerDeathThink(client)
	if (client:GetChar()) then
		local deathTime = client:GetNetVar("deathTime")

		if (deathTime and deathTime <= CurTime()) then
			client:Spawn()
		end
	end

	return false
end

function GM:PlayerDisconnected(client)
	client:SaveData()

	local character = client:GetChar()

	if (character) then
		local charEnts = character:GetVar("charEnts") or {}

		for _, v in ipairs(charEnts) do
			if (v and IsValid(v)) then
				v:Remove()
			end
		end

		hook.Run("OnCharDisconnect", client, character)
			character:Save()
		ix.chat.Send(nil, "disconnect", client:SteamName())
	end
end

function GM:InitPostEntity()
	local doors = ents.FindByClass("prop_door_rotating")

	for _, v in ipairs(doors) do
		local parent = v:GetOwner()

		if (IsValid(parent)) then
			v.ixPartner = parent
			parent.ixPartner = v
		else
			for _, v2 in ipairs(doors) do
				if (v2:GetOwner() == v) then
					v2.ixPartner = v
					v.ixPartner = v2

					break
				end
			end
		end
	end

	timer.Simple(0.1, function()
		hook.Run("LoadData")
	end)

	timer.Simple(2, function()
		ix.entityDataLoaded = true
	end)
end

function GM:ShutDown()
	ix.shuttingDown = true
	ix.config.Save()

	hook.Run("SaveData")

	for _, v in ipairs(player.GetAll()) do
		v:SaveData()

		if (v:GetCharacter()) then
			v:GetCharacter():Save()
		end
	end
end

-- luacheck: globals LIMB_GROUPS
LIMB_GROUPS = {}
LIMB_GROUPS[HITGROUP_LEFTARM] = true
LIMB_GROUPS[HITGROUP_RIGHTARM] = true
LIMB_GROUPS[HITGROUP_LEFTLEG] = true
LIMB_GROUPS[HITGROUP_RIGHTLEG] = true
LIMB_GROUPS[HITGROUP_GEAR] = true

function GM:ScalePlayerDamage(client, hitGroup, dmgInfo)
	dmgInfo:ScaleDamage(1.5)

	if (hitGroup == HITGROUP_HEAD) then
		dmgInfo:ScaleDamage(7)
	elseif (LIMB_GROUPS[hitGroup]) then
		dmgInfo:ScaleDamage(0.5)
	end
end

function GM:GetGameDescription()
	return "IX: "..(Schema and Schema.name or "Unknown")
end

function GM:OnPlayerUseBusiness(client, item)
	-- You can manipulate purchased items with this hook.
	-- does not requires any kind of return.
	-- ex) item:SetData("businessItem", true)
	-- then every purchased item will be marked as Business Item.
end

function GM:PlayerDeathSound()
	return true
end

function GM:InitializedSchema()
	if (!ix.data.Get("date", nil, false, true)) then
		ix.data.Set("date", os.time(), false, true)
	end

	ix.date.start = ix.data.Get("date", os.time(), false, true)

	game.ConsoleCommand("sbox_persist ix_"..Schema.folder.."\n")
end

function GM:PlayerCanHearPlayersVoice(listener, speaker)
	local allowVoice = ix.config.Get("allowVoice")
	if allowVoice then
		local listener_pos = listener:GetPos()
		local speaker_pos = speaker:GetPos()
		local voice_dis = math.Distance(speaker_pos.x, speaker_pos.y, listener_pos.x, listener_pos.y)
		if voice_dis > ix.config.Get("voiceDistance") then
			allowVoice = false
		end
	end
	return allowVoice
end

function GM:OnPhysgunFreeze(weapon, physObj, entity, client)
	-- Object is already frozen (!?)
	if (!physObj:IsMoveable()) then return false end
	if (entity:GetUnFreezable()) then return false end

	physObj:EnableMotion(false)

	-- With the jeep we need to pause all of its physics objects
	-- to stop it spazzing out and killing the server.
	if (entity:GetClass() == "prop_vehicle_jeep") then
		local objects = entity:GetPhysicsObjectCount()

		for i = 0, objects - 1 do
			entity:GetPhysicsObjectNum(i):EnableMotion(false)
		end
	end

	-- Add it to the player's frozen props
	client:AddFrozenPhysicsObject(entity, physObj)
	client:SendHint("PhysgunUnfreeze", 0.3)
	client:SuppressHint("PhysgunFreeze")

	return true
end

function GM:CanPlayerSuicide(client)
	return false
end

function GM:AllowPlayerPickup(client, entity)
	return false
end

function GM:PreCleanupMap()
	hook.Run("SaveData")
	hook.Run("PersistenceSave")
end

function GM:PostCleanupMap()
	hook.Run("LoadData")
	hook.Run("PostLoadData")
end

function GM:CharacterPreSave(character)
	local client = character:GetPlayer()

	for _, v in pairs(character:GetInventory():GetItems()) do
		if (v.OnSave) then
			v:Call("OnSave", client)
		end
	end
end

timer.Create("ixLifeGuard", 1, 0, function()
	for _, v in ipairs(player.GetAll()) do
		if (v:GetChar() and v:Alive() and hook.Run("ShouldPlayerDrowned", v) != false) then
			if (v:WaterLevel() >= 3) then
				if (!v.drowningTime) then
					v.drowningTime = CurTime() + 30
					v.nextDrowning = CurTime()
					v.drownDamage = v.drownDamage or 0
				end

				if (v.drowningTime < CurTime()) then
					if (v.nextDrowning < CurTime()) then
						v:ScreenFade(1, Color(0, 0, 255, 100), 1, 0)
						v:TakeDamage(10)
						v.drownDamage = v.drownDamage + 10
						v.nextDrowning = CurTime() + 1
					end
				end
			else
				if (v.drowningTime) then
					v.drowningTime = nil
					v.nextDrowning = nil
					v.nextRecover = CurTime() + 2
				end

				if (v.nextRecover and v.nextRecover < CurTime() and v.drownDamage > 0) then
					v.drownDamage = v.drownDamage - 10
					v:SetHealth(math.Clamp(v:Health() + 10, 0, v:GetMaxHealth()))
					v.nextRecover = CurTime() + 1
				end
			end
		end
	end
end)

netstream.Hook("strReq", function(client, time, text)
	if (client.ixStrReqs and client.ixStrReqs[time]) then
		client.ixStrReqs[time](text)
		client.ixStrReqs[time] = nil
	end
end)

function GM:GetPreferredCarryAngles(entity)
	if (entity:GetClass() == "ix_item") then
		local itemTable = entity:GetItemTable()

		if (itemTable) then
			local preferedAngle = itemTable.preferedAngle

			if (preferedAngle) then -- I don't want to return something
				return preferedAngle
			end
		end
	end
end

function GM:PluginShouldLoad(uniqueID)
	return !ix.plugin.unloaded[uniqueID]
end

function GM:DatabaseConnected()
	-- Create the SQL tables if they do not exist.
	ix.db.LoadTables()
	ix.log.LoadTables()

	MsgC(Color(0, 255, 0), "Database Type: " .. ix.db.module .. ".\n")

	timer.Create("ixDatabaseThink", 0.5, 0, function()
		mysql:Think()
	end)
end


netstream.Hook("ixEntityMenuSelect", function(client, entity, option)
	if (!IsValid(entity) or !isstring(option) or
		hook.Run("CanPlayerInteractEntity", client, entity, option) == false or
		entity:GetPos():Distance(client:GetPos()) > 96) then
		return
	end

	hook.Run("OnPlayerInteractEntity", client, entity, option)

	if (entity["OnSelect" .. option]) then
		entity["OnSelect" .. option](entity, client, option)
	else
		entity:OnOptionSelected(client, option)
	end
end)
