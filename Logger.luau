local CONFIG = require(script.Parent.CONFIG)

local Logger = {}

PREFIX = "[NovNet]"

function Logger.LogInfo(text: string)
	if not CONFIG.LOGGING then return end
	print(PREFIX, text)
end

function Logger.LogWarning(text: string)
	if not CONFIG.LOGGING then return end
	warn(PREFIX, text)
end

function Logger.LogError(text: string)
	if not CONFIG.LOGGING then return end
	error(PREFIX, text)
end

return Logger
