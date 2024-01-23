Sealer = class()
Sealer.maxParentCount = 1
Sealer.maxChildCount = 0
Sealer.connectionInput = sm.interactable.connectionType.logic
Sealer.connectionOutput = sm.interactable.connectionType.none

local neighbours = {
    sm.vec3.new(1, 0, 0),
    sm.vec3.new(-1, 0, 0),
    sm.vec3.new(0, 1, 0),
    sm.vec3.new(0, -1, 0),
    sm.vec3.new(0, 0, 1),
    sm.vec3.new(0, 0, -1),
}

local minNeighbours = {
    sm.vec3.new(1, 0, 0),
    sm.vec3.new(0, 1, 0),
    sm.vec3.new(0, 0, 1)
}

local function round(value)
    local decimal = value % 1

    if decimal < .5 then
        return value - decimal
    else
        return value + (1 - decimal)
    end
end

local function roundVec(vec3)
    return sm.vec3.new(
        round(vec3.x),
        round(vec3.y),
        round(vec3.z)
    )
end

local function floor(vec3)
    return sm.vec3.new(
        math.floor(vec3.x),
        math.floor(vec3.y),
        math.floor(vec3.z)
    )
end

local function find(a, b)
    for i, v in pairs(a) do
        if v == b then
            return true
        end
    end

    return false
end

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    end

    return value
end

local function findInteractable(interactables, id)
    for _, v in ipairs(interactables) do
        if v.id == id then
            return v
        end
    end
end

local function localDirection(body, vector)
    local inverted = sm.quat.inverse(body.worldRotation)
    local bodyFront, bodySide, bodyUp = sm.quat.getAt(inverted), sm.quat.getRight(inverted), sm.quat.getUp(inverted)

    return (bodyFront * vector.z) + (bodySide * vector.x) + (bodyUp * vector.y)
end

function Sealer:server_onCreate()
    self.sv = {}
    self.sv.lastTick = 0
    self.sv.volumes = {}
    self.sv.characterStates = {}

    self:server_calucateVolumes()
end

function Sealer:server_onRefresh()
    self.sv.lastTick = 0

    self:server_calucateVolumes()
end

function Sealer:server_onFixedUpdate()
    -- Originally for only getting the areatrigger overlapping body but wouldn't detect areaTrigger it was inside --
    --local bodyMin, bodyMax = self.shape.body:getWorldAabb()
    --local bodySize = bodyMax-bodyMin

    local volume = self.sv.volumes[1]
    if volume and volume.min and volume.max then
        local a, b = sm.physics.raycast(self.shape.body.worldPosition + sm.vec3.new(0, 0, 1000),
            self.shape.body.worldPosition, nil, sm.physics.filter.areaTrigger)
        if a and b:getAreaTrigger():getUserData().water then
            local waterHeight = b:getAreaTrigger():getWorldMax().z
            local heightDifference = waterHeight - self.shape.body.worldPosition.z
            local height = volume.max.z - volume.min.z

            volume.water = clamp(volume.volume * (heightDifference / height) * 4, 0, volume.volume)
        end
    end

    --[[
        Switchs and logic updates can trigger the creation to change which in this usage is undesired.
    if self.shape.body:hasChanged(self.sv.lastTick) then
        self.sv.lastTick = sm.game.getCurrentTick()

        self:server_calucateVolumes()
    end
    ]]

    if #self.sv.volumes > 0 then
        -- Update water level of volumes and replicate to client --
        local minimalNetworkVolume = {}

        for i, v in ipairs(self.sv.volumes) do
            -- index 1 is exterior --
            if i > 1 then
                -- TODO fix the water volume calucation losing water pressure through volumes --

                for _, neighbourId in ipairs(v.neighbours) do
                    local neighbour = self.sv.volumes[neighbourId]

                    local interactable = findInteractable(self.shape.body:getInteractables(), v.interactable)
                    if not interactable or interactable:isActive() then
                    local height = v.min.z + (v.max.z - v.min.z) * (v.water / v.volume)
                    local neighbourHeight = neighbour.min.z +
                        (neighbour.max.z - neighbour.min.z) * (neighbour.water / neighbour.volume)

                    local diff = height - neighbourHeight

                    neighbour.water = neighbour.water + diff
                    v.water = v.water - diff

                    --neighbour.water = clamp(neighbour.water + diff, 0, neighbour.volume)
                    --v.water = clamp(v.water - diff, 0, v.volume)
                    end
                end

                -- Increase water level of all volumes --
                --v.water = math.min(v.volume, v.water + 0)

                -- Make volumes containing water heavier (water weight is just a randomish number) --
                sm.physics.applyImpulse(self.shape.body, sm.vec3.new(0, 0, v.water * -1), true)
            end

            -- Create array for replication --
            minimalNetworkVolume[i] = {
                water = v.water
            }
        end
        -- Replicate water levels to client --
        self.network:sendToClients("client_updateVolume", minimalNetworkVolume)

        -- Handle player characters when they are inside volumes --
        local newCharacterStates = {}
        for _, player in ipairs(sm.player.getAllPlayers()) do
            local character = player:getCharacter()
            if character and sm.exists(character) then
                local localPoint = character.worldPosition - self.shape.body.worldPosition
                local inverted = sm.quat.inverse(self.shape.body.worldRotation)
                local front, side, up = sm.quat.getAt(inverted), sm.quat.getRight(inverted), sm.quat.getUp(inverted)
                local point = (front * localPoint.z) + (side * localPoint.x) + (up * localPoint.y)

                -- Convert localPoint to grid position --
                point = sm.vec3.new(
                    math.floor(point.x * 4),
                    math.floor(point.y * 4),
                    math.floor(point.z * 4)
                )

                -- Check if grid cell exists for player grid position to check if they are in a volume -
                local volume = nil
                for i, v in ipairs(self.sv.volumes) do
                    -- Skipping one as always as its the exterior of the body --
                    if i > 1 and v.grid[point.x] and v.grid[point.x][point.y] and v.grid[point.x][point.y][point.z] then
                        volume = v
                        break
                    end
                end

                if volume then
                    -- Check if character is at suitable height to be swimming --
                    local height = volume.min.z + (volume.max.z - volume.min.z) * (volume.water / volume.volume)

                    local characterInWater = localPoint.z < height/4

                    -- Make the character swim/dive --
                    character:setSwimming(characterInWater)
                    character:setDiving(characterInWater)

                    -- Update the character state --
                    newCharacterStates[player.id] = characterInWater
                elseif self.sv.characterStates[player.id] then -- Check if the character was in water last update so they aren't stuck swimming
                    character:setSwimming(false)
                    character:setDiving(false)
                end
            end
        end

        self.sv.characterStates = newCharacterStates
    end
