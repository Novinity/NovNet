local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NovNet = {}

-- For storing connected callbacks
NovNet.Connections = {}

local CONFIG = require(script.CONFIG)
local Logger = require(script.Logger)

local REMOTE_TYPES = {
	"RemoteEvent", "BindableEvent", "RemoteFunction", "BindableFunction", "UnreliableRemoteEvent"
}

-- Quickly find the event with the given name
local function _getEvent(eventName: string)
	return script.RegisteredEvents:FindFirstChild(eventName)
end

-- Creates an event
local function _registerEvent(eventName: string, eventType: "RemoteEvent" | "BindableEvent" | "RemoteFunction" | "BindableFunction" | "UnreliableRemoteEvent")
	if RunService:IsClient() then
		Logger.LogError("Events can only be registered on the server")
		return
	end
	
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	-- Make sure the event type is valid
	if not eventType or not table.find(REMOTE_TYPES, eventType) then
		Logger.LogWarning("No event type provided to _registerEvent, defaulting to " .. CONFIG.DEFAULT_EVENT_TYPE)
		eventType = CONFIG.DEFAULT_EVENT_TYPE
	end
	-- If the event already exists, cancel
	if _getEvent(eventName) then
		Logger.LogInfo("Event " .. eventName .. " is already registered.")
		return
	end
	
	-- Create the event
	local event = Instance.new(eventType)
	event.Name = eventName
	event.Parent = script.RegisteredEvents
	
	Logger.LogInfo("Registered new event " .. eventName)
end

-- Deletes an event
local function _unregisterEvent(eventName: string)
	-- Only allow unregistration on the server
	if RunService:IsServer() then
		if not eventName then
			Logger.LogError("No event name provided")
			return
		end
		
		-- Make sure the event exists
		local event = _getEvent(eventName)
		if event then
			event:Destroy()
			Logger.LogInfo("Unregistered event " .. eventName)
		else
			Logger.LogWarning("Could not unregister event " .. eventName)
		end
	else
		Logger.LogError("Events can only be unregistered on the server")
	end
end

-- Disconnects all callbacks connected to an event
local function _clearCallbacks(eventName: string, event: Instance?)
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	local callbacks = NovNet.Connections[eventName]
	if not callbacks then return end
	
	-- Clear connections in the table
	for _, conn in callbacks do
		conn:Disconnect()
	end
	
	-- Clear Function connections
	if event then
		if event:IsA("BindableFunction") then
			event.OnInvoke = nil
		elseif event:IsA("RemoteFunction") then
			if RunService:IsClient() then
				event.OnClientInvoke = nil
			end
			if RunService:IsServer() then
				event.OnServerInvoke = nil
			end
		end
	end
	
	NovNet.Connections[eventName] = nil
end

local function _isPlayer(instance: any): boolean
	return (instance and typeof(instance) == "Instance" and instance:IsA("Player"))
end

--[[
	Creates and registers a given event
	@server
	@param eventName: string - The name of the event to register.
	@param eventType: "RemoteEvent" | "BindableEvent" | "RemoteFunction" | "BindableFunction" - The type of event to register.
	@return nil
]]
function NovNet.RegisterEvent(eventName: string, eventType: "RemoteEvent" | "BindableEvent" | "RemoteFunction" | "BindableFunction" | "UnreliableRemoteEvent")
	_registerEvent(eventName, eventType)
end

--[[
	Unregisters and deletes a given event
	@server
	@param eventName: string - The name of the event to unregister.
	@return nil
]]
function NovNet.UnregisterEvent(eventName: string)
	_unregisterEvent(eventName)
end

