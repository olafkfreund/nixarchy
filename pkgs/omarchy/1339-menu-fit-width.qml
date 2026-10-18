  property int cardWidth: Math.min(Math.max(Math.min(root.fitWidth, Style.space(640)), root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300))), panel.width - Style.gapsOut * 2)
  // Width that fits the widest label of the open menu (#1339). The cap applies
  // to this fitted width only, so a caller's own width passes through. It only
  // grows, and starts again at each request, so filtering does not make the
  // card jump.
  property int fitWidth: 0
  onActiveMenuChanged: fitWidth = 0
  onRequestSerialChanged: fitWidth = 0
  onLayoutSerialChanged: {
    var widest = 0
    for (var i = 0; i < displayModel.count; i++) {
      labelMetrics.text = displayModel.get(i).label || ""
      widest = Math.max(widest, labelMetrics.advanceWidth)
    }
    var chrome = root.rowReservedBorderLeft + root.rowReservedBorderRight + Style.space(8 + 36 + 6 + 6 + 14 + 8) + card.contentLeftInset + card.contentRightInset
    fitWidth = Math.max(fitWidth, Math.ceil(widest + chrome))
  }
  TextMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
    font.weight: Font.Medium
  }