end

-- Calucate volumes for body for water seal --
function Sealer:server_calucateVolumes()
    local grid = {}
    local body = self.shape.body

    -- Define grid bounds with a block border for the exterior --
    local min, max = body:getLocalAabb()
    min = min - sm.vec3.one()
    max = max + sm.vec3.one()

    -- Define grid and grid cell ids --
    local iterationCount = 0
    for x = min.x, max.x do
        grid[x] = {}
        for y = min.y, max.y do
            grid[x][y] = {}
            for z = min.z, max.z do
                iterationCount = iterationCount + 1
                grid[x][y][z] = iterationCount
            end
        end
    end

    -- Clear value of cells that contain blocks/parts --
    local function calucateBlockOverlap(shape, pos2, size2, value)
        local pos, rot, size = shape.worldPosition, shape:getLocalRotation(), shape:getBoundingBox()
        local front, side, up = sm.quat.getAt(rot), sm.quat.getRight(rot), sm.quat.getUp(rot)

        -- Workaround due to localPosition being offset by localRotation --
        pos = (pos - self.shape.body.worldPosition) * 4

        -- Handle body rotation to keep the position local to body --
        pos = localDirection(self.shape.body, pos)

        -- Handle values from door interactable --
        if pos2 then
            pos = pos + (front * pos2.z) + (side * pos2.x) + (up * pos2.y)
        end
        if size2 then
            size = size2 / 4
        end

        -- Fix shape size cutting off an extra block on all axis --
        size = sm.vec3.new(
            size.x <= .25 and 0 or size.x - .25,
            size.y <= .25 and 0 or size.y - .25,
            size.z <= .25 and 0 or size.z - .25
        )

        -- Make sure to include part rotation for size --
        local modifiedSize = sm.vec3.zero()
        modifiedSize = modifiedSize + front * size.z
        modifiedSize = modifiedSize + side * size.x
        modifiedSize = modifiedSize + up * size.y

        -- Create part bounds --
        local c1, c2 = pos - modifiedSize * 2, pos + modifiedSize * 2

        -- Make sure to min/max bounds --
        local min, max = sm.vec3.min(c1, c2), sm.vec3.max(c1, c2)

        -- Floor startIndex & count due to vector inprecision --
        for x = math.floor(min.x), math.floor(max.x) do
            for y = math.floor(min.y), math.floor(max.y) do
                for z = math.floor(min.z), math.floor(max.z) do
                    if grid[x] and grid[x][y] then
                        grid[x][y][z] = value or nil
                    end
                end
            end
        end
    end
    -- Calucate what cells shapes are occupying --
    for _, shape in ipairs(body:getShapes()) do
        calucateBlockOverlap(shape)
    end

    -- Calucate what cells interactables are occupying --
    for i, interactable in ipairs(body:getInteractables()) do
        if interactable.type == "scripted" then
            local shape = interactable:getShape()
            local publicData = interactable.publicData
            local pos, size = publicData and publicData.pos, publicData and publicData.size
            if shape and pos and size then
                calucateBlockOverlap(shape, pos, size, iterationCount + interactable.id)
            end
        end
    end
    -- Sort grid cells into their cell ids --
    local sortedIds = {}
    for x = min.x, max.x do
        for y = min.y, max.y do
            for z = min.z, max.z do
                if grid[x][y][z] then
                    sortedIds[grid[x][y][z]] = {
                        {
                            x = x,
                            y = y,
                            z = z,
                        }
                    }
                end
            end
        end
    end

    -- Sort out what cells are connected --
    for x = min.x, max.x do
        for y = min.y, max.y do
            for z = min.z, max.z do
                local mainCell = grid[x][y][z]
                if mainCell ~= nil and mainCell <= iterationCount then
                    -- Check we if have neighbours and assign their cell id to ours so we know we are connected --
                    for _, vec in ipairs(minNeighbours) do
                        local cell = grid[x + vec.x] and grid[x + vec.x][y + vec.y] and
                            grid[x + vec.x][y + vec.y][z + vec.z]
                        if cell and cell ~= mainCell and cell <= iterationCount then
                            -- Iterate over all cells with same id and assign new id --
                            for _, v in ipairs(sortedIds[cell]) do
                                grid[v.x][v.y][v.z] = mainCell
                                sortedIds[mainCell][#sortedIds[mainCell] + 1] = {
                                    x = v.x,
                                    y = v.y,
                                    z = v.z,
                                }
                            end
                            sortedIds[cell] = nil
                        end
                    end
                end
            end
        end
    end

    self.sv.volumes = {}

    local array = {}

    -- Sort volume grids into groups --
    for x = min.x, max.x do
        for y = min.y, max.y do
            for z = min.z, max.z do
                if grid[x][y][z] ~= nil then
                    local value = grid[x][y][z]

                    if not array[value] then
                        array[value] = {
                            grid = {},
                            neighbours = {},
                            volume = 0,
                            water = 0
                        }

                        if value - iterationCount > 0 then
                            array[value].interactable = value - iterationCount
                        end
                    end
                    array[value].volume = array[value].volume + .25

                    if not array[value].grid[x] then
                        array[value].grid[x] = {}
                    end

                    if not array[value].grid[x][y] then
                        array[value].grid[x][y] = {}
                    end

                    if not array[value].grid[x][y][z] then
                        array[value].grid[x][y][z] = true

                        -- Calucate neighbours --
                        for _, vec in ipairs(neighbours) do
                            local cell = grid[x + vec.x] and grid[x + vec.x][y + vec.y] and
                                grid[x + vec.x][y + vec.y][z + vec.z]
                            if cell and cell ~= value and not find(array[value].neighbours, cell) then
                                table.insert(array[value].neighbours, cell)
                            end
                        end
                    end
                end
            end
        end
    end

    for index, v in pairs(array) do
        v.id = index
        table.insert(self.sv.volumes, v)
    end

    -- Get largest volume --
    local index = -1
    local min, max = sm.vec3.new(1000000, 1000000, 1000000), sm.vec3.new(-1000000, -1000000, -1000000)
    for i, v in ipairs(self.sv.volumes) do
        local localMin, localMax = sm.vec3.new(1000000, 1000000, 1000000), sm.vec3.new(-1000000, -1000000, -1000000)
        for x, yArr in pairs(v.grid) do
            for y, zArr in pairs(yArr) do
                for z, _ in pairs(zArr) do
                    localMin = sm.vec3.new(
                        math.min(localMin.x, x),
                        math.min(localMin.y, y),
                        math.min(localMin.z, z)
                    )

                    localMax = sm.vec3.new(
                        math.max(localMax.x, x),
                        math.max(localMax.y, y),
                        math.max(localMax.z, z)
                    )
                end
            end
        end

        v.min = localMin
        v.max = localMax

        if localMin.x < min.x and localMin.y < min.y and localMin.z < min.z and localMax.x > max.x and localMax.y > max.y and localMax.z > max.z then
            min = localMin
            max = localMax
            index = i
        end
    end

    -- Move large volume to first index --
    if index ~= -1 then
        local reference = self.sv.volumes[index]
        table.remove(self.sv.volumes, index)
        table.insert(self.sv.volumes, 1, reference)
    end

    -- Create dict used for changing cell ids into volume ids --
    local ids = {}
    for i, v in ipairs(self.sv.volumes) do
        ids[v.id] = i
    end

    -- Convert cell ids into volume array ids --
    for _, volume in ipairs(self.sv.volumes) do
        for index, id in ipairs(volume.neighbours) do
            if ids[id] then
                volume.neighbours[index] = ids[id]
            end
        end
    end

    local networkFriendlyVolumes = {}

    for i, volume in ipairs(self.sv.volumes) do
        networkFriendlyVolumes[i] = {
            position = sm.vec3.lerp(volume.min, volume.max, 0.5),
            size = volume.max-volume.min,
            volume = volume.volume,
            water = 0
        }
    end

    self.network:sendToClients("client_visualize", networkFriendlyVolumes)
