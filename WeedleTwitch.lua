
	--[[
		WeedleTwitch.lua
		Updated 23/04/2018
	--]]

	if myHero.charName ~= "Twitch" then return end

	require("FF15Menu")
	require("GeometryLib")	

	local version        = 0.2 
	local myId           = myHero.networkId
	local Q, W, E, R     = 0, 1, 2, 3
	local TEAM_JUNGLE    = 300
	local TEAM_ALLY      = myHero.team 
	local TEAM_ENEMY     = TEAM_JUNGLE - TEAM_ALLY
	local _HERO          = GameObjectType.AIHeroClient 
	local _MISSILE       = GameObjectType.MissileClient
	local huge           = math.huge	
	local sqrt           = math.sqrt  
	local floor          = math.floor 
	local insert         = table.insert 
	local format         = string.format 		
	local find           = string.find 
	local lower          = string.lower 
	local spellRange     = {W = 950, E = 1200, R = 850}	
	local poisonTable    = {}
	for i, hero in pairs(ObjectManager:GetEnemyHeroes()) do 
		poisonTable[hero.networkId] = 0 
	end

	local menu = Menu("WeedleTwitch", "Twitch by Weedle")
	menu:key("Combo", "Combo Key", 0x20)
	menu:sub("Q", "Q Settings")
		menu.Q:checkbox("Kill", "Q after Kill", true)
		menu.Q:key("Recall", "Stealth Recall Key", 0x4E)
	menu:sub("W", "W Settings")
		menu.W:checkbox("ON", "Use W in Combo", true)
	menu:sub("E", "E Settings")
		menu.E:checkbox("ON", "Use E", true)
		menu.E:slider("Count", "Min Count to E", 0, 6, 0, 1)
	menu:sub("R", "R Settings")
		menu.R:slider("Count", "Min Count to R", 0, 5, 3, 1)

	--x--

	local function Ready(spell, unit)
		unit = unit or myHero
		return unit.spellbook:CanUseSpell(spell) == 0
	end		

	local function GetDistanceSqr(p1, p2)
		p2 = p2 or myHero
		p1 = p1.position or p1
		p2 = p2.position or p2
		
		local dx = p1.x - p2.x
		local dz = p1.z - p2.z
	
		return dx*dx + dz*dz
	end

	local function GetDistance(p1, p2)
	  	return sqrt(GetDistanceSqr(p1, p2))
	end

	local function Hex(a,r,g,b)
	    return format("0x%.2X%.2X%.2X%.2X",a,r,g,b)
	end	 		

	local function Vec3(vec)
		return D3DXVECTOR3(vec.x, vec.y, vec.z)
	end

	local function CalcPhysicalDamage(source, target, dmg)
	    if target.isInvulnerable then return 0 end	    
		local result = 0

		local baseArmor = target.characterIntermediate.armor
		local Lethality = source.characterIntermediate.physicalLethality * (0.6 + 0.4 * source.experience.level / 18)
		baseArmor = baseArmor - Lethality
	
		if baseArmor < 0 then baseArmor = 0 end
		if (baseArmor >= 0 ) then
			local armorPenetration = source.characterIntermediate.percentArmorPenetration
			local armor = baseArmor - ((armorPenetration * baseArmor) / 100)
			result = dmg * (100 / (100 + armor))
		end
		return result
	end
	
	local function CalcMagicalDamage(source, target, dmg)
	    if target.isInvulnerable then return 0 end	    
	    local result = 0
	
		local baseArmor = target.characterIntermediate.spellBlock
		local Lethality = source.characterIntermediate.flatMagicPenetration
	    baseArmor = baseArmor - Lethality
	
		if baseArmor < 0 then baseArmor = 0 end
		if (baseArmor >= 0 ) then
			local armorPenetration = source.characterIntermediate.percentMagicPenetration
			local armor = baseArmor - ((armorPenetration * baseArmor) / 100)
			result = dmg * (100 / (100 + armor))
		end
		return result
	end

	--x--

	local function GetPathIndex(unit, pathing)
	    local result = 1 
	    for i = 2, #pathing.paths do
	        local myHeroPos = Vector(myHero)
	        local iPath = Vector(pathing.paths[i])
	        local iMinusPath = Vector(pathing.paths[i-1])
	        if GetDistance(iPath,myHeroPos) < GetDistance(iMinusPath,myHeroPos) and 
	            GetDistance(iPath,iMinusPath) <= GetDistance(iMinusPath, myHeroPos) and i ~= #pathing.paths then
	            result = i 
	        end
	    end
	    return result
	end 	

	local function GetPaths(unit)
   		local result = {}
   		local pathing = unit.aiManagerClient.navPath
   		if pathing and pathing.paths and #pathing.paths > 1 then        
   		    for i = GetPathIndex(unit, pathing), #pathing.paths do 
   		        local path = pathing.paths[i]
   		        insert(result, Vector(path))
   		    end  
   		    insert(result, 2, Vector(unit))   
   		else
   		    insert(result, Vector(unit))
   		end
   		return result
   	end	

   	local function GetPred(unit, speed, delay)
   		local hPos = Vector(myHero) 
   		local tms = unit.characterIntermediate.movementSpeed
   		local paths = GetPaths(unit)
   		if #paths <= 2 then return paths[1] end 

   		local t = delay + NetClient.ping/2000 

   		local dt = 0
   		local pPath = paths[2]

   		if speed < huge then 
   			for i = 3, #paths do 
   				local cPath = paths[i]
   				local dir = (cPath - pPath):normalized()
   				local velocity = dir*tms 
   				local a = velocity * velocity - speed * speed 
   				if a == 0 then return nil end 
   				local vecBetween = hPos - pPath 
   				local b = 2 * velocity * vecBetween 
   				local c = vecBetween * vecBetween 
	
   				local radicand = b*b - 4*a*c 
   				if radicand < 0 then return nil end 
   				local sqrtRadicand = sqrt(radicand)
   				
   				local d = 2*a 
   				local t0 = (-b + sqrtRadicand) / d 
   				local t1 = (-b - sqrtRadicand) / d 
	
   				local time
   				if t0 < t1 then 
   					if t1 < 0 then return nil end
   					if t0 >= 0 then 
   						time = t0 
   					else 
   						time = t1 
   					end
   				else 
   					if t0 < 0 then return nil end 
   					if t1 >= 0 then 
   						time = t1 
   					else
   						time = t0 
   					end 
   				end
	
   				t = t + time 
   				local dist = GetDistance(cPath, pPath)
	
   				if t - dt < dist / tms or i == #paths then 
   					return pPath + dir * (t*tms)
   				end
   				pPath = cPath 
   				dt = dt + (dist / tms)
   			end
   		end
   		return pPath + (paths[3] - pPath):normalized() * (t*tms) 
   	end

	--x--

	local forceTarget = nil
	local function OnWndProc(hWnd, msg, wParam, lParam)
		if msg == 513 and wParam == 0 then 
			forceTarget = nil 
			local heroes = ObjectManager:GetEnemyHeroes()
			for i = 1, #heroes do 
				local hero = heroes[i]
				if hero.isValid and hero.team == TEAM_ENEMY and hero.isDead == false and GetDistance(hero, pwHud.hudManager.activeVirtualCursorPos) < 125 then 
					forceTarget = hero
					break
				end 
			end
		end 
	end
 
	local function Edmg(unit)
		local count = poisonTable[unit.networkId]
		if count == 0 or count == nil then return 0 end
		local eLvl = myHero.spellbook:Spell(E).level 		
		local adDmg = CalcPhysicalDamage(myHero, unit, 5 + 15 * eLvl + ((5 * (2 + eLvl) * count) + (0.25 * floor(myHero.characterIntermediate.flatPhysicalDamageMod) * count)))
		local apDmg = CalcMagicalDamage(myHero, unit, 0.2 * floor(myHero.characterIntermediate.flatMagicDamageMod + myHero.characterIntermediate.baseAbilityDamage) * count)
		return adDmg + apDmg 
	end

	local function ELogic()
		if menu.E.ON:get() and Ready(E) then 
			local heroes = ObjectManager:GetEnemyHeroes()
			for i = 1, #heroes do 
				local hero = heroes[i]
				if hero.isValid and hero.team == TEAM_ENEMY and hero.isDead == false and hero.isTargetable and hero.isInvulnerable == false and GetDistance(hero) < spellRange.E and GetDistance(hero) > myHero.characterIntermediate.attackRange then 
					local dmg = Edmg(hero)
					if dmg > hero.health or (poisonTable[hero.networkId] >= menu.E.Count:get() and menu.E.Count:get() > 0) then 
						myHero.spellbook:CastSpell(E, myId)
					end
				end
			end
		end
	end

	local function OnTick()
		if myHero.isDead == false and MenuGUI.isChatOpen == false then
			ELogic()
		end
	end

	local function OnDoCastSpell(source, spellInfo)
		if menu.Combo:get() and source.networkId == myId then
			local target = spellInfo.target
			if target and target.type == _HERO then 
				if menu.E.ON:get() and Ready(E) then 
					local spellName = lower(spellInfo.spellData.name)
					if find(spellName, "attack") then 
						local multiplier = find(spellName, "crit") and 2 or 1 
						local dmg = CalcPhysicalDamage(myHero, target, myHero.characterIntermediate.flatPhysicalDamageMod + myHero.characterIntermediate.baseAttackDamage) * multiplier
						if target.health + target.attackShield < dmg + Edmg(target) and target.health + target.attackShield  > dmg then 
							myHero.spellbook:CastSpell(E, myId)
							return
						end
					end
				end
				if menu.W.ON:get() and Ready(W) then 
					local spellName = lower(spellInfo.spellData.name)
					if find(spellName, "attack") then 
						local multiplier = find(spellName, "crit") and 2 or 1 
						local dmg = CalcPhysicalDamage(myHero, target, myHero.characterIntermediate.flatPhysicalDamageMod + myHero.characterIntermediate.baseAttackDamage) * multiplier
						if target.health + target.attackShield > dmg then 
							local predPos = GetPred(target, 1400, 0.25)
							if predPos and GetDistance(predPos) < spellRange.W then 
								myHero.spellbook:CastSpell(W, Vec3(predPos))
							end
						end
					end
				end
			end
		end
	end

	local function OnCreateObject(obj)
		if obj.type == _MISSILE then 
			local missile = obj.asMissile
			local target = missile.target
			if target and target.type == _HERO and missile.spellCaster.networkId == myId and find(lower(missile.missileData.spellData.name), "attack") then
				local stacks = poisonTable[target.networkId]
				if stacks <= 5 then 
					poisonTable[target.networkId] = stacks + 1 
				end
			end
		end
	end

	local function OnBuffLost(unit, buff)
		if unit.isValid and unit.type == _HERO and unit.team == TEAM_ENEMY then 
			if buff.name == "TwitchDeadlyVenom" then 
				poisonTable[unit.networkId] = 0 
			end
		end
	end

	AddEvent(Events.OnWndProc,OnWndProc)		
	AddEvent(Events.OnTick,OnTick)	
	AddEvent(Events.OnDoCastSpell,OnDoCastSpell)
	AddEvent(Events.OnCreateObject,OnCreateObject)
	AddEvent(Events.OnBuffLost,OnBuffLost)
	PrintChat([[<b><font color="#f9365d">Twitch by Weedle v]]..version..[[</b></font><font color="#FFFFF0"> loaded ^^</font>]])		




