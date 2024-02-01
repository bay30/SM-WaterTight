FluidInput = class()
FluidInput.maxParentCount = 1
FluidInput.maxChildCount = 255
FluidInput.connectionInput = sm.interactable.connectionType.logic
FluidInput.connectionOutput = sm.interactable.connectionType.water
FluidInput.colorNormal = sm.color.new( 0, 0, 1 )
FluidInput.colorHighlight = sm.color.new( 0, .5, 1 )
FluidInput.poseWeightCount = 1

function FluidInput:server_onFixedUpdate()
	local parent = self.interactable:getSingleParent()
	if parent then
		self.interactable:setActive(parent:isActive())
	end
end

function FluidInput:client_onUpdate()
	self.interactable:setUvFrameIndex(self.interactable:isActive() and 6 or 0)
end