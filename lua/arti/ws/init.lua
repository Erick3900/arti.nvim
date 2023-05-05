local path = require('plenary.path')
local utils = require('arti.utils')
local dialogs = require('arti.ws.dialogs')
local workspace = require('arti.ws.workspace')
local default_config = require('arti.ws.config')

local arti_ws = {
    storage = path:new(utils.storage_path, "ws"),
    workspaces = {},
    config = nil,
    active = nil
}

function arti_ws.get_buffers_for_ws(ws, options)
    options = options or {}

    local buffers = {}

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            local filepath = vim.api.nvim_buf_get_name(buf)

            if vim.startswith(filepath, ws.rootpath) and vim.fn.filereadable(filepath) == 1 then
                if options.byid == true then
                    table.insert(buffers, buf)
                elseif options.relative == true then
                    table.insert(buffers, tostring(path:new(filepath):make_relative(ws.rootpath)))
                else
                    table.insert(buffers, filepath)
                end
            end
        end
    end

    return buffers
end

function arti_ws.load_recents()
    local recents_path = path:new(arti_ws.storage, arti_ws.config.impl.recents)
    local recents = {}

    if recents_path:is_file() then
        local recents_data = utils.do_luafile(recents_path)

        if type(recents_data) == "table" then
            recents = vim.tbl_filter(function(ws)
                return path:new(ws.rootpath, arti_ws.config.impl.workspace):is_dir()
            end, recents_data)
        end
    end

    return recents, recents_path
end

function arti_ws.save_workspaces()
    local recents, recents_path = arti_ws.load_recents()
    local new_recents = {}

    for _, recent in ipairs(recents) do
        for _, ws in ipairs(arti_ws.workspaces) do
            if recent.rootpath == ws.rootpath then
                recent.files = arti_ws.get_buffers_for_ws(ws, { relative = true })
                break
            end
        end

        table.insert(new_recents, recent)
    end

    local serpent = require('arti.serpent')

    utils.write_file(
        recents_path,
        serpent.pretty_dump(new_recents, {
            nocode = true
        })
    )
end

function arti_ws.close_workspace(ws)
    local buffers = arti_ws.get_buffers_for_ws(ws, { byid = true })

    vim.api.nvim_command("silent! :wall")

    for _, buf in ipairs(buffers) do
        vim.api.nvim_command("silent! :bd! " .. buf)
    end

    arti_ws.workspaces[ws.rootpath] = nil
end

function arti_ws.update_recents(ws)
    local recents, recents_path = arti_ws.load_recents()
    local c_path = ws.rootpath
    local idx = -1

    for i, proj in ipairs(recents) do
        if proj.rootpath == c_path then
            idx = i
            break
        end
    end

    if idx ~= -1 then
        table.remove(recents, idx)
    end

    table.insert(recents, 1, {
        rootpath = ws.rootpath,
        files = arti_ws.get_buffers_for_ws(ws, { relative = true })
    })

    local serpent = require('arti.serpent')

    utils.write_file(
        recents_path,
        serpent.pretty_dump(recents, {
            nocode = true
        })
    )
end

function arti_ws._edit_workspace(ws)
    local items = vim.tbl_map(function(filepath)
        return {
            icon = "buffer",
            value = filepath
        }
    end, arti_ws.get_buffers_for_ws(ws, { relative = true }))

    table.insert(items, { icon = "close", value = "CLOSE" })
    table.insert(items, { icon = nil, value = ".." })

    dialogs.select(
        items,
        {
            prompt_title = "Workspace '"..ws:get_name().."'",
            entry_maker = function(e)
                local entry = {
                    display = e.value,
                    ordinal = e.value
                }

                if e.icon then
                    entry.display = arti_ws.config.icons[e.icon].." "..entry.display
                end

                return entry
            end
        },
        function(entry)
            if entry.ordinal == ".." then
                arti_ws.show_workspaces()
            elseif entry.ordinal == "CLOSE" then
                arti_ws.close_workspace(ws)
            else
                vim.api.nvim_command(":e "..tostring(path:new(ws.rootpath, entry.ordinal)))
            end
        end
    )
end

