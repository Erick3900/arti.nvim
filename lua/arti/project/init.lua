local path = require('plenary.path')
local utils = require('arti.utils')
local default_config = require('arti.project.config')
local workspace = require('arti.project.workspace')

local project = {
    storage = utils.storage_path,
    workspaces = {},
    config = nil,
    active = nil
}

function project.check(filepath)
    if not filepath:exists() then
        return
    end

    for _, p in ipairs(filepath:parents()) do
        if project.load(p) then
            break
        end
    end
end

function project.has_open_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            return true
        end
    end

    return false
end

function project.load(searchpath, files)
    searchpath = searchpath or vim.fn.getcwd()
    files = files or {}

    local ws_loc = path:new(searchpath, project.config.impl.workspace)

    if ws_loc:is_dir() then
        local ws_path = ws_loc:parent():parent()
        local ws = project.workspaces[tostring(ws_path)]

        if ws then
            ws:set_active()
        else
            ws = workspace(project.config, ws_path)
            project.workspaces[tostring(ws_path)] = ws
            ws:set_active()

            if vim.tbl_isempty(files) and not project.has_open_buffers() then
                vim.api.nvim_command(":enew")
            else
                for _, relpath in ipairs(files) do
                    local filepath = path:new(ws.rootpath, relpath)

                    if filepath:is_file() then
                        vim.api.nvim_command(":e " .. tostring(filepath))
                    end
                end
            end
        end

        project.active = ws
    else
        project.active = nil
    end

    return project.active ~= nil
end

function project.workspace_config_files()
    return vim.tbl_filter(function(n)
        return vim.endswith(n, ".lua")
    end, vim.tbl_values(project.config.impl))
end

function project.setup(config)
    project.config = vim.tbl_deep_extend(
        "force",
        default_config,
        config or {}
    )

    local group_id = vim.api.nvim_create_augroup(
        "arti_workspace",
        { clear = true }
    )

    vim.api.nvim_create_autocmd(
        { "BufNewFile", "BufRead" },
        {
            group = group_id,
            pattern = vim.tbl_map(function(n)
                return "*" .. utils.dirsep .. project.config.impl.workspace .. utils.dirsep .. n
            end, project.workspace_config_files()),
            callback = function(arg)
                -- TODO
            end
        }
    )

    vim.api.nvim_create_autocmd(
        "BufEnter",
        {
            group = group_id,
            callback = function(arg)
                if #arg.file > 0 then
                    project.check(path:new(arg.file))
                end
            end
        }
    )

    vim.api.nvim_create_user_command(
        "ArtiProject",
        function(opts)
            local action, arg = opts.fargs[1], opts.fargs[2]

            if action == nil then
                error("Action required")
            end

            local check_arg = function()
                if arg == nil then
                    error("Invalid argument")
                end
            end

            if action == "create" then
                -- TODO
            elseif action == "init" then
                -- TODO
            elseif action == "load" then
                project.load()
            elseif action == "jobs" then
                local runner = require('arti.project.runner')

                runner.show_jobs(project.config)
            elseif action == "config" then
                local ws = project.active

                if not ws then
                    return
                end

                ws:edit_config()
            elseif action == "launch" then
                local ws = project.active

                if not ws then
                    return
                end

                ws:show_launch()
            elseif action == "tasks" then
                local ws = project.active

                if not ws then
                    return
                end

                ws:show_tasks()
            elseif action == "open" then
                check_arg()

                local ws = project.active

                if not ws then
                    return
                end

                if arg == "launch" then
                    ws:open_launch()
                elseif arg == "tasks" then
                    ws:open_tasks()
                elseif arg == "variables" then
                    ws:open_variables()
                elseif arg == "config" then
                    ws:open_config()
                end
            else
                print("Unknown action '"..action.."'")
            end
        end,
        {
            nargs = "+",
            desc = "ArtiProject",
            complete = function(_, line)
                local ws = project.active
                local args = utils.cmdline_split(line)

                table.remove(args, 1)

                local COMMANDS = { "create", "init", "load" }

                if ws then
                    COMMANDS = vim.list_extend(COMMANDS, {
                        "jobs",
                        "config",
                        "launch",
                        "tasks",
                        "open"
                    })
                end

                if vim.tbl_isempty(args) then
                    return COMMANDS
                end

                local filter_possibles = function(commands_list, curr_command)
                    local exact_match = false
                    local possible = {}

                    for _, cmd in ipairs(commands_list) do
                    if cmd:sub(1, #curr_command) == curr_command then
                            table.insert(possible, cmd)

                            if cmd:len() == curr_command:len() then
                                exact_match = true
                                possible = {}
                                break
                            end
                         end
                    end

                    return exact_match, possible
                end

                if #args == 1 then
                    local exact, possible = filter_possibles(COMMANDS, args[1])

                    if not exact then
                        return possible
                    end
                end

                local action = args[1]
                table.remove(args, 1)

                -- TODO: Handle options with more than one token

                if action == "launch" then
                    local launchs = { "default" }

                    for _, launch in ipairs(ws:get_launch()) do
                        table.insert(launchs, launch.name)
                    end

                    local arg = args[1]

                    if arg then
                        local exact, possible = filter_possibles(launchs, arg)

                        if not exact then
                            return possible
                        else
                            return {}
                        end
                    end

                    return launchs
                elseif action == "tasks" then
                    local tasks = { "default" }

                    for _, task in ipairs(ws:get_tasks()) do
                        table.insert(tasks, task.name)
                    end

                    local arg = args[1]

                    if arg then
                        local exact, possible = filter_possibles(tasks, arg)

                        if not exact then
                            return possible
                        else
                            return {}
                        end
                    end

                    return tasks
                elseif action == "open" then
                    local OPEN_LIST = { "launch", "tasks", "variables", "config" }

                    local arg = args[1]

                    if arg then
                        local exact, possible = filter_possibles(OPEN_LIST, arg)

                        if not exact then
                            return possible
                        else
                            return {}
                        end
                    end

                    return OPEN_LIST
                end

                return {}
            end
        }
    )
end

return project
