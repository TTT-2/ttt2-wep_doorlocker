if SERVER then
	AddCSLuaFile()

	resource.AddFile("materials/gui/ttt/icon_doorlocker.vmt")
end

local sounds = {
	empty = Sound("Weapon_SMG1.Empty"),
	lock = Sound("doors/door_metal_medium_close1.wav"),
	unlock = Sound("buttons/latchunlocked2.wav"),
	open = Sound("doors/door1_move.wav")
}

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.ViewModelFOV = 78
	SWEP.DrawCrosshair = false
	SWEP.ViewModelFlip = false

	SWEP.EquipMenuData = {
		type = "item_weapon",
		name = "weapon_doorlocker_name",
		desc = "weapon_doorlocker_desc"
	}

	SWEP.Icon = "vgui/ttt/icon_doorlocker"
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = {ROLE_TRAITOR, ROLE_DETECTIVE}

SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"

SWEP.AutoSpawnable = false
SWEP.NoSights = true

SWEP.HoldType = "pistol"
SWEP.LimitedStock = true

SWEP.Primary.Recoil = 0
SWEP.Primary.ClipSize = 5
SWEP.Primary.DefaultClip = 5
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 1
SWEP.Primary.Ammo = "none"

SWEP.Secondary.Recoil = 0
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 0.5

if SERVER then
	util.AddNetworkString("WeaponDoorlockerUpdate")

	function SWEP:Deploy()
		net.Start("WeaponDoorlockerUpdate")
		net.WriteBool(true)
		net.Send(self:GetOwner())

		-- store owner in extra variable because the owner isn't valid
		-- once OnDrop is called
		self.notfiyOwner = self:GetOwner()

		self.BaseClass.Deploy(self)
	end

	function SWEP:Holster(wep)
		net.Start("WeaponDoorlockerUpdate")
		net.WriteBool(false)
		net.Send(self:GetOwner())

		self.notfiyOwner = nil

		return self.BaseClass.Holster(self, wep)
	end

	function SWEP:OnDrop()
		self.BaseClass.OnDrop(self)

		if not IsValid(self.notfiyOwner) then return end

		net.Start("WeaponDoorlockerUpdate")
		net.WriteBool(false)
		net.Send(self.notfiyOwner)

		self.notfiyOwner = nil
	end
end

if CLIENT then
	local matScreen = Material("models/weapons/v_toolgun/screen")
	local txBackground = surface.GetTextureID("models/weapons/doorlocker/screen_bg")
	local TEX_SIZE = 256
	local RTTexture = GetRenderTarget("TTT2Doorlocker", TEX_SIZE, TEX_SIZE)

	function SWEP:RenderScreen()
		-- Set the material of the screen to our render target
		matScreen:SetTexture("$basetexture", RTTexture)

		-- Set up our view for drawing to the texture
		render.PushRenderTarget(RTTexture)
		cam.Start2D()

		-- Background
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetTexture(txBackground)
		surface.DrawTexturedRect(0, 0, TEX_SIZE, TEX_SIZE)

		cam.End2D()
		render.PopRenderTarget()
	end

	function SWEP:Initialize()
		self:AddHUDHelp("door_help_msb1", "door_help_msb2", true)

		return self.BaseClass.Initialize(self)
	end

	local validDoors = {}

	net.Receive("WeaponDoorlockerUpdate", function()
		if net.ReadBool() then
			local doors = door.GetAll()

			for i = 1, #doors do
				local doorEntity = doors[i]

				if not IsValid(doorEntity) or not doorEntity:PlayerCanOpenDoor()
					or not door.IsValidNormal(doorEntity:GetClass())
				then continue end

				validDoors[#validDoors + 1] = doorEntity
			end

			thermalvision.SetBackgroundColoring(true)
			thermalvision.Add(validDoors, THERMALVISION_MODE_BOTH)
		else
			thermalvision.SetBackgroundColoring(false)
			thermalvision.Remove(validDoors)
		end
	end)
end

function SWEP:GetEntity()
	local owner = self:GetOwner()

	local trace = owner:GetEyeTrace(MASK_SHOT_HULL)
	local distance = trace.StartPos:Distance(trace.HitPos)
	local ent = trace.Entity

	if not IsValid(ent) or not ent:IsDoor() or not ent:PlayerCanOpenDoor() or distance > 100 then
		owner:EmitSound(sounds["empty"])

		return
	end

	return ent
end

function SWEP:PrimaryAttack()
	if CLIENT then return end

	local owner = self:GetOwner()
	local ent = self:GetEntity()

	if not IsValid(ent) then return end

	if not self:CanPrimaryAttack() then
		owner:EmitSound(sounds["empty"])

		return
	end

	if not door.IsValidNormal(ent:GetClass()) then
		LANG.Msg(owner, "door_not_lockable", nil, MSG_MSTACK_WARN)

		owner:EmitSound(sounds["empty"])

		return
	end

	if ent:IsDoorLocked() then
		LANG.Msg(owner, "door_already_locked", nil, MSG_MSTACK_WARN)

		owner:EmitSound(sounds["empty"])

		return
	end

	if ent:IsDoorOpen() then
		LANG.Msg(owner, "door_is_open", nil, MSG_MSTACK_WARN)

		owner:EmitSound(sounds["empty"])

		return
	end

	ent.doorlockerData = {
		ply = owner,
		time = CurTime(),
		wasDestructible = ent:DoorIsDestructible()
	}

	if IsValid(ent.otherPairDoor) then
		ent.otherPairDoor.doorlockerData = {
			ply = owner,
			time = CurTime(),
			wasDestructible = ent.otherPairDoor:DoorIsDestructible()
		}
	end

	ent:LockDoor(ply)
	ent:MakeDoorDestructable(true)
	owner:EmitSound(sounds["lock"])

	LANG.Msg(owner, "door_now_locked", nil, MSG_MSTACK_PLAIN)

	self:TakePrimaryAmmo(1)
end

function SWEP:SecondaryAttack()
	if CLIENT then return end

	local owner = self:GetOwner()
	local ent = self:GetEntity()

	if not IsValid(ent) then return end

	if not door.IsValidNormal(ent:GetClass()) then
		owner:EmitSound(sounds["empty"])

		return
	end

	if not ent:IsDoorLocked() then
		LANG.Msg(owner, "door_not_locked", nil, MSG_MSTACK_WARN)

		owner:EmitSound(sounds["empty"])

		return
	end

	if ent:IsDoorLocked() and (not ent.doorlockerData or ent.doorlockerData.ply ~= owner) then
		LANG.Msg(owner, "door_locked_not_you", nil, MSG_MSTACK_WARN)

		owner:EmitSound(sounds["empty"])

		return
	end

	ent:UnlockDoor(ply)
	ent:MakeDoorDestructable(ent.doorlockerData.wasDestructible)
	owner:EmitSound(sounds["unlock"])

	LANG.Msg(owner, "door_now_unlocked", nil, MSG_MSTACK_PLAIN)
end

-- do not play sound when swep is empty
function SWEP:DryFire()
	return false
end
