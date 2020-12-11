class "ArtyClient"

require("RayCastStates")

function ArtyClient:__init()
    --self.m_EngineUpdateEvent = Events:Subscribe("Engine:Update", self, self.OnEngineUpdate)

    self.m_UpdateManagerUpdateEvent = Events:Subscribe("UpdateManager:Update", self, self.OnUpdateManagerUpdate)
    self.m_UIDrawHudEvent = Events:Subscribe("UI:DrawHud", self, self.OnUIDrawHud)
    self.m_PlayerUpdateInputEvent = Events:Subscribe("Player:UpdateInput", self, self.OnPlayerUpdateInput)
    self.m_ArtyToggleEnableEvent = NetEvents:Subscribe("Arty:ToggleEnable", self, self.OnArtyToggleEnable)

    self.m_SphereSize = 0.5
    self.m_ColorGrey = Vec4(0.25, 0.25, 0.25, 0.75)
    self.m_ColorRed = Vec4(0.75, 0, 0, 0.75)
    self.m_ColorGreen = Vec4(0, 0.75, 0, 0.75)

    self.m_ShouldRaycast = true
    self.m_RaycastDistance = 400.0

    self.m_RaycastTick = 0.0
    self.m_RaycastMaxTick = 0.25

    -- 0 = nothing hit
    -- 1 = hit movable
    -- 2 = locked in
    -- 3 = hidden
    self.m_RaycastState = RayCastStates.State_Hidden
    self.m_RaycastPosition = Vec3(0, 0, 0)

    self.m_RaycastLockTick = 0.0
    self.m_RaycastLockMaxTick = 10.0 -- This must match the server

    self.m_ArtyEnabled = true
end

function ArtyClient:OnArtyToggleEnable(p_ArtyEnabled)
    print("Toggling Arty Ready State to: " .. p_ArtyEnabled)

    self.m_ArtyEnabled = p_ArtyEnabled
end

function ArtyClient:OnUIDrawHud()
    if self.m_RaycastState == RayCastStates.State_NoHit then
        -- Draw our target spot with target miss
        DebugRenderer:DrawSphere(self.m_RaycastPosition, self.m_SphereSize, self.m_ColorGrey, false, false)
    elseif self.m_RaycastState == RayCastStates.State_Movable then
        -- Draw our green outline that we got a proper hit
        if self.m_ArtyEnabled then
            DebugRenderer:DrawSphere(self.m_RaycastPosition, self.m_SphereSize, self.m_ColorGreen, false, false)
        else
            DebugRenderer:DrawSphere(self.m_RaycastPosition, self.m_SphereSize, self.m_ColorRed, false, false)
        end
    elseif self.m_RaycastState == RayCastStates.State_Locked then
        -- Draw our red outline that we got a locked hit
        DebugRenderer:DrawSphere(self.m_RaycastPosition, self.m_SphereSize, self.m_ColorRed, false, false)
    elseif self.m_RaycastState == RayCastStates.State_Hidden then
        return
    end
        
end

function ArtyClient:OnPlayerUpdateInput(p_Cache, p_DeltaTime)
    -- Don't allow players to drop arty if it's already dropping
    if self.m_ArtyEnabled == false then
        return
    end

    if InputManager:WentKeyDown(InputDeviceKeys.IDK_F) then
        if self.m_RaycastState == RayCastStates.State_Movable then
            self.m_RaycastLockTick = 0.0
            self.m_RaycastState = RayCastStates.State_Locked

            NetEvents:Send("Arty:RequestStrike", self.m_RaycastPosition)
            --print("BITCH SWAY")
        end
    end
end

function ArtyClient:OnUpdateManagerUpdate(p_DeltaTime, p_UpdatePass)
    if p_UpdatePass == UpdatePass.UpdatePass_PreSim then
        -- Handle Physics Raycasts
        self.m_RaycastTick = self.m_RaycastTick + p_DeltaTime
        if self.m_RaycastTick >= self.m_RaycastMaxTick then
            -- Reset the raycast tick
            self.m_RaycastTick = 0.0

            -- Get the local player
            local s_LocalPlayer = PlayerManager:GetLocalPlayer()

            -- Check if the player exists
            if s_LocalPlayer ~= nil then
                -- Only if the player is alive do the raycast
                if s_LocalPlayer.alive then
                    self:OnUpdateRaycast()
                end
            end
        end

        -- Update the lock tick
        if self.m_RaycastState == RayCastStates.State_Locked then
            self.m_RaycastLockTick = self.m_RaycastLockTick + p_DeltaTime
            if self.m_RaycastLockTick >= self.m_RaycastLockMaxTick then
                self.m_RaycastLockTick = 0.0
                self.m_RaycastState = RayCastStates.State_Hidden
            end
        end
    end
end

function ArtyClient:OnUpdateRaycast()
    -- If we have raycasting disabled then don't do it
    if not self.m_ShouldRaycast then
        self.m_RaycastState = RayCastStates.State_Hidden
        return
    end

    -- Skip changing any state when the hit is locked
    if self.m_RaycastState == RayCastStates.State_Locked then
        return
    end

    -- Get the client camera transform
    local s_CameraTransform = ClientUtils:GetCameraTransform()

    -- Get the forward vector and invert it (as it's backwards)
    local s_CameraDirection = Vec3(s_CameraTransform.forward.x * -1, s_CameraTransform.forward.y * -1, s_CameraTransform.forward.z * -1)
    
    -- Ensure that we have a vector
    if self.m_CameraDirection == Vec3(0, 0, 0) then
        -- Hide our raycast
        self.m_RaycastState = RayCastStates.State_Hidden
        return
    end

    local s_RaycastStart = Vec3(s_CameraTransform.trans.x, s_CameraTransform.trans.y, s_CameraTransform.trans.z)
    local s_RaycastEnd = Vec3(s_RaycastStart.x + (s_CameraDirection.x * self.m_RaycastDistance), s_RaycastStart.y + (s_CameraDirection.y * self.m_RaycastDistance), s_RaycastStart.z + (s_CameraDirection.z * self.m_RaycastDistance))

    --print("Start: (" .. s_RaycastStart.x .. "," .. s_RaycastStart.y .. "," .. s_RaycastStart.z .. ")")
    --print("End: (" .. s_RaycastEnd.x .. "," .. s_RaycastEnd.y .. "," .. s_RaycastEnd.z .. ")")
    local s_RaycastHit = RaycastManager:Raycast(s_RaycastStart, s_RaycastEnd, RayCastFlags.DontCheckWater | RayCastFlags.DontCheckCharacter | RayCastFlags.DontCheckRagdoll)
    if s_RaycastHit == nil then
        -- Set our status to nothing hit
        self.m_RaycastPosition = s_RaycastEnd
        self.m_RaycastState = RayCastStates.State_NoHit
        return
    end

    --print("Hit: (" .. s_RaycastHit.position.x .. "," .. s_RaycastHit.position.y .. "," .. s_RaycastHit.position.z .. ")")
    self.m_RaycastPosition = s_RaycastHit.position
    self.m_RaycastState = RayCastStates.State_Movable
end

g_ArtyClient = ArtyClient()