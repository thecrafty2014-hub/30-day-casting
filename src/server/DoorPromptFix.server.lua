--[[
	DoorPromptFix.server.lua
	Fixes ProximityPrompts that show up on the WRONG side of doors.

	How it works:
	  * A ProximityPrompt appears at the position of its parent.
	  * If the prompt sits inside an Attachment, we move that Attachment to the
	    other side of the door (flip its local Z).
	  * If the prompt sits directly on a Part, we create an Attachment on the
	    front face (-Z) and move the prompt into it.
	  * The prompt object itself is never recreated, so ActionText, ObjectText,
	    KeyboardKeyCode, HoldDuration, and any door scripts already connected to
	    .Triggered keep working.

	Settings are below. If the prompts end up on the wrong side again,
	change MODE to "Front" (or back to "Flip").
]]

-- ===================== SETTINGS =====================
-- "Flip"  = move every prompt to the OPPOSITE side from where it is now
-- "Front" = always put prompts on the front face (-Z) of the door part
local MODE = "Flip"

-- true = only fix prompts whose part/model name contains "door"
-- false = fix every ProximityPrompt in workspace
local ONLY_DOORS = false

-- How far outside the door surface the prompt sits (studs)
local SURFACE_OFFSET = 0.1

-- Wait so door scripts can find and connect their prompts first
local START_DELAY = 1
-- ====================================================

local FIXED_ATTR = "DoorPromptFixed"

local function getDoorPart(prompt)
	local parent = prompt.Parent
	if parent == nil then
		return nil, nil
	end
	if parent:IsA("Attachment") then
		local part = parent.Parent
		if part and part:IsA("BasePart") then
			return part, parent
		end
	elseif parent:IsA("BasePart") then
		return parent, nil
	elseif parent:IsA("Model") and parent.PrimaryPart then
		return parent.PrimaryPart, nil
	end
	return nil, nil
end

local function looksLikeDoor(part)
	local node = part
	while node and node ~= workspace do
		if string.find(string.lower(node.Name), "door") then
			return true
		end
		node = node.Parent
	end
	return false
end

local function fixPrompt(prompt)
	if prompt:GetAttribute(FIXED_ATTR) then
		return -- already fixed, don't flip twice
	end

	local part, attachment = getDoorPart(prompt)
	if not part then
		warn("[DoorPromptFix] Skipped prompt (no door part found): " .. prompt:GetFullName())
		return
	end
	if ONLY_DOORS and not looksLikeDoor(part) then
		return
	end

	local halfDepth = part.Size.Z / 2 + SURFACE_OFFSET

	if attachment then
		local pos = attachment.Position
		local newZ
		if MODE == "Flip" then
			-- Mirror to the other side; if it was in the middle, push to front.
			if math.abs(pos.Z) < 0.01 then
				newZ = -halfDepth
			else
				newZ = (pos.Z > 0) and -halfDepth or halfDepth
			end
		else -- "Front"
			newZ = -halfDepth
		end

		if math.abs(pos.Z - newZ) < 0.01 then
			print("[DoorPromptFix] Already on correct side: " .. part:GetFullName())
		else
			attachment.Position = Vector3.new(pos.X, pos.Y, newZ)
			print(string.format("[DoorPromptFix] Fixed door prompt on: %s (Z %.2f -> %.2f)",
				part:GetFullName(), pos.Z, newZ))
		end
	else
		-- Prompt sits directly on the part: give it an attachment on the front face.
		local newAttachment = Instance.new("Attachment")
		newAttachment.Name = "PromptAttachment"
		newAttachment.Position = Vector3.new(0, 0, -halfDepth)
		newAttachment.Parent = part
		prompt.Parent = newAttachment -- same prompt object, all settings kept
		print("[DoorPromptFix] Fixed door prompt on: " .. part:GetFullName() .. " (created front attachment)")
	end

	prompt:SetAttribute(FIXED_ATTR, true)
end

task.wait(START_DELAY)

local count = 0
for _, obj in ipairs(workspace:GetDescendants()) do
	if obj:IsA("ProximityPrompt") then
		local ok, err = pcall(fixPrompt, obj)
		if ok then
			count += 1
		else
			warn("[DoorPromptFix] Error on " .. obj:GetFullName() .. ": " .. tostring(err))
		end
	end
end
print(string.format("[DoorPromptFix] Done. Checked %d ProximityPrompt(s). MODE = %s", count, MODE))

-- Also fix doors that get added later (e.g. spawned/cloned doors)
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("ProximityPrompt") then
		task.defer(function()
			local ok, err = pcall(fixPrompt, obj)
			if not ok then
				warn("[DoorPromptFix] Error on " .. obj:GetFullName() .. ": " .. tostring(err))
			end
		end)
	end
end)
