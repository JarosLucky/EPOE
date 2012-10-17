-- EPOE Server Code

require ( "hook" )

local G=_G

local ValidEntity=ValidEntity
local assert=assert
local RecipientFilter=RecipientFilter
local error=error
local pairs=pairs
local pcall=pcall
local tostring=tostring
local tonumber=tonumber
local CreateConVar=CreateConVar
local setmetatable=setmetatable

local len=string.len

local concommand=concommand
local player=player
local umsg=umsg
local timer=timer
local string=string
local util=util
local hook=hook
local table=table
local bit=bit
if not bit then error"You need http://luaforge.net/projects/bit/ OR https://dl.dropbox.com/u/1910689/gmod/bit.lua for Garry's Mod 12!" end

--local GMOD_VERSION=VERSION
-- inform the client of the version
CreateConVar( "epoe_version", "2.4", FCVAR_NOTIFY )

local epoe_client_traces=CreateConVar("epoe_client_traces","0")
local epoe_server_traces=CreateConVar("epoe_server_traces","0")
local epoe_client_errors=CreateConVar("epoe_client_errors","1")

module( "epoe" )

-- Constants 
local recover_time = 2 -- 0.1 = agressive. 2 = safer. 

-- Store global old print functions. Original ones.
G._Msg=G._Msg or G.Msg
G._MsgC=G._MsgC or G.MsgC or G.Msg
G._MsgN=G._MsgN or G.MsgN
G._print=G._print or G.print


-- Store local real messages, real ones
RealMsg=G._Msg

MsgC_Compat=function(col,...)RealMsg(...)end
RealMsgC=G._MsgC and G._MsgC!=G.Msg and G._MsgC or MsgC_Compat

RealMsgN=G._MsgN
RealPrint=G._print
RealErrorNoHalt=G.ErrorNoHalt

/*-- Big Hack
local function ErrorNoHalt(...)
	local t={...}
	G.timer.Simple(0.01,function()
		RealErrorNoHalt(unpack(t))
	end)
end
*/


------------------ SUBS SYSTEM ------------------

	-- Subscribed people
	Sub = {
		-- player = true
	}
	-- Garbage collect whenever you want...
	setmetatable(Sub,{__mode="k"})

	HasNoSubs=true

	function AddSub(pl)
		if (pl and pl.IsValid and pl:IsValid()) and pl:IsPlayer() then
			HasNoSubs=false
			Sub[pl]=true
			Transmit(IS_EPOE,"_S",pl)
		end
	end

	function DelSub(pl)
		Sub[pl]=nil
		CalculateSubs()
		Transmit(IS_EPOE,"_US",pl)
	end

	function CalculateSubs()
		for k,v in pairs(Sub) do
			HasNoSubs=false
			return
		end

		HasNoSubs=true

		DisableTick()
	end

	-- Could probably remove this.
	function OnEntityRemoved(pl)
		if !(pl and pl.IsValid and pl:IsValid()) then return end
		if 	pl:IsPlayer() then
			DelSub(pl)
		end
	end
	hook.Add('EntityRemoved',TagHuman,OnEntityRemoved)

	-- Override for admin mods :o
	function CanSubscribe(pl,unsubscribe)
		--RealPrint( tostring(pl)..(unsubscribe and "unsubscribed from" or "subscribed to").." EPOE" )
		return pl:IsAdmin("epoe")
	end

	function OnSubCmd(pl,_,argz)
		if not (pl and pl.IsValid and pl:IsValid()) then return end -- Consoles can't subscribe. Sorry :(

		local wantsub=util.tobool(argz[1] or "0")

		if wantsub then
			if CanSubscribe(pl) then
				AddSub(pl)
			else
				Transmit(IS_EPOE,"_NA",pl)
			end
		else
			DelSub(pl)
			CanSubscribe(pl,true)
		end

	end
	concommand.Add(Tag,OnSubCmd)

	function GetSubscribers()
		return Sub
	end


RF=RecipientFilter()
local RF=RF

-- Refresh pretty much everything for us
function Refresh()
	--RealMsgN(InEPOE and "IN EPOE","Refresh")
	RF:RemoveAllPlayers()
	CalculateSubs()
	if HasNoSubs then return end
	for pl,_ in pairs(Sub) do
		if (pl and pl.IsValid and pl:IsValid()) and CheckSub(pl) then
			RF:AddPlayer(pl)
		end
	end
end

