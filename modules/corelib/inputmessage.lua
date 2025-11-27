function InputMessage:getData()
    local dataType = self:getU8()
    if dataType == NetworkMessageTypes.Boolean then
        return numbertoboolean(self:getU8())
    elseif dataType == NetworkMessageTypes.U8 then
        return self:getU8()
    elseif dataType == NetworkMessageTypes.U16 then
        return self:getU16()
    elseif dataType == NetworkMessageTypes.U32 then
        return self:getU32()
    elseif dataType == NetworkMessageTypes.U64 then
        return self:getU64()
    elseif dataType == NetworkMessageTypes.NumberString then
        return tonumber(self:getString())
    elseif dataType == NetworkMessageTypes.String then
        return self:getString()
    elseif dataType == NetworkMessageTypes.Table then
        return self:getTable()
    else
        perror('Unknown data type ' .. dataType)
    end
    return nil
end

function InputMessage:getTable()
    local ret = {}
    local size = self:getU16()
    for i = 1, size do
        local index = self:getData()
        local value = self:getData()
        ret[index] = value
    end
    return ret
end

function InputMessage:getColor()
    local color = {}
    color.r = self:getU8()
    color.g = self:getU8()
    color.b = self:getU8()
    color.a = self:getU8()
    return color
end

function InputMessage:getPosition()
    local position = {}
    position.x = self:getU16()
    position.y = self:getU16()
    position.z = self:getU8()
    return position
end


function InputMessage:getOutfit()
	local lookType = self:getU16()
	local outfit = {}

	if lookType ~= 0 then
		outfit.type = lookType
		outfit.head = self:getU8()
		outfit.body = self:getU8()
		outfit.legs = self:getU8()
		outfit.feet = self:getU8()
		outfit.addons = self:getU8()
	else
		outfit.auxType = self:getU16()
	end

	outfit.wings = self:getU16()
	outfit.aura = self:getU16()
	outfit.shader = self:getString()

	return outfit
end
