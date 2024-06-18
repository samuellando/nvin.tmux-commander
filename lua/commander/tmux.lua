local log = require("commander.dev").log
local utils = require("harpoon.utils")

local M = {}
local tmux_windows = {}

local function create_terminal(name)
    log.trace("tmux: _create_terminal())")

    local window_id

    -- Create a new tmux window and store the window id
    local out, ret, _ = utils.get_os_command_output({
        "tmux",
        "new-window",
        "-P",
        "-d",
        "-n",
        name,
        "-F",
        "#{pane_id}",
    }, vim.loop.cwd())

    if ret == 0 then
        window_id = out[1]:sub(2)
    end

    if window_id == nil then
        log.error("tmux: _create_terminal(): window_id is nil")
        return nil
    end

    return window_id
end

-- Checks if the tmux window with the given window id exists
local function terminal_exists(window_id)
    log.trace("_terminal_exists(): Window:", window_id)

    local exists = false

    local window_list, _, _ = utils.get_os_command_output({
        "tmux",
        "list-windows",
        "-F",
        "#W"
    }, vim.loop.cwd())

    -- This has to be done this way because tmux has-session does not give
    -- updated results
    for _, line in pairs(window_list) do
        local window_info = line

        if string.find(window_info, string.sub(window_id, 2)) then
            exists = true
        end
    end

    return exists
end

local function get_window_id(window_id)
    log.trace("_get_window_id(): Window:", window_id)

    local window_list, _, _ = utils.get_os_command_output({
        "tmux",
        "list-windows",
        "-F",
        "#S:#W"
    }, vim.loop.cwd())

    -- This has to be done this way because tmux has-session does not give
    -- updated results
    for _, line in pairs(window_list) do
        local window_info = line

        if string.find(window_info, string.sub(window_id, 2)) then
            return window_info
        end
    end
    log.error("Window does not exist")
end

local function find_terminal(args)
    log.trace("tmux: _find_terminal(): Window:", args)

    if type(args) == "string" then
        -- assume args is a valid tmux target identifier
        -- if invalid, the error returned by tmux will be thrown
        return {
            window_id = get_window_id(args),
            pane = false,
        }
    end
end

function M.gotoTerminal(idx)
    log.trace("tmux: gotoTerminal(): Window:", idx)
    local window_handle = find_terminal(idx)

    local _, ret, stderr = utils.get_os_command_output({
        "tmux",
        window_handle.pane and "select-pane" or "select-window",
        "-t",
        window_handle.window_id,
    }, vim.loop.cwd())

    if ret ~= 0 then
        error("Failed to go to terminal." .. stderr[1])
    end
end

function M.sendCommand(idx, cmd, ...)
    log.trace("tmux: sendCommand(): Window:", idx)
    local window_handle = find_terminal(idx)

    log.error("ID", window_handle.window_id)

    if cmd then
        log.debug("sendCommand:", cmd)

        local _, ret, stderr = utils.get_os_command_output({
            "tmux",
            "send-keys",
            "-t",
            window_handle.window_id..".",
            string.format(cmd, ...),
        }, vim.loop.cwd())

        if ret ~= 0 then
            error("Failed to send command. " .. stderr[1])
        end
    end
end

function M.create_terminal(name)
    log.trace("create_terminal()", name)
    if not terminal_exists(name) then
        create_terminal(name)
        return true
    end
    return false
end

return M