-- Override and return false to prevent player from receiving more updates.
-- Added for dynamic demote from EPOE. Can get spammed so should be lightweight to call.
function CheckSub()
	return true
end

-------------------------------------------------



-- Prevent local errors from screwing our system
InEPOE=true

-- Holds the messages that are to be sent to clients
Messages=FIFO() -- shared.lua
local Messages=Messages

-- Flood Protection
function Recover()
	EnableTick()
	Messages:clear() -- We were in flood protection mode. Don't continue doing it...

	InEPOE = false

	local payload={ flag=IS_EPOE,
	msg="Queue reset! (Over "..tostring(MaxQueue or "unknown").." messages pushed triggering safeguards)" }
	Messages:push(payload)

end


local TickEnabled=false
function EnableTick()
	if TickEnabled then return end
	TickEnabled = true
	hook.Add('Tick',TagHuman,OnTick)
end
local EnableTick=EnableTick

function DisableTick()
	--RealMsgN(InEPOE and "IN EPOE",TickEnabled,"DisableTick")
	if not TickEnabled then return end
	TickEnabled = false
	hook.Remove('Tick',TagHuman)
end
local DisableTick=DisableTick

function HitMaxQueue()

	if Messages:len() > MaxQueue then

		DisableTick()
		Messages:clear()

		InEPOE=true
		timer.Simple(recover_time,Recover)

		return true

	end

end

------------------
-- Overrides
------------------
	function OnMsg(...)	
		if InEPOE or HasNoSubs then pcall(RealMsg,...) else
			InEPOE = true	

				if HitMaxQueue() then return end

				EnableTick()

				
				local err,str=pcall(ToStringEx,"",...) -- just to be sure

				if str then
					PushPayload( IS_MSG , str )
				end

				pcall(RealMsg,...)

			InEPOE=false
		end
	end

	-- TODO: Add Colors..
	function OnMsgC(color,...)	
		if InEPOE or HasNoSubs then pcall(RealMsgC,color,...) else
			InEPOE = true	

				if HitMaxQueue() then return end

				EnableTick()

				
				local err,str=pcall(ToStringEx,"",...)

				if str then
					local colbytes = ColorToStr(color)
					PushPayload( IS_MSGC , colbytes..str )
				end

				pcall(RealMsgC,color,...)

			InEPOE=false
		end
	end	

	function OnMsgN(...)
		if InEPOE or HasNoSubs then pcall(RealMsgN,...) else
			InEPOE = true	

				if HitMaxQueue() then return end

				EnableTick()

				
				local err,str=pcall(ToStringEx,"",...)
				if str then
					PushPayload( IS_MSGN , str )
				end

				pcall(RealMsgN,...)

			InEPOE=false
		end
	end

	function OnPrint(...)
		if InEPOE or HasNoSubs then pcall(RealPrint,...) else
			InEPOE = true	

				if HitMaxQueue() then return end

				EnableTick()

				
				local err,str=pcall(ToStringEx," ",...)
				if str then
					PushPayload( IS_PRINT , str )
				end

				pcall(RealPrint,...)

			InEPOE=false
		end
	end

	function OnLuaError(str)
		if InEPOE or HasNoSubs then return end

		InEPOE = true

			if HitMaxQueue() then return end

			EnableTick()

			PushPayload( IS_ERROR , tostring(str) )

		InEPOE=false
	end
	function OnLuaErrorNoHalt(...)
		if InEPOE or HasNoSubs then pcall(RealErrorNoHalt,...) else
			InEPOE = true

				if HitMaxQueue() then return end

				EnableTick()

				
				local err,str=pcall(ToStringEx," ",...)
				if str then
					PushPayload( IS_ERROR , str )
				end

				pcall(RealErrorNoHalt,...)

			InEPOE=false
		end
	end
------------------


function SamePayload(a,b)
	if a==b then return true end -- nil or same message will pass this, hmm
	if not a or not b then return false end

	-- strip repeat flags for comparison
	--a.flag=a.flag BAND andnot(IS_REPEAT)
	--b.flag=b.flag BAND andnot(IS_REPEAT)

	return a.flag==b.flag and a.msg==b.msg
end

-- Check if the payload is same and make a new payload and push that instead
-- NOTE: Removed due to unforeseen behaviour causing more problems than fixes
function DoPush(payload)
	--[[local last = Messages:peek()
	if SamePayload(last,payload) then
		local newload={
			flag= payload.flag|IS_REPEAT,
			msg="" -- no message as previous message sent it
			}
		return Messages:push(newload)
	end]]

	Messages:push(payload)
