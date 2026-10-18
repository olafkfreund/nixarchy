  property int cardWidth: Math.min(Math.max(root.fitWidth, root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300))), Style.space(640), panel.width - Style.gapsOut * 2)
  // Width that fits the widest label of the open menu (#1339). It only grows
  // while the menu is open, so filtering does not make the card jump.
  property int fitWidth: 0
  onActiveMenuChanged: fitWidth = 0
  onDmenuActiveChanged: fitWidth = 0
  onLayoutSerialChanged: {
    var widest = 0
    for (var i = 0; i < displayModel.count; i++) {
      labelMetrics.text = displayModel.get(i).label || ""
      widest = Math.max(widest, labelMetrics.advanceWidth)
    }
    var chrome = root.rowReservedBorderLeft + Style.space(8 + 36 + 6 + 6 + 14 + 12) + card.contentLeftInset + card.contentRightInset
    fitWidth = Math.max(fitWidth, Math.ceil(widest + chrome))
  }
  TextMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
    font.weight: Font.Medium
  }
