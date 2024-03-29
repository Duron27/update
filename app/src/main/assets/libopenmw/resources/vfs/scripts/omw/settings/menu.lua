local menu = require('openmw.menu')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local storage = require('openmw.storage')
local I = require('openmw.interfaces')

local common = require('scripts.omw.settings.common')
-- :reset on startup instead of :removeOnExit
common.getSection(false, common.groupSectionKey):reset()

local renderers = {}
local function registerRenderer(name, renderFunction)
    renderers[name] = renderFunction
end
require('scripts.omw.settings.renderers')(registerRenderer)

local interfaceL10n = core.l10n('Interface')

local pages = {}
local groups = {}
local pageOptions = {}

local interval = { template = I.MWUI.templates.interval }
local growingIntreval = {
    template = I.MWUI.templates.interval,
    external = {
        grow = 1,
    },
}
local spacer = {
    props = {
        size = util.vector2(0, 10),
    },
}
local bigSpacer = {
    props = {
        size = util.vector2(0, 50),
    },
}
local stretchingLine = {
    template = I.MWUI.templates.horizontalLine,
    external = {
        stretch = 1,
    },
}
local spacedLines = function(count)
    local content = {}
    table.insert(content, spacer)
    table.insert(content, stretchingLine)
    for _ = 2, count do
        table.insert(content, interval)
        table.insert(content, stretchingLine)
    end
    table.insert(content, spacer)
    return {
        type = ui.TYPE.Flex,
        external = {
            stretch = 1,
        },
        content = ui.content(content),
    }
end

local function interlaceSeparator(layouts, separator)
    local result = {}
    result[1] = layouts[1]
    for i = 2, #layouts do
        table.insert(result, separator)
        table.insert(result, layouts[i])
    end
    return result
end

local function setSettingValue(global, groupKey, settingKey, value)
    if global then
        core.sendGlobalEvent(common.setGlobalEvent, {
            groupKey = groupKey,
            settingKey = settingKey,
            value = value,
        })
    else
        storage.playerSection(groupKey):set(settingKey, value)
    end
end

local function renderSetting(group, setting, value, global)
    local renderFunction = renderers[setting.renderer]
    if not renderFunction then
        error(('Setting %s of %s has unknown renderer %s'):format(setting.key, group.key, setting.renderer))
    end
    local set = function(value)
        setSettingValue(global, group.key, setting.key, value)
    end
    local l10n = core.l10n(group.l10n)
    local titleLayout = {
        type = ui.TYPE.Flex,
        content = ui.content {
            {
                template = I.MWUI.templates.textHeader,
                props = {
                    text = l10n(setting.name),
                },
            },
        },
    }
    if setting.description then
        titleLayout.content:add(interval)
        titleLayout.content:add {
            template = I.MWUI.templates.textParagraph,
            props = {
                text = l10n(setting.description),
                size = util.vector2(300, 0),
            },
        }
    end
    local argument = common.getArgumentSection(global, group.key):get(setting.key)
    return {
        name = setting.key,
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
        },
        external = {
            stretch = 1,
        },
        content = ui.content {
            titleLayout,
            growingIntreval,
            renderFunction(value, set, argument),
        },
    }
end

local groupLayoutName = function(key, global)
    return ('%s%s'):format(global and 'global_' or 'player_', key)
end

local function renderGroup(group, global)
    local l10n = core.l10n(group.l10n)

    local valueSection = common.getSection(global, group.key)
    local settingLayouts = {}
    local sortedSettings = {}
    for _, setting in pairs(group.settings) do
        sortedSettings[setting.order] = setting
    end
    for _, setting in ipairs(sortedSettings) do
        table.insert(settingLayouts, renderSetting(group, setting, valueSection:get(setting.key), global))
    end
    local settingsContent = ui.content(interlaceSeparator(settingLayouts, spacedLines(1)))

    local resetButtonLayout = {
        template = I.MWUI.templates.box,
        events = {
            mouseClick = async:callback(function()
                for _, setting in pairs(group.settings) do
                    setSettingValue(global, group.key, setting.key, setting.default)
                end
            end),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = interfaceL10n('Reset')
                        },
                    },
                },
            },
        },
    }

    local titleLayout = {
        type = ui.TYPE.Flex,
        external = {
            stretch = 1,
        },
        content = ui.content {
            {
                template = I.MWUI.templates.textHeader,
                props = {
                    text = l10n(group.name),
                    textSize = 20,
                },
            }
        },
    }
    if group.description then
        titleLayout.content:add(interval)
        titleLayout.content:add {
            template = I.MWUI.templates.textParagraph,
            props = {
                text = l10n(group.description),
                size = util.vector2(300, 0),
            },
        }
    end

    return {
        name = groupLayoutName(group.key, global),
        type = ui.TYPE.Flex,
        external = {
            stretch = 1,
        },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                },
                external = {
                    stretch = 1,
                },
                content = ui.content {
                    titleLayout,
                    growingIntreval,
                    resetButtonLayout,
                },
            },
            spacedLines(2),
            {
                name = 'settings',
                type = ui.TYPE.Flex,
                content = settingsContent,
                external = {
                    stretch = 1,
                },
            },
        },
    }
