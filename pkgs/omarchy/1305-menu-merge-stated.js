      // An override copies only what it stated; a first definition is copied whole (#1305).
      var keys = (nextItems[entry.id] && entry.statedKeys) ? entry.statedKeys : Object.keys(entry)
      for (var k2 = 0; k2 < keys.length; k2++) merged[keys[k2]] = entry[keys[k2]]
      merged.kind = merged.action ? "action" : (merged.target ? "link" : "menu")
      delete merged.statedKeys
