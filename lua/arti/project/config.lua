local utils = require('arti.utils')

return {
    terminal = {
        position = "botright",
        size = 6
    },
    icons = {
        buffer = "",
        close = "",
        launch = "",
        task = "",
        workspace = "",
    },
    impl = {
        workspace = ".arti" .. utils.dirsep .. "project",
        variables = "variables.lua",
        tasks = "tasks.lua",
        launch = "launch.lua",
        config = "config.lua",
        state = "state.lua"
    }
}