function arti_ws.show_workspaces()
    local workspaces = vim.tbl_map(function(n)
        local ws = arti_ws.workspaces[n]

        return {
            ws = ws,
            files = arti_ws.get_buffers_for_ws(ws)
        }
    end, vim.tbl_keys(arti_ws.workspaces))

    dialogs.table(
        workspaces,
        {
            prompt_title = "Workspaces",
            columns = {
                { width = 40 },
                { remaining = true }
            },
            entry_maker = function(e)
                return {
                    ordinal = e.ws:get_name(),
                    value = e
                }
            end,
            displayer = function(entry)
                return {
                    { entry.value.ws:get_name(), "TelescopeResultsIdentifier" },
                    { string.format("%d buffers(s)", #entry.value.files), "TelescopeResultsNumber" }
                }
            end
        },
        function(entry)
            arti_ws._edit_workspace(entry.value.ws)
        end
    )
end

function arti_ws.recent_workspaces()
    local recents = arti_ws.load_recents()

    local gettext = function(e)
        return utils.get_filename(e.rootpath).." - "..e.rootpath
    end

    dialogs.table(
        recents,
        {
            prompt_title = "Workspaces",
            columns = {
                { width = 1 },
                { width = 20 },
                { remaining = true }
            },
            entry_maker = function(e)
                return {
                    ordinal = gettext(e),
                    value = e
                }
            end,
            displayer = function(e)
                return {
                    arti_ws.config.icons.workspace,
                    { utils.get_filename(e.value.rootpath), "TelescopeResultsNumber" },
                    { e.value.rootpath, "TelescopeResultsIdentifier" }
                }
            end
        },
        function(e)
            if arti_ws.active then
                arti_ws.close_workspace(arti_ws.active)
            end
            arti_ws.load(e.value.rootpath, e.value.files)
        end
    )
end

function arti_ws.get_templates()
    local templates = {}
    local scan_dir = require('plenary.scandir')

    local templates_path = path:new('/opt/arti/nvim/templates')

    if templates_path:is_dir() then
        local scan_opts = {
            only_dirs = true,
            depth = 1
        }

        for _, p in ipairs(scan_dir.scan_dir(tostring(templates_path), scan_opts)) do
            templates[utils.get_filename(p)] = path:new(p)
        end
    end

    return templates
end

function arti_ws.init_workspace(filepath)
    filepath = vim.F.if_nil(filepath, path:new(vim.fn.getcwd()))

    local ws_path = path:new(filepath, arti_ws.config.impl.workspace)

    if not ws_path:exists() then
        local templates = arti_ws.get_templates()

        if #vim.tbl_keys(templates) == 0 then
            vim.notify("No templates configured")
            return
        end

        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"

        local opts = {}

        pickers.new(opts, {
            prompt_title = "colors",
            finder = finders.new_table {
                results = vim.tbl_keys(templates)
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()

                    ws_path:mkdir({ parents = true })

                    templates[selection[1]]:copy({
                        recursive = true,
                        override = true,
                        destination = ws_path
                    })

                    arti_ws.load(filepath)
                end)

                return true
            end,
        }):find()
    else
        vim.notify("Workspace already initialized")
    end
end

function arti_ws.check(filepath)
    if not filepath:exists() then
        return
    end

    for _, p in ipairs(filepath:parents()) do
        if arti_ws.load(p) then
            break
        end
    end
end

function arti_ws.has_open_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            return true
        end
    end

    return false
end

function arti_ws.load(searchpath, files)
    searchpath = searchpath or vim.fn.getcwd()
    files = files or {}

    local ws_loc = path:new(searchpath, arti_ws.config.impl.workspace)

    if ws_loc:is_dir() then
        local ws_path = ws_loc:parent():parent()
        local ws = arti_ws.workspaces[tostring(ws_path)]

        if ws then
            ws:set_active()
        else
            ws = workspace(arti_ws.config, ws_path)
            arti_ws.workspaces[tostring(ws_path)] = ws
            ws:set_active()

            if vim.tbl_isempty(files) and not arti_ws.has_open_buffers() then
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

        arti_ws.update_recents(ws)
        arti_ws.active = ws
    else
        arti_ws.active = nil
    end

    return arti_ws.active ~= nil
end

function arti_ws.workspace_config_files()
    return vim.tbl_filter(function(n)
        return vim.endswith(n, ".lua")
    end, vim.tbl_values(arti_ws.config.impl))
end

function arti_ws.setup(config)
    arti_ws.config = vim.tbl_deep_extend(
        "force",
        default_config,
        config or {}
    )

    arti_ws.storage:mkdir({
        exists_ok = true,
        parents = true
    })

    local group_id = vim.api.nvim_create_augroup(
        "ArtiWs",
        { clear = true }
    )

    vim.api.nvim_create_autocmd(
        { "BufNewFile", "BufRead" },
        {
            group = group_id,
            pattern = vim.tbl_map(function(n)
                return "*" .. utils.dirsep .. arti_ws.config.impl.workspace .. utils.dirsep .. n
            end, arti_ws.workspace_config_files()),
            callback = function(arg)
                local lspconfig = require('lspconfig')

                local ws = arti_ws.active

                if not ws then
                    arti_ws.load()
                    ws = arti_ws.active
                end

                local ws_vars = ws:get_current_variables()
                local ws_globals = { 'vim' }

                local serpent = require('arti.serpent')

                local cache_path = path:new(ws:ws_root(), ".cache.lua")
                local preview = ""

                for var, val in pairs(ws_vars) do
                    preview = preview .. "_G." .. var .. " = " .. serpent.line(val) .. "\n"
                end

                utils.write_file(cache_path, preview)

                local ws_lib = vim.api.nvim_get_runtime_file("", true)
                table.insert(ws_lib, tostring(cache_path))

                lspconfig.lua_ls.setup({
                    settings = {
                        Lua = {
                            runtime = {
                                version = 'LuaJIT',
                            },
                            diagnostics = {
                                globals = ws_globals,
                            },
                            workspace = {
                                library = ws_lib,
                            }
                        }
                    }
                })
            end
        }
    )

    vim.api.nvim_create_autocmd(
        "BufEnter",
        {
            group = group_id,
            callback = function(arg)
                if #arg.file > 0 then
                    arti_ws.check(path:new(arg.file))
                end
            end
        }
    )

    vim.api.nvim_create_autocmd(
        "VimLeave",
        {
            group = group_id,
            callback = function()
                arti_ws.save_workspaces()
            end
        }
    )

    vim.api.nvim_create_user_command(
        "ArtiWs",
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

            if action == "init" then
                arti_ws.init_workspace()
            elseif action == "workspaces" then
                arti_ws.show_workspaces()
            elseif action == "recents" then
                arti_ws.recent_workspaces()
            elseif action == "load" then
                arti_ws.load()
            elseif action == "jobs" then
                local runner = require('arti.ws.runner')

                runner.show_jobs(arti_ws.config)
            elseif action == "config" then
                local ws = arti_ws.active

                if not ws then
                    return
                end

                ws:edit_config()
            elseif action == "launch" then
                local ws = arti_ws.active

                if not ws then
                    return
                end

                if arg then
                    if arg == "default" then
                        ws:launch_default()
                    else
                        local args_c = vim.deepcopy(opts.fargs)
                        table.remove(args_c, 1)
                        args_c = table.concat(args_c, " ")

                        local launchs = ws:get_launch_by_name()

                        if launchs[args_c] ~= nil then
                            ws:launch(launchs[args_c])
                        else
                            print("Invalid launch name provided")
                        end
                    end
                else
                    ws:show_launch()
                end
            elseif action == "tasks" then
                local ws = arti_ws.active

                if not ws then
                    return
                end

                if arg then
                    if arg == "default" then
                        ws:tasks_default()
                    else
                        local args_c = vim.deepcopy(opts.fargs)
                        table.remove(args_c, 1)
                        args_c = table.concat(args_c, " ")

                        local tasks = ws:get_tasks_by_name()

                        if tasks[args_c] ~= nil then
                            ws:run(tasks[args_c])
                        else
                            print("Invalid task name provided")
                        end
                    end
                else
                    ws:show_tasks()
                end
            elseif action == "open" then
                check_arg()

                local ws = arti_ws.active

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
                print("Unknown action '" .. action .. "'")
            end
        end,
        {
            nargs = "+",
            desc = "ArtiWs",
            complete = function(_, line)
                local ws = arti_ws.active
                local args = utils.cmdline_split(line)

                table.remove(args, 1)

                local COMMANDS = { "recents", "workspaces", "init", "load" }

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
                        if #curr_command > 0 and cmd:sub(1, #curr_command) == curr_command then
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

                    if not exact and #possible > 0 then
                        return possible
                    elseif exact then
                        if line:sub(line:len() - args[1]:len() + 1, line:len()) == args[1] then
                            return { args[1] .. " " }
                        end
                    end
                end

                print("::" .. table.concat(args, "_") .. "::" .. tostring(#args))

                local action = args[1]
                table.remove(args, 1)

                -- TODO: Handle options with more than one token

                if action == "launch" then
                    local launchs = { "default" }

                    for _, launch in ipairs(ws:get_launch()) do
                        table.insert(launchs, launch.name)
                    end

                    local arg = table.concat(args, " ")

                    if arg and arg:len() > 0 then
                        local exact, possible = filter_possibles(launchs, arg)

                        if not exact and #possible > 0 then
                            return possible
                        elseif exact then
                            return { arg .. " " }
                        end
                    end

                    return launchs
                elseif action == "tasks" then
                    local tasks = { "default" }

                    for _, task in ipairs(ws:get_tasks()) do
                        table.insert(tasks, task.name)
                    end

                    local arg = table.concat(args, " ")

                    if arg and arg:len() > 0 then
                        local exact, possible = filter_possibles(tasks, arg)

                        if not exact and #possible > 0 then
                            return possible
                        elseif exact then
                            return { arg .. " " }
                        end
                    end

                    return tasks
                elseif action == "open" then
                    local OPEN_LIST = { "launch", "tasks", "variables", "config" }

                    local arg = args[1]

                    if arg and arg:len() > 0 then
                        local exact, possible = filter_possibles(OPEN_LIST, arg)

                        if not exact and #possible > 0 then
                            return possible
                        elseif exact then
                            return { arg .. " " }
                        end
                    end

                    return OPEN_LIST
                end

                return {}
            end
        }
    )
end

return arti_ws
