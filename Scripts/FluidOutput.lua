FluidOutput = class()
FluidOutput.maxParentCount = 255
FluidOutput.maxChildCount = 0
FluidOutput.connectionInput = sm.interactable.connectionType.water
FluidOutput.connectionOutput = sm.interactable.connectionType.none
FluidOutput.colorNormal = sm.color.new( 0, 0, 1 )
FluidOutput.colorHighlight = sm.color.new( 0, .5, 1 )
FluidOutput.poseWeightCount = 1

function FluidOutput:server_onFixedUpdate()
	local state = false
	for _, v in ipairs(self.interactable:getParents()) do
		if v:isActive() then
			state = true
		end
	end

	self.interactable:setActive(state)
end

function FluidOutput:client_onUpdate()
	self.interactable:setUvFrameIndex(self.interactable:isActive() and 6 or 0)
end