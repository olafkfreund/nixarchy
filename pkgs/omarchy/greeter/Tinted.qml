import QtQuick
import QtQuick.Effects
Item {
  property url src
  property color tint
  Image { id: shape; anchors.fill: parent; source: parent.src; fillMode: Image.PreserveAspectFit;
          visible: false; layer.enabled: true }
  Rectangle { id: fill; anchors.fill: parent; color: parent.tint; visible: false }
  MultiEffect { anchors.fill: parent; source: fill; maskEnabled: true; maskSource: shape }
}
