import QtQuick
import QtQuick.Shapes

Shape {
    id: siluetaEsquina

    property real ala: 16
    property real cuerpoRadio: 22
    property color relleno: "#0d1011"
    property color bordeColor: Qt.rgba(1, 1, 1, 0.12)
    property real bordeAncho: 1

    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    ShapePath {
        id: trazo
        fillColor: siluetaEsquina.relleno
        strokeWidth: siluetaEsquina.bordeAncho
        strokeColor: siluetaEsquina.bordeColor

        readonly property real w: siluetaEsquina.width
        readonly property real h: siluetaEsquina.height
        readonly property real a: Math.max(0, Math.min(siluetaEsquina.ala, h / 3, w / 6))
        readonly property real r: Math.max(0, Math.min(siluetaEsquina.cuerpoRadio, h / 2, w / 3))

        // Start at top-left corner of the screen
        startX: 0
        startY: 0

        // Flush top border of the screen to the right wing start
        PathLine {
            x: trazo.w - trazo.a
            y: 0
        }

        // Inverted concave wing connecting seamlessly to the top screen edge
        PathArc {
            x: trazo.w
            y: trazo.a
            radiusX: trazo.a
            radiusY: trazo.a
            direction: PathArc.Counterclockwise
        }

        // Right side vertical edge down to bottom-right corner
        PathLine {
            x: trazo.w
            y: Math.max(trazo.a, trazo.h - trazo.r)
        }

        // Bottom-right smooth rounded corner
        PathArc {
            x: Math.max(0, trazo.w - trazo.r)
            y: trazo.h
            radiusX: trazo.r
            radiusY: trazo.r
            direction: PathArc.Clockwise
        }

        // Bottom horizontal edge
        PathLine {
            x: trazo.r
            y: trazo.h
        }

        // Bottom-left smooth rounded corner
        PathArc {
            x: 0
            y: Math.max(0, trazo.h - trazo.r)
            radiusX: trazo.r
            radiusY: trazo.r
            direction: PathArc.Clockwise
        }

        // Left side vertical edge flush with the left screen border back to (0, 0)
        PathLine {
            x: 0
            y: 0
        }
    }
}
