Door = class()
Door.maxParentCount = 1
Door.maxChildCount = 0
Door.connectionInput = sm.interactable.connectionType.logic
Door.connectionOutput = sm.interactable.connectionType.none
Door.colorNormal = sm.color.new( 0xc41616ff )
Door.colorHighlight = sm.color.new( 0xd91111ff )
Door.poseWeightCount = 1

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

local function directionLocalToWorld(shape, dir)
	return shape:transformLocalPoint(dir) - shape.worldPosition
end

function Door:server_onCreate()
	self.Storage = self.storage:load() or {}
	self.Pos = self.Storage[1] or sm.vec3.new(0,0,0)
	self.Size = self.Storage[2] or sm.vec3.new(1,1,1)
	self.lastModification = 0

	local position = self.shape:transformLocalPoint(sm.vec3.new( 0.0, 0.25, 0.0 ))
	local direction = directionLocalToWorld(self.shape, sm.vec3.new( 0.0, 0.0, 1.0 ))
	local upVector = directionLocalToWorld(self.shape, sm.vec3.new( 0.0, -1.0, 0.0 ))

	-- Check if storage is blank --
	if #self.Storage == 0 then
		-- Try to automatically get one axis for volume. --
		local point1, point2, point3

		local success, result = sm.physics.raycast(position, position + direction * 5)
		if success then
			if result.type == "body" then
				local body = result:getBody()
				if sm.exists(body) and body.id == self.shape:getBody().id then
					point1 = result.pointWorld
				end
			end
		end

		local success, result = sm.physics.raycast(position, position + direction * -5)
		if success then
			if result.type == "body" then
				local body = result:getBody()
				if sm.exists(body) and body.id == self.shape:getBody().id then
					point2 = result.pointWorld
				end
			end
		end

		local success, result = sm.physics.raycast(position, position + upVector * -5)
		if success then
			if result.type == "body" then
				local body = result:getBody()
				if sm.exists(body) and body.id == self.shape:getBody().id then
					point3 = result.pointWorld
				end
			end
		end

		if point1 and point2 then
			point1 = self.shape:transformPoint(point1)
			point2 = self.shape:transformPoint(point2)
			point3 = self.shape:transformPoint(point3)

			local center = sm.vec3.lerp(point1, point2, 0.5)

			local rawNum = (point1 - point2).z --(self.shape.worldPosition - result.pointWorld).x
			local yAxis = round(point3.y * 8)/2 - .5
			local zAxis = round(rawNum * 8)/2

			self.Size = sm.vec3.new(self.Size.x, yAxis, zAxis)
			self.Pos = sm.vec3.new(self.Pos.x, yAxis/2 + .5, round(center.z * 8) / 2)
			print(yAxis, zAxis)
		end

		self.storage:save( {self.Pos,self.Size} )
		self.network:sendToClients("client_refresheffect")
	end

	self.interactable.publicData = {
        pos = self.Pos;
        size = self.Size;
    }
end

function Door:server_onFixedUpdate()
	local parent = self.interactable:getSingleParent()
	if parent then
		self.interactable:setActive(parent:isActive())
	end
end

function Door:server_onDestroy()
end

function Door:server_onRefresh()

end

function Door:client_onFixedUpdate()
	if sm.game.getCurrentTick() > self.lastModification + 80 and self.effect and self.effect:isPlaying() then
		self.effect:stop()
	end
end

function Door:client_refresheffect()

	self.cl.Gui:setText( "X", tostring(self.Pos.x) )
	self.cl.Gui:setText( "Y", tostring(self.Pos.y) )
	self.cl.Gui:setText( "Z", tostring(self.Pos.z) )
	self.cl.Gui:setText( "XX", tostring(self.Size.x) )
	self.cl.Gui:setText( "YY", tostring(self.Size.y) )
	self.cl.Gui:setText( "ZZ", tostring(self.Size.z) )
	
	self.effect:setOffsetPosition( self.Pos/4 )
	self.effect:setScale( -self.Size/4 )

	self.lastModification = sm.game.getCurrentTick()
	if not self.effect:isPlaying() then
		self.effect:start()
	end
	
end