--[[
	Connects a callback to the given event. If the event is not registered, it will be registered for you.
	@param eventName: string - The name of the event to connect to.
	@param callback: function - The function to call when the event is fired.
	@param suggestedType: "RemoteEvent" | "BindableEvent" | "RemoteFunction" | "BindableFunction" | "UnreliableRemoteEvent" - The type of event to create if the event does not exist.
	@return nil
]]
function NovNet.ListenEvent(eventName: string, callback, suggestedType: "RemoteEvent" | "BindableEvent" | "RemoteFunction" | "BindableFunction" | "UnreliableRemoteEvent")
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	-- Register the event if it doesn't exist
	if not _getEvent(eventName) then
		if RunService:IsClient() then
			Logger.LogWarning("Event " .. eventName .. " does not exist.")
			return
		end
		_registerEvent(eventName, suggestedType or CONFIG.DEFAULT_EVENT_TYPE)
	end
	
	-- Wait for the event to exist, cancel if it never does
	local event: RemoteEvent | BindableEvent | RemoteFunction | BindableFunction | UnreliableRemoteEvent = script.RegisteredEvents:WaitForChild(eventName, 10)
	if not event then
		Logger.LogWarning("Failed to find event " .. eventName)
		return
	end
	
	-- Make sure the event's table exists
	NovNet.Connections[eventName] = NovNet.Connections[eventName] or {}
	
	-- Connect differently based on event type
	if event:IsA("RemoteEvent") or event:IsA("UnreliableRemoteEvent") then
		
		if RunService:IsClient() then
			
			local conn = event.OnClientEvent:Connect(callback)
			NovNet.Connections[eventName][callback] = conn
			
			Logger.LogInfo("Now listening to client RemoteEvent " .. eventName)
			
		elseif RunService:IsServer() then
			
			local conn = event.OnServerEvent:Connect(callback)
			NovNet.Connections[eventName][callback] = conn
			
			Logger.LogInfo("Now listening to server RemoteEvent " .. eventName)
			
		end
		
	elseif event:IsA("BindableEvent") then
		
		local conn = event.Event:Connect(callback)
		NovNet.Connections[eventName][callback] = conn
		
		Logger.LogInfo("Now listening to BindableEvent " .. eventName)
		
	elseif event:IsA("RemoteFunction") then
		
		if RunService:IsClient() then
			event.OnClientInvoke = callback
			
			Logger.LogInfo("Now listening to client RemoteFunction " .. eventName)
		elseif RunService:IsServer() then
			event.OnServerInvoke = callback
			
			Logger.LogInfo("Now listening to server RemoteFunction " .. eventName)
		end
		
	elseif event:IsA("BindableFunction") then
		
		event.OnInvoke = callback
		
		Logger.LogInfo("Now listening to BindableFunction " .. eventName)
		
	else
		Logger.LogError("Unknown event type " .. eventName .. " (" .. typeof(event) .. ")")
	end
end

--[[
	Removes the callback from the given event
	@param eventName: string - The name of the event to stop listening to
	@param callback: function - The callback function to remove
	@returns nil
]]
function NovNet.UnlistenEvent(eventName: string, callback)
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	local event: RemoteEvent | BindableEvent | RemoteFunction | BindableFunction | UnreliableRemoteEvent = _getEvent(eventName)
	-- Make sure event exists
	if not event then
		Logger.LogWarning("Event " .. eventName .. " is not registered")
		return
	end
	
	-- Make sure the event's table exists
	NovNet.Connections[eventName] = NovNet.Connections[eventName] or {}
	
	-- Disconnect and remove callback
	if event:IsA("RemoteEvent") or event:IsA("UnreliableRemoteEvent") or event:IsA("BindableEvent") then
		
		local conn = NovNet.Connections[eventName][callback]
		if conn then
			conn:Disconnect()
			NovNet.Connections[eventName][callback] = nil
		end
		
	elseif event:IsA("RemoteFunction") then
		
		if RunService:IsClient() then
			event.OnClientInvoke = nil
		end
		if RunService:IsServer() then
			event.OnServerInvoke = nil
		end
		
	elseif event:IsA("BindableFunction") then
		
		event.OnInvoke = nil
		
	else
		Logger.LogError("Unknown event type " .. eventName .. " (" .. typeof(event) .. ")")
	end
