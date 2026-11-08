import SwiftUI

/// The logo of orangeflix.de: an iris of six blades cut to a disc, with two
/// leaves at the upper left. At rest the iris stands open and takes the ink
/// of the page; when it closes, the blades turn into one another and take
/// the orange of the brand, the leaves turn green, and the iris becomes an
/// orange.
///
/// The geometry is the geometry of the website and of the terminal version
/// (`internal/tui/iris.go` in the Go program): the same blade path, the same
/// disc, the same pivot of the blades and the same leaves. Here the mark is
/// drawn as vectors instead of a grid of characters.
struct IrisMark: View {
    /// How far the iris is closed: 0 is open, 1 is closed.
    var closed: Double
    /// The color of the blades.
    var blade: Color
    /// The color of the leaves.
    var leaf: Color

    var body: some View {
        ZStack {
            IrisBlades(closed: closed)
                .fill(blade)
                .clipShape(IrisDisc())
                .opacity(0.73 + 0.27 * closed)
            IrisLeaves(closed: closed)
                .fill(leaf)
                .opacity(0.56 + 0.44 * closed)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The state of the iris at one moment, ported from `irisStateAt` of the Go
/// program.
struct IrisState {
    /// The turn of the blades in degrees.
    var turn: Double
    /// How far the blades have taken the orange (0…1).
    var bladeMix: Double
    /// How far the leaves have taken the green (0…1).
    var leafMix: Double
    /// The turn of the leaves around the iris in degrees.
    var orbit: Double
    /// The scale of the leaves.
    var scale: Double

    /// The iris stands open.
    static let open = IrisState(turn: 0, bladeMix: 0, leafMix: 0, orbit: 0, scale: 1)

    /// The iris is closed and orange.
    static let shut = IrisState(turn: 38.15, bladeMix: 1, leafMix: 1, orbit: -4, scale: 0.99)

    /// The state between the two.
    init(closed: Double) {
        let amount = max(0, min(1, closed))
        self.turn = 38.15 * amount
        self.bladeMix = amount
        self.leafMix = amount
        self.orbit = -4 * amount
        self.scale = 1 - 0.01 * amount
    }

    init(turn: Double, bladeMix: Double, leafMix: Double, orbit: Double, scale: Double) {
        self.turn = turn
        self.bladeMix = bladeMix
        self.leafMix = leafMix
        self.orbit = orbit
        self.scale = scale
    }
}

/// The geometry of the logo in the units of the SVG of the website, mapped
/// into the unit square (0…1) of the view.
enum IrisGeometry {
    /// The view box of the SVG (220 + 1060).
    static let viewMin = 220.0
    static let viewSize = 1060.0

    /// The centre of the iris.
    static let center = point(811.15, 826.90)
    /// The radius of the disc the blades are cut to.
    static let discRadius = 440.0 / viewSize
    /// The point every blade turns around.
    static let bladePivot = point(811.15, 486.98)
    /// The point the leaves turn around.
    static let leafPivot = point(648.68, 550.46)
    /// The turn of the leaves around the iris in degrees.
    static let leafTurn = -9.0

    /// The path of one blade of the website.
    static let blade = bladePath()

    /// The two leaves of the website.
    static let leaves: [Path] = [leafPathOne(), leafPathTwo()]

    /// Maps a point of the SVG into the unit square.
    static func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x - viewMin) / viewSize, y: (y - viewMin) / viewSize)
    }

    /// Scales the unit square into a rectangle.
    static func unit(_ rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(scaleX: rect.width, y: rect.height)
    }

    /// Turns around a point.
    static func turn(around pivot: CGPoint, degrees: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }

    /// Scales around a point.
    static func scale(around pivot: CGPoint, factor: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .scaledBy(x: factor, y: factor)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }

    /// The path of one blade: a line to the point of the disc and an arc
    /// back to the start.
    private static func bladePath() -> Path {
        var path = Path()
        path.move(to: point(641.69, 271.17))
        path.addLine(to: point(1024.39, 758.37))
        path.addLine(to: point(1205.00, 307.96))
        // The arc of the website ("A 600 600 0 0 0 641.69 271.17"), drawn
        // from its centre, so the direction does not depend on the
        // convention of the platform.
        let from = point(1205.00, 307.96)
        let to = point(641.69, 271.17)
        let radius = 600.0 / viewSize
        let chord = hypot(to.x - from.x, to.y - from.y)
        let half = max(radius, chord / 2)
        let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let height = sqrt(max(0, half * half - chord * chord / 4))
        let sign: Double = 1
        let center = CGPoint(x: middle.x - sign * height * (to.y - from.y) / chord,
                             y: middle.y + sign * height * (to.x - from.x) / chord)
        let begin = atan2(from.y - center.y, from.x - center.x)
        var delta = atan2(to.y - center.y, to.x - center.x) - begin
        if delta > 0 { delta -= 2 * .pi }
        path.addArc(center: center, radius: half,
                    startAngle: Angle(radians: begin), endAngle: Angle(radians: begin + delta),
                    clockwise: false)
        path.closeSubpath()
        return path
    }

