    var normalized = normalizeItem(id, entry)
    // The keys the file stated, so a later merge copies only those (#1305).
    normalized.statedKeys = Object.keys(entry).filter(function(k) { return k in normalized })
    out.push(normalized)