end

function Sealer:client_onCreate()
    self.cl = {}
    self.cl.effects = {}
end

function Sealer:client_onDestroy()
    for _, v in ipairs(self.cl.effects) do
        v:stop()
    end
    self.cl.effects = nil
end

function Sealer:client_onInteract(_, state)
    if state == true then
        self.network:sendToServer("server_calucateVolumes")
    end
end

function Sealer:client_updateVolume(water)
    if not self.cl.volumes then return end

    -- Update volumes water variable from received water values --
    for i, volume in ipairs(water) do
        self.cl.volumes[i].water = volume.water
    end

    -- Render water level with effect --
    for i, volume in ipairs(self.cl.volumes or {}) do
        if volume.effect and i ~= 1 then
            local effect = volume.effect

            local size = volume.size / 4 + sm.vec3.one() / 4
            local pos = volume.position / 4

            local percentage = clamp(volume.water / volume.volume, 0, 1)

            pos = pos + sm.vec3.new(0, 0, -size.z / 2 + size.z * percentage)

            pos = self.shape.body:transformPoint(pos + sm.vec3.new(.125, .125, .125))

            effect:setPosition(pos)
            effect:setRotation(self.shape.body.worldRotation)
            -- Dividing by 2048 because of effect size --
            effect:setScale(size / 2048)

        end
    end
