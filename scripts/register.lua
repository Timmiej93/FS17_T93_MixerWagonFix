-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --
-- Register script by Rival, modified by Timmiej93
--
-- This file is inspired by the register script as created by 'Rival'.
--
-- Purpose: This file registers the specialisation 'MixerWagonFix', and inserts it into each 
--     vehicle with the 'mixerWagon' specialization. 
-- 
-- Authors: Timmiej93
--
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --

SpecializationUtil.registerSpecialization("MixerWagonFix", "MixerWagonFix", g_currentModDirectory.."scripts/MixerWagonFix.lua")

mwfRegister = {};

function mwfRegister.contains(table, specString)
	for _,v in pairs(table) do
		if v == SpecializationUtil.getSpecialization(specString) then
			return true;
		end
	end
	return false;
end

function mwfRegister:loadMap(name)
	if self.firstRun == nil then
		self.firstRun = false;
		
		for k,vehicleType in pairs(VehicleTypeUtil.vehicleTypes) do
			if vehicleType ~= nil then
				local allowInsertion = true;
				for i = 1, table.maxn(vehicleType.specializations) do
					local specialization = vehicleType.specializations[i];
					if specialization ~= nil and specialization == SpecializationUtil.getSpecialization("mixerWagon") then
						local vehicleName = vehicleType.name 
						local location = string.find(vehicleName, ".", nil, true)
						if location ~= nil then
							local name = string.sub(vehicleName, 1, location-1);
							if rawget(SpecializationUtil.specializations, string.format("%s.MixerWagonFix", name)) ~= nil then
								allowInsertion = false;								
							end;							
						end;
						if allowInsertion then	
							table.insert(vehicleType.specializations, SpecializationUtil.getSpecialization("MixerWagonFix"));
							break;
						end;
					end;
				end;
			end;	
		end;
	end;
end;

function mwfRegister:deleteMap()end;
function mwfRegister:keyEvent(unicode, sym, modifier, isDown)end;
function mwfRegister:mouseEvent(posX, posY, isDown, isUp, button)end;
function mwfRegister:update(dt)end;
function mwfRegister:draw()end;

addModEventListener(mwfRegister);