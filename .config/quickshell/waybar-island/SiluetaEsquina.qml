import QtQuick
import QtQuick.Shapes

Shape {
    id: siluetaEsquina

    property real ala: 18
    property real cuerpoRadio: 24
    property color relleno: "#0d1011"
    property color bordeColor: "transparent"
    property real bordeAncho: 0

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
        readonly property real g: Math.max(0, Math.min(siluetaEsquina.ala, trazo.h / 3, trazo.w / 6))
        readonly property real r: Math.max(0, Math.min(siluetaEsquina.cuerpoRadio, trazo.h / 2, trazo.w / 3 - trazo.g))

        // Start at absolute top-left screen corner (0, 0)
        startX: 0
        startY: 0

        // 1. Flush down along left screen bezel to left wing tip
        PathLine {
            x: 0
            y: trazo.h
        }

        // 2. Inverted concave wing fusing into left screen bezel
        PathArc {
            x: trazo.g
            y: Math.max(0, trazo.h - trazo.g)
            radiusX: trazo.g
            radiusY: trazo.g
            direction: PathArc.Clockwise
        }

        // 3. Bottom edge to bottom-right corner start
        PathLine {
            x: Math.max(trazo.g, trazo.w - trazo.g - trazo.r)
            y: Math.max(0, trazo.h - trazo.g)
        }

        // 4. Smooth rounded bottom-right corner
        PathArc {
            x: Math.max(trazo.g, trazo.w - trazo.g)
            y: Math.max(0, trazo.h - trazo.g - trazo.r)
            radiusX: trazo.r
            radiusY: trazo.r
            direction: PathArc.Counterclockwise
        }

        // 5. Right vertical edge up to top wing start
        PathLine {
            x: Math.max(trazo.g, trazo.w - trazo.g)
            y: Math.min(trazo.h, trazo.g)
        }

        // 6. Inverted concave wing fusing into top screen bezel
        PathArc {
            x: trazo.w
            y: 0
            radiusX: trazo.g
            radiusY: trazo.g
            direction: PathArc.Clockwise
        }

        // 7. Flush top screen border back to (0, 0)
        PathLine {
            x: 0
            y: 0
        }
    }
}