end

local function pageGroupComparator(a, b)
    return a.order < b.order or (
        a.order == b.order and a.key < b.key
    )
end

local function generateSearchHints(page)
    local hints = {}
    local l10n = core.l10n(page.l10n)
    table.insert(hints, l10n(page.name))
    if page.description then
        table.insert(hints, l10n(page.description))
    end
    local pageGroups = groups[page.key]
    for _, pageGroup in pairs(pageGroups) do
        local group = common.getSection(pageGroup.global, common.groupSectionKey):get(pageGroup.key)
        local l10n = core.l10n(group.l10n)
        table.insert(hints, l10n(group.name))
        if group.description then
            table.insert(hints, l10n(group.description))
        end
        for _, setting in pairs(group.settings) do
            table.insert(hints, l10n(setting.name))
            if setting.description then
                table.insert(hints, l10n(setting.description))
            end
        end
    end
    return table.concat(hints, ' ')
end

local function renderPage(page)
    local l10n = core.l10n(page.l10n)
    local sortedGroups = {}
    for _, group in pairs(groups[page.key]) do
        table.insert(sortedGroups, group)
    end
    table.sort(sortedGroups, pageGroupComparator)
    local groupLayouts = {}
    for _, pageGroup in ipairs(sortedGroups) do
        local group = common.getSection(pageGroup.global, common.groupSectionKey):get(pageGroup.key)
        if not group then
            error(string.format('%s group "%s" was not found', pageGroup.global and 'Global' or 'Player', pageGroup.key))
        end
        table.insert(groupLayouts, renderGroup(group, pageGroup.global))
    end
    local groupsLayout = {
        name = 'groups',
        type = ui.TYPE.Flex,
        external = {
            stretch = 1,
        },
        content = ui.content(interlaceSeparator(groupLayouts, bigSpacer)),
    }
    local titleLayout = {
        type = ui.TYPE.Flex,
        external = {
            stretch = 1,
        },
        content = ui.content {
            {
                template = I.MWUI.templates.textHeader,
                props = {
                    text = l10n(page.name),
                    textSize = 22,
                },
            },
            spacedLines(3),
        },
    }
    if page.description then
        titleLayout.content:add {
            template = I.MWUI.templates.textParagraph,
            props = {
                text = l10n(page.description),
                size = util.vector2(300, 0),
            },
        }
    end
    local layout = {
        name = page.key,
        type = ui.TYPE.Flex,
        props = {
            position = util.vector2(10, 10),
        },
        content = ui.content {
            titleLayout,
            bigSpacer,
            groupsLayout,
            bigSpacer,
        },
    }
    return {
        name = l10n(page.name),
        element = ui.create(layout),
        searchHints = generateSearchHints(page),
    }
end

local function onSettingChanged(global)
    return async:callback(function(groupKey, settingKey)
        local group = common.getSection(global, common.groupSectionKey):get(groupKey)
        if not group or not pageOptions[group.page] then return end

        local value = common.getSection(global, group.key):get(settingKey)

        local element = pageOptions[group.page].element
        local groupsLayout = element.layout.content.groups
        local groupLayout = groupsLayout.content[groupLayoutName(group.key, global)]
        local settingsContent = groupLayout.content.settings.content
        settingsContent[settingKey] = renderSetting(group, group.settings[settingKey], value, global)
        element:update()
    end)
end