    /// The first leaf of the website.
    private static func leafPathOne() -> Path {
        var path = Path()
        path.move(to: point(458.71, 492.35))
        path.addCurve(to: point(459.04, 429.15),
                      control1: point(455.99, 471.63), control2: point(456.05, 450.41))
        path.addCurve(to: point(467.80, 390.58),
                      control1: point(460.90, 415.94), control2: point(463.84, 403.05))
        path.addCurve(to: point(258.35, 287.34),
                      control1: point(415.57, 332.83), control2: point(342.09, 294.09))
        path.addLine(to: point(248.55, 286.55))
        path.addCurve(to: point(388.65, 575.65),
                      control1: point(238.99, 405.25), control2: point(296.17, 513.91))
        path.addCurve(to: point(458.71, 492.35),
                      control1: point(407.87, 544.91), control2: point(431.32, 517.00))
        path.closeSubpath()
        return path
    }

    /// The second leaf of the website.
    private static func leafPathTwo() -> Path {
        var path = Path()
        path.move(to: point(497.34, 467.77))
        path.addCurve(to: point(652.81, 393.88),
                      control1: point(544.34, 434.09), control2: point(596.59, 409.27))
        path.addCurve(to: point(609.15, 239.46),
                      control1: point(654.43, 340.98), control2: point(640.39, 287.07))
        path.addCurve(to: point(609.15, 239.46),
                      control1: point(577.91, 191.85), control2: point(609.15, 239.46))
        path.addCurve(to: point(488.84, 474.01),
                      control1: point(527.71, 292.91), control2: point(485.08, 383.28))
        path.addCurve(to: point(497.34, 467.76),
                      control1: point(491.65, 471.90), control2: point(494.48, 469.82))
        path.closeSubpath()
        return path
    }
}

/// The six blades of the iris, each turned around its own pivot and around
/// the centre of the iris.
struct IrisBlades: Shape {
    var closed: Double

    func path(in rect: CGRect) -> Path {
        let state = IrisState(closed: closed)
        return Path { path in
            for group in 0..<6 {
                // The blade is turned around its own pivot, then the whole
                // blade is turned with the group around the centre.
                let turned = IrisGeometry.blade.applying(
                    IrisGeometry.turn(around: IrisGeometry.bladePivot, degrees: state.turn))
                let placed = turned.applying(
                    IrisGeometry.turn(around: IrisGeometry.center, degrees: Double(group) * 60))
                path.addPath(placed.applying(IrisGeometry.unit(rect)))
            }
        }
    }
}

/// The disc the blades are cut to.
struct IrisDisc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = IrisGeometry.discRadius
        let center = IrisGeometry.center
        return Path { path in
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
        .applying(IrisGeometry.unit(rect))
    }
}

/// The two leaves at the upper left of the iris.
struct IrisLeaves: Shape {
    var closed: Double

    func path(in rect: CGRect) -> Path {
        let state = IrisState(closed: closed)
        return Path { path in
            for leaf in IrisGeometry.leaves {
                // The leaves turn around their own point, grow a little and
                // travel around the iris.
                let turned = leaf.applying(
                    IrisGeometry.turn(around: IrisGeometry.leafPivot, degrees: IrisGeometry.leafTurn))
                let scaled = turned.applying(
                    IrisGeometry.scale(around: IrisGeometry.center, factor: state.scale))
                let orbited = scaled.applying(
                    IrisGeometry.turn(around: IrisGeometry.center, degrees: state.orbit))
                path.addPath(orbited.applying(IrisGeometry.unit(rect)))
            }
        }
    }
}

/// The open iris in the full colors of the brand: orange blades, green
/// leaves. The app icon and the mark at the upper left use it, instead of
/// the ink of the page at rest.
struct IrisColorMark: View {
    var blade: Color = Color(hex: "F19100")
    var leaf: Color = Color(hex: "009245")

    var body: some View {
        ZStack {
            IrisBlades(closed: 0)
                .fill(blade)
                .clipShape(IrisDisc())
            IrisLeaves(closed: 0)
                .fill(leaf)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The iris in the colors of the brand: the blades take the orange while it
/// closes, the leaves the green.
struct IrisBrandMark: View {
    /// How far the iris is closed (0…1).
    var closed: Double
    var size: CGFloat = 28

    var body: some View {
        IrisMark(
            closed: closed,
            blade: Color(hex: "F19100").mix(with: Palette.ink, amount: 1 - closed),
            leaf: Color(hex: "009245").mix(with: Palette.ink, amount: 1 - closed))
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.45), value: closed)
    }
}

extension Color {
    /// Mixes two colors; `amount` is the share of the second color.
    func mix(with other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(white: 0, alpha: 1)
        let b = NSColor(other).usingColorSpace(.sRGB) ?? NSColor(white: 0, alpha: 1)
        let t = max(0, min(1, amount))
        let red = a.redComponent * (1 - t) + b.redComponent * t
        let green = a.greenComponent * (1 - t) + b.greenComponent * t
        let blue = a.blueComponent * (1 - t) + b.blueComponent * t
        return Color(NSColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    }
}