function Door:server_input( name, player )

	if name[1] == "X0" then
		self.Pos = self.Pos + sm.vec3.new(-1,0,0)
	elseif name[1] == "X1" then
		self.Pos = self.Pos + sm.vec3.new(1,0,0)
	end
	
	if name[1] == "Y0" then
		self.Pos = self.Pos + sm.vec3.new(0,-1,0)
	elseif name[1] == "Y1" then
		self.Pos = self.Pos + sm.vec3.new(0,1,0)
	end
	
	if name[1] == "Z0" then
		self.Pos = self.Pos + sm.vec3.new(0,0,-1)
	elseif name[1] == "Z1" then
		self.Pos = self.Pos + sm.vec3.new(0,0,1)
	end
	
	if name[1] == "XX0" then
		self.Pos = self.Pos + sm.vec3.new(.5, 0, 0)
		self.Size = self.Size + sm.vec3.new(-1,0,0)
	elseif name[1] == "XX1" then
		self.Pos = self.Pos + sm.vec3.new(-.5, 0, 0)
		self.Size = self.Size + sm.vec3.new(1,0,0)
	end
	
	if name[1] == "YY0" then
		self.Pos = self.Pos + sm.vec3.new(0, .5, 0)
		self.Size = self.Size + sm.vec3.new(0,-1,0)
	elseif name[1] == "YY1" then
		self.Pos = self.Pos + sm.vec3.new(0, -.5, 0)
		self.Size = self.Size + sm.vec3.new(0,1,0)
	end
	
	if name[1] == "ZZ0" then
		self.Pos = self.Pos + sm.vec3.new(0, 0, .5)
		self.Size = self.Size + sm.vec3.new(0,0,-1)
	elseif name[1] == "ZZ1" then
		self.Pos = self.Pos + sm.vec3.new(0, 0, -.5)
		self.Size = self.Size + sm.vec3.new(0,0,1)
	end
	
	if name[1] == "X" then
		self.Pos = sm.vec3.new(tonumber(name[2]) or 0,self.Pos.y,self.Pos.z)
	elseif name[1] == "Y" then
		self.Pos = sm.vec3.new(self.Pos.x,tonumber(name[2]) or 0,self.Pos.z)
	elseif name[1] == "Z" then
		self.Pos = sm.vec3.new(self.Pos.x,self.Pos.y,tonumber(name[2]) or 0)
	elseif name[1] == "XX" then
		self.Size = sm.vec3.new(tonumber(name[2]) or 1,self.Size.y,self.Size.z)
	elseif name[1] == "YY" then
		self.Size = sm.vec3.new(self.Size.x,tonumber(name[2]) or 1,self.Size.z)
	elseif name[1] == "ZZ" then
		self.Size = sm.vec3.new(self.Size.x,self.Size.y,tonumber(name[2]) or 1)
	end

    self.interactable.publicData = {
        pos = self.Pos;
        size = self.Size;
    }
	
	self.storage:save( {self.Pos,self.Size} )
	
	self.network:sendToClients("client_refresheffect")
end

function Door:client_input( name, a )
	self.network:sendToServer("server_input",{name,a})
end

function Door:client_onCreate()
	self.effect = sm.effect.createEffect( "ShapeRenderable", self.interactable )				
	self.effect:setParameter( "uuid", sm.uuid.new("5f41af56-df4c-4837-9b3c-10781335757f") )
	if not self.effect:isPlaying() then
		self.effect:start()
	end
	self.cl = {}
	self.cl.Gui = sm.gui.createGuiFromLayout( "$MOD_DATA/Gui/cords.layout" )
	self.cl.Gui:setButtonCallback( "X0", "client_input" )
	self.cl.Gui:setButtonCallback( "X1", "client_input" )
	self.cl.Gui:setButtonCallback( "Y0", "client_input" )
	self.cl.Gui:setButtonCallback( "Y1", "client_input" )
	self.cl.Gui:setButtonCallback( "Z0", "client_input" )
	self.cl.Gui:setButtonCallback( "Z1", "client_input" )
	self.cl.Gui:setButtonCallback( "XX0", "client_input" )
	self.cl.Gui:setButtonCallback( "XX1", "client_input" )
	self.cl.Gui:setButtonCallback( "YY0", "client_input" )
	self.cl.Gui:setButtonCallback( "YY1", "client_input" )
	self.cl.Gui:setButtonCallback( "ZZ0", "client_input" )
	self.cl.Gui:setButtonCallback( "ZZ1", "client_input" )
	self.cl.Gui:setTextChangedCallback( "X", "client_input" )
	self.cl.Gui:setTextChangedCallback( "Y", "client_input" )
	self.cl.Gui:setTextChangedCallback( "Z", "client_input" )
	self.cl.Gui:setTextChangedCallback( "XX", "client_input" )
	self.cl.Gui:setTextChangedCallback( "YY", "client_input" )
	self.cl.Gui:setTextChangedCallback( "ZZ", "client_input" )
	
	self:client_refresheffect()
end

function Door:client_onUpdate()
	self.interactable:setUvFrameIndex(self.interactable:isActive() and 6 or 0)
end

function Door:client_onDestroy()
	if self.effect ~= nil then
		self.effect:stop()
		self.effect = nil
	end
end

function Door:client_onInteract(character, state)
	if not state then return end
	self.cl.Gui:open()
end