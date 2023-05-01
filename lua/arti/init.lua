local project = require('arti.project')
local utils     = require('arti.utils')

local arti = {
    storage = utils.storage_path,
    project = project
}

function arti.setup(config)
    for mod, opts in pairs(config or {}) do
        if opts.enabled == true then
            if arti[mod] ~= nil and type(arti[mod].setup) == "function" then
                arti[mod].setup(opts, arti)
            end
        end
    end
end

return arti