end

function Sealer:client_visualize(volumes)
    for _, v in ipairs(self.cl.effects) do
        v:stop()
    end
    self.cl.effects = {}

    self.cl.volumes = volumes
    for i, volume in pairs(volumes) do
        local effect = sm.effect.createEffect("Boop - Floor")

        --effect:setRotation(self.shape.body.worldRotation)

        effect:setScale(sm.vec3.one()/2048)
        effect:start()

        volume.effect = effect
        table.insert(self.cl.effects, effect)
    end

    -- Debugging tools to visualize volumes --
    --[[
    local colors = {
        sm.color.new(255, 0, 0),
        sm.color.new(0, 255, 0),
        sm.color.new(0, 0, 255),
        sm.color.new(255, 255, 0),
        sm.color.new(0, 255, 255),
        sm.color.new(255, 0, 255),
        sm.color.new(0, 0, 0),
        sm.color.new(255, 255, 255)
    }

    for i, volume in pairs(volumes) do
        for x, gridY in pairs(volume.grid) do
            for y, gridZ in pairs(gridY) do
                for z, value in pairs(gridZ) do
                    local effect = sm.effect.createEffect("ShapeRenderable")
                    effect:setParameter("uuid", sm.uuid.new("5f41af56-df4c-4837-9b3c-10781335757f"))
                    effect:setParameter("color", colors[i])

                    effect:setPosition(self.shape.body.worldPosition + sm.vec3.new(x / 4 + .125, y / 4 + .125, z / 4 + .125))
                    --effect:setRotation(self.shape.body.worldRotation)
                    effect:setScale(sm.vec3.new(.1, .1, .1))

                    effect:start()
                    table.insert(self.cl.effects, effect)
                end
            end
        end
    end
    ]]
end