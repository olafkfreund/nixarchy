        active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
        asynchronous: panelEntry.pluginId !== "nixarchy.menu"