local function onGroupRegistered(global, key)
    local group = common.getSection(global, common.groupSectionKey):get(key)
    if not group then return end

    groups[group.page] = groups[group.page] or {}
    local pageGroup = {
        key = group.key,
        global = global,
        order = group.order,
    }

    if not groups[group.page][pageGroup.key] then
        common.getSection(global, group.key):subscribe(onSettingChanged(global))
        common.getArgumentSection(global, group.key):subscribe(async:callback(function(_, settingKey)
            if settingKey == nil then return end

            local group = common.getSection(global, common.groupSectionKey):get(group.key)
            if not group or not pageOptions[group.page] then return end

            local value = common.getSection(global, group.key):get(settingKey)

            local element = pageOptions[group.page].element
            local groupsLayout = element.layout.content.groups
            local groupLayout = groupsLayout.content[groupLayoutName(group.key, global)]
            local settingsContent = groupLayout.content.settings.content
            settingsContent[settingKey] = renderSetting(group, group.settings[settingKey], value, global)
            element:update()
        end))
    end

    groups[group.page][pageGroup.key] = pageGroup

    if not pages[group.page] then return end
    if pageOptions[group.page] then
        pageOptions[group.page].element:destroy()
    else
        pageOptions[group.page] = {}
    end
    local renderedOptions = renderPage(pages[group.page])
    for k, v in pairs(renderedOptions) do
        pageOptions[group.page][k] = v
    end
end

local function updateGroups(global)
    local groupSection = common.getSection(global, common.groupSectionKey)
    for groupKey in pairs(groupSection:asTable()) do
        onGroupRegistered(global, groupKey)
    end
    groupSection:subscribe(async:callback(function(_, key)
        if key then
            onGroupRegistered(global, key)
        else
            for groupKey in pairs(groupSection:asTable()) do
                onGroupRegistered(global, groupKey)
            end
        end
    end))
end

local updatePlayerGroups = function() updateGroups(false) end
updatePlayerGroups()

local updateGlobalGroups = function() updateGroups(true) end

local menuGroups = {}
local menuPages = {}

local function resetPlayerGroups()
    local playerGroupsSection = storage.playerSection(common.groupSectionKey)
    for pageKey, page in pairs(groups) do
        for groupKey, group in pairs(page) do
            if not menuGroups[groupKey] and not group.global then
                page[groupKey] = nil
                playerGroupsSection:set(groupKey, nil)
            end
        end
        if pageOptions[pageKey] then
            pageOptions[pageKey].element:destroy()
            if not menuPages[pageKey] then
                ui.removeSettingsPage(pageOptions[pageKey])
                pageOptions[pageKey] = nil
            else
                local renderedOptions = renderPage(pages[pageKey])
                for k, v in pairs(renderedOptions) do
                    pageOptions[pageKey][k] = v
                end
            end
        end
    end
end

local function registerPage(options)
    if type(options) ~= 'table' then
        error('Page options must be a table')
    end
    if type(options.key) ~= 'string' then
        error('Page must have a key')
    end
    if type(options.l10n) ~= 'string' then
        error('Page must have a localization context')
    end
    if type(options.name) ~= 'string' then
        error('Page must have a name')
    end
    if options.description ~= nil and type(options.description) ~= 'string' then
        error('Page description key must be a string')
    end
    local page = {
        key = options.key,
        l10n = options.l10n,
        name = options.name,
        description = options.description,
    }
    pages[page.key] = page
    groups[page.key] = groups[page.key] or {}
    if pageOptions[page.key] then
        pageOptions[page.key].element:destroy()
    end
    pageOptions[page.key] = pageOptions[page.key] or {}
    local renderedOptions = renderPage(page)
    for k, v in pairs(renderedOptions) do
        pageOptions[page.key][k] = v
    end
    ui.registerSettingsPage(pageOptions[page.key])
end

return {
    interfaceName = 'Settings',
    interface = {
        version = 1,
        registerPage = function(options)
            registerPage(options)
            menuPages[options.key] = true
        end,
        registerRenderer = registerRenderer,
        registerGroup = function(options)
            if not options.permanentStorage then
                error('Menu scripts are only allowed to register setting groups with permanentStorage = true')
            end
            common.registerGroup(options)
            menuGroups[options.key] = true
        end,
        updateRendererArgument = common.updateRendererArgument,
    },
    engineHandlers = {
        onStateChanged = function()
            if menu.getState() == menu.STATE.Running then
                updatePlayerGroups()
                updateGlobalGroups()
            elseif menu.getState() == menu.STATE.NoGame then
                resetPlayerGroups()
            end
        end,
    },
    eventHandlers = {
        [common.registerPageEvent] = function(options)
            registerPage(options)
        end,
    }
}