end

--[[
	Fires an event with the given name
	@param eventName: string - The name of the event to fire
	@param wait: boolean - If true, the function will wait for the event to be registered
	@param ...: any - The arguments to pass to the event. Player should be the first argument if calling from the server to a client.
	@return: nil
]]
function NovNet.Fire(eventName: string, wait: boolean, ...)
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	-- Wait for the event if the firer wants to
	if wait then
		NovNet.WaitForEvent(eventName)
	end
	
	-- Make sure the event exists
	local event: RemoteEvent | BindableEvent | RemoteFunction | BindableFunction | UnreliableRemoteEvent = _getEvent(eventName)
	if not event then
		Logger.LogWarning("No event named " .. eventName .. " exists!")
		return
	end
	
	-- Fire event with args
	if event:IsA("RemoteEvent") or event:IsA("UnreliableRemoteEvent") then
		
		if RunService:IsClient() then
			event:FireServer(...)
		elseif RunService:IsServer() then
			-- Sanity check to make sure first argument is actually a player
			local player = ...
			if not _isPlayer(player) then
				Logger.LogError("Fire requires a Player as the first argument when called from the server")
				return
			end
			
			event:FireClient(...)
		end

	elseif event:IsA("BindableEvent") then

		event:Fire(...)

	elseif event:IsA("RemoteFunction") then

		if RunService:IsClient() then
			event:InvokeServer(...)
		elseif RunService:IsServer() then
			-- Sanity check to make sure first argument is actually a player
			local player = ...
			if not _isPlayer(player) then
				Logger.LogError("Fire requires a Player as the first argument when called from the server")
				return
			end
			
			event:InvokeClient(...)
		end

	elseif event:IsA("BindableFunction") then

		event:Invoke(...)

	else
		Logger.LogError("Unknown event type " .. eventName .. " (" .. typeof(event) .. ")")
	end
end

--[[
	Fires an event with the given name to all players. Only supports RemoteEvents and RemoteFunctions.
	@server
	@param eventName: string - The name of the event to fire
	@param wait: boolean - If true, the function will wait for the event to be registered
	@param ...: any - The arguments to pass to the event.
	@return: nil
]]
function NovNet.FireAll(eventName: string, wait: boolean, ...)
	if not RunService:IsServer() then
		Logger.LogError("Cannot use FireAll on the client!")
		return
	end
	
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end

	-- Wait for the event if the firer wants to
	if wait then
		NovNet.WaitForEvent(eventName)
	end

	-- Make sure the event exists
	local event: RemoteEvent | BindableEvent | RemoteFunction | BindableFunction | UnreliableRemoteEvent = _getEvent(eventName)
	if not event then
		Logger.LogWarning("No event named " .. eventName .. " exists!")
		return
	end

	-- Fire event to all clients
	if event:IsA("RemoteEvent") or event:IsA("UnreliableRemoteEvent") then

		event:FireAllClients(...)

	elseif event:IsA("RemoteFunction") then

		for _, player: Player in Players:GetPlayers() do
			event:InvokeClient(player, ...)
		end

	else
		Logger.LogError("Unknown/unsupported event type " .. eventName .. " (" .. typeof(event) .. ")")
	end
end

--[[
	Waits for an event to exist
	@param eventName: string - The name of the event to wait for
	@return: nil
	@yields
]]
function NovNet.WaitForEvent(eventName: string, timeout: number?)
	if not eventName then
		Logger.LogError("No event name provided")
		return
	end
	
	local result = script.RegisteredEvents:WaitForChild(eventName, timeout or CONFIG.DEFAULT_WAIT_TIMEOUT)
	if not result then
		Logger.LogWarning("Timed out waiting for event " .. eventName)
	end
end

function _init()
	-- Clear out all callbacks for an event after it gets deleted
	script.RegisteredEvents.ChildRemoved:Connect(function(child)
		_clearCallbacks(child.Name, child)
	end)
end

_init()

return NovNet