end

-- Divides the payload to ok sized chunks and THEN sends it. GMod13 needs this too as you don't want to receive 66*64KB every second in the mega worst case scenario
function PushPayload(flags,text)
	
	local txt,i=true,1 
	local size=190 -- usermessage size. GMod13 might want bigger at some point :)
	local textlen=#text
	local first=true
	while txt and txt!="" do 
	
		txt=text:sub(i,i+size-1)
		i=i+size
		if txt!="" or first then
			local curflags=flags
			if textlen>=i then
				curflags=bit.bor(flags,IS_SEQ) -- bitwise, don't let me down <3
			end
			DoPush{
				flag=curflags, 
				msg=txt
			}			
		end
		first=false
		
		if i>63*1024 then -- let's stop here. You've done well enough...
			EnableTick()
			Messages:clear()
			InEPOE=false			
			Messages:push{flag=IS_EPOE,msg="Cancelling messages, too many iterations."}
			return
		end
	end
end



function Transmit(flags,msg,rf)
	umsg.Start(Tag,rf==true and RF or rf)
		umsg.Char(flags-128)
		umsg.String(msg)
	umsg.End()
end

------------------
-- Transmit one from the queue
-- Return: true if queue is empty
------------------
function OnBeingTransmit()

	local payload=Messages:pop()
	if payload==nil then return true end
	local flags=payload.flag or 0
	assert(flags>=0)
	assert(flags<=255)

	local msg=payload.msg or "EPOE ERROR"
	Transmit(flags,msg,true)
end


------------------
-- What makes you tick!
------------------
function OnTick()
	if InEPOE then return end
	--RealMsgN(InEPOE and "IN EPOE","OnTick")
	InEPOE = true

		Refresh()
		if HasNoSubs then 
			Messages:clear() 
		elseif !HitMaxQueue() and Messages:len()>0 then 

			for i=1,UMSGS_IN_TICK do 

				if OnBeingTransmit() then -- No more in queue
					DisableTick()
					break
				end

			end

		end

	InEPOE=false
end

-- Initialize EPOE 
function Initialize()
	InEPOE=true

		G.require	"enginespew"

		G.Msg			= OnMsg
		G.MsgC			= OnMsgC
		G.MsgN			= OnMsgN
		G.print			= OnPrint
		if G.VERSION>150 then
			G.ErrorNoHalt	= OnLuaErrorNoHalt
			local incoming_clienterr
			hook.Add("EngineSpew",TagHuman,function(a,msg,c,d)
				if (!msg or msg:sub(1,1)!="[" or a!=0 or c!="" or d!=0  ) and not incoming_clienterr then return end
				if InEPOE then return end
				
				if incoming_clienterr then
					--RealPrint("CLERRSTOP: '"..msg.."'")
					if not epoe_client_errors:GetBool() then return end
					local pl,userid=false,incoming_clienterr:match(".+|(%d*)|.-$")
					incoming_clienterr=false
					if userid then
						userid=tonumber(userid)
						for k,v in pairs(player.GetAll()) do
							if v:UserID()==userid then
								pl=v
								break
							end
						end
					end
					msg=msg and msg:gsub("^\n*","") -- trim newlines from beginning
					
					-- epoe_client_traces=print everything from the error 
					local newmsg = not  epoe_client_traces:GetBool() and msg:match("%[ERROR%] (.-)\n") or (msg:match("%[ERROR%] (.+)") or msg)
					OnLuaError( (pl and tostring(pl) or "CLIENT").." ERR: "..newmsg )
					
					return 
					
				end
				if msg:find("] Lua Error:",1,true) then 
					--RealPrint("CLERRSTART: '"..msg.."'")
					incoming_clienterr=msg 
					return
				end
				if msg:find(":%d+%] ") then 
					local newmsg = not epoe_server_traces:GetBool() and msg:match("(.-)\n") or msg
					
					OnLuaError( newmsg )
					return 
				end
			
			end)
		else
			local inhook = false -- Prevent deadloop. Should not happen type.
			hook.Add("EngineSpew", TagHuman, function(spewType, msg, group, level) 
				if inhook then return end
				inhook = true

				if spewType == 1 --[[ = SPEW_WARNING]] then -- TODO: Add possibility for full console output.
					OnLuaError( msg ) 
				end
				inhook = false
			end )
		end
		G.print	"EPOE hooks added"
		

	InEPOE=false
end

-- TODO: Initialize earlier to hook even module prints
Initialize()