class "ArtyServer"

function ArtyServer:__init()
    self.m_ArtyStrikeRequestEvent = NetEvents:Subscribe("Arty:RequestStrike", self, self.OnArtyStrikeRequest)
    self.m_EngineUpdateEvent = Events:Subscribe("Engine:Update", self, self.OnEngineUpdate)

    -- Cooldown time in seconds
    self.m_CooldownTime = 10
    self.m_CooldownTick = 0

    -- Configurable options
    self.m_ArtyRadius = 13.0

    self.m_MortarPartitionGuid = Guid('5350B268-18C9-11E0-B820-CD6C272E4FCC')
    self.m_CustomBlueprintGuid = Guid('D407033B-49AE-DF14-FE19-FC776AE04E2C')

    -- Player id of player that dropped arty
    self.m_ArtyPlayerId = -1

    -- Counter for arty strikes
    self.m_ArtyDropTick = 0.0

    -- Maximu time in between arty strikes
    self.m_ArtyDropMaxTick = 0.90

    -- Current spawn position in the air to spawn arty
    self.m_ArtyPosition = Vec3(0, 0, 0)

    -- Current count of arty to drop
    self.m_ArtyCount = 0
end

function ArtyServer:OnEngineUpdate(p_DeltaTime, p_SimulationDeltaTime)
    -- Update our arty time
    self.m_CooldownTick = self.m_CooldownTick + p_DeltaTime

    -- We only want to tick if we have arty to drop
    if self.m_ArtyCount > 0 then
        -- Increment the current tick count
        self.m_ArtyDropTick = self.m_ArtyDropTick + p_DeltaTime

        -- Check if we are at the time to drop another arty
        if self.m_ArtyDropTick > self.m_ArtyDropMaxTick then
            -- Reset the arty drop tick to wait for another MaxTick in time
            self.m_ArtyDropTick = 0.0

            -- Get a random point from the arty position (this must be set before hand)
            local s_ArtyStartPoint = self:GetRandomPointFromCenter(self.m_ArtyPosition, self.m_ArtyRadius)

            -- Get the player that called in the strike
            local s_Player = PlayerManager:GetPlayerById(self.m_ArtyPlayerId)

            -- Spawn an arty at the start point
            self:SpawnArty(s_Player, s_ArtyStartPoint)

            -- Decrease the amount of artys to drop
            self.m_ArtyCount = self.m_ArtyCount - 1
        end

        -- When we are firing our last arty, send message to clients to unlock
        if self.m_ArtyCount == 1 then
            NetEvents:BroadcastUnreliable("Arty:ToggleEnable", true)
        end
    end
end

function ArtyServer:OnArtyStrikeRequest(p_Player, p_Position)
    if p_Player == nil then
        print("OnArtyStrikeRequest invalid player.")
        return
    end

    local s_PlayerName = p_Player.name

    if self.m_CooldownTick < self.m_CooldownTime then
        print("Player (" .. s_PlayerName .. ") arty rejected, reason cooldown.")
        return
    end

    -- Set our arty time to be on cooldown again
    self.m_CooldownTick = 0.0

    -- Update clients that arty is disabled for now
    NetEvents:BroadcastLocal("Arty:ToggleEnable", false)

    print("Player: " .. s_PlayerName .. " requested arty at (" .. p_Position.x .. ", " .. p_Position.y .. ", " .. p_Position.z .. ")")

    -- Calculate the position "in the sky" where the projectiles will spawn from
    self.m_ArtyPosition = Vec3(p_Position.x, p_Position.y + 500.0, p_Position.z)
    self.m_ArtyCount = 10
    self.m_ArtyPlayerId = p_Player.id
end

function ArtyServer:SpawnArty(p_Player, p_Position)
    if p_Player == nil then
        print("spawn arty: invalid player.")
        return
    end

    local s_SpawnTransform = LinearTransform(
        Vec3(1, 0, 0),
        Vec3(0, 0, 1),
        Vec3(0,-1, 0),
        p_Position
    )

    local s_Params = EntityCreationParams()
    s_Params.networked = true
    s_Params.transform = s_SpawnTransform

    local s_ProjectileBlueprint = ResourceManager:FindInstanceByGuid(self.m_MortarPartitionGuid, self.m_CustomBlueprintGuid)

    local s_ProjectileEntityBus = EntityManager:CreateEntitiesFromBlueprint(s_ProjectileBlueprint, s_Params)

    for _, l_Entity in pairs(s_ProjectileEntityBus.entities) do
        l_Entity:Init(Realm.Realm_ClientAndServer, true)
    end
end

function ArtyServer:GetRandomPointFromCenter(p_Position, p_Radius)
    local s_X = p_Position.x
    local s_Z = p_Position.z

    -- Calculate random angle
    local s_Alpha = 2 * math.pi * math.random()

    -- Calculate random radius
    local s_Radius = p_Radius * math.sqrt(math.random())

    -- Calculate coordinates
    local s_NewX = s_Radius * math.cos(s_Alpha) + s_X
    local s_NewZ = s_Radius * math.sin(s_Alpha) + s_Z

    return Vec3(s_NewX, p_Position.y, s_NewZ)
end

g_ArtyServer = ArtyServer()