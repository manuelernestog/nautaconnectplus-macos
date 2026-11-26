import AppKit

/// Draws the NautaConnect glyph from assets/icon.svg as a template image so it
/// adapts to light/dark menu bars automatically.
enum MenuBarIcon {
    static func image(size: CGFloat = 16) -> NSImage {
        // Transformed glyph bounds inside the 447x447 SVG viewBox (removes outer margins).
        let minX: CGFloat = 9.1014
        let minY: CGFloat = 89.9323
        let glyphWidth: CGFloat = 413.7536
        let glyphHeight: CGFloat = 276.5249

        let inset: CGFloat = 0.8
        let drawHeight = max(1, size - 2 * inset)
        let scale = drawHeight / glyphHeight
        let drawWidth = glyphWidth * scale
        let canvasWidth = ceil(drawWidth + 2 * inset)

        let image = NSImage(size: NSSize(width: canvasWidth, height: size), flipped: true) { rect in
            let offsetX = (rect.width - drawWidth) / 2
            let offsetY = (rect.height - drawHeight) / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                let gx = 1.0225 * x + 0.916245
                let gy = 1.0225 * y - 13.643906
                return NSPoint(
                    x: offsetX + (gx - minX) * scale,
                    y: offsetY + (gy - minY) * scale
                )
            }

            let path = NSBezierPath()
            path.move(to: p(143.376, 353.91))
            path.curve(to: p(48.972, 324.144), controlPoint1: p(138.2, 353.65), controlPoint2: p(73.374, 361.267))
            path.curve(to: p(122.522, 184.183), controlPoint1: p(8.005, 261.819), controlPoint2: p(119.007, 184.283))
            path.curve(to: p(116.239, 191.182), controlPoint1: p(126.634, 184.067), controlPoint2: p(118.882, 189.058))
            path.curve(to: p(111.135, 195.042), controlPoint1: p(115.723, 191.597), controlPoint2: p(111.544, 194.735))
            path.curve(to: p(103.63, 320.036), controlPoint1: p(64.837, 229.811), controlPoint2: p(33.523, 295.711))
            path.curve(to: p(107.679, 318.439), controlPoint1: p(106.722, 321.109), controlPoint2: p(108.886, 321.55))
            path.curve(to: p(114.7, 253.626), controlPoint1: p(101.363, 302.163), controlPoint2: p(102.692, 271.573))
            path.curve(to: p(245.403, 208.288), controlPoint1: p(146.936, 205.445), controlPoint2: p(222.092, 218.76))
            path.curve(to: p(255.203, 169.553), controlPoint1: p(248.319, 206.978), controlPoint2: p(261.678, 200.978))
            path.curve(to: p(196.473, 146.384), controlPoint1: p(250.703, 147.716), controlPoint2: p(225.852, 139.885))
            path.curve(to: p(155.487, 164.437), controlPoint1: p(167.884, 152.709), controlPoint2: p(158.03, 164.027))
            path.curve(to: p(154.325, 158.491), controlPoint1: p(153.988, 164.679), controlPoint2: p(154.298, 158.975))
            path.curve(to: p(154.277, 132.444), controlPoint1: p(155.633, 134.445), controlPoint2: p(153.771, 134.466))
            path.curve(to: p(188.578, 115.699), controlPoint1: p(154.906, 129.931), controlPoint2: p(173.145, 121.561))
            path.curve(to: p(278.551, 109.31), controlPoint1: p(207.693, 108.438), controlPoint2: p(247.881, 101.491))
            path.curve(to: p(302.453, 109.28), controlPoint1: p(289.884, 112.199), controlPoint2: p(290.024, 111.652))
            path.curve(to: p(391.494, 176.498), controlPoint1: p(344.284, 101.297), controlPoint2: p(412.654, 108.32))
            path.curve(to: p(361.421, 226.43), controlPoint1: p(386.324, 193.154), controlPoint2: p(370.08, 216.712))
            path.curve(to: p(310.52, 274.536), controlPoint1: p(330.075, 261.612), controlPoint2: p(326.713, 260.037))
            path.curve(to: p(302.625, 319.474), controlPoint1: p(306.702, 277.954), controlPoint2: p(300.412, 310.288))
            path.curve(to: p(332.739, 330.411), controlPoint1: p(307.884, 341.305), controlPoint2: p(331.565, 326.112))
            path.curve(to: p(330.219, 345.382), controlPoint1: p(333.067, 331.611), controlPoint2: p(330.455, 344.887))
            path.curve(to: p(308.533, 353.722), controlPoint1: p(328.251, 349.523), controlPoint2: p(309.84, 353.539))
            path.curve(to: p(239.303, 324.599), controlPoint1: p(267.392, 359.477), controlPoint2: p(252.607, 351.224))
            path.curve(to: p(230.516, 331.515), controlPoint1: p(237.655, 321.3), controlPoint2: p(234.94, 326.738))
            path.curve(to: p(143.376, 353.91), controlPoint1: p(193.266, 371.737), controlPoint2: p(151.665, 354.264))
            path.line(to: p(142.442, 351.621))
            path.curve(to: p(267.218, 304.059), controlPoint1: p(159.818, 352.501), controlPoint2: p(210.286, 340.091))
            path.curve(to: p(307.317, 275.313), controlPoint1: p(270.553, 301.949), controlPoint2: p(303.657, 280.997))
            path.curve(to: p(317.06, 240.402), controlPoint1: p(310.645, 270.145), controlPoint2: p(312.668, 253.621))
            path.curve(to: p(314.459, 239.452), controlPoint1: p(318.795, 235.18), controlPoint2: p(314.617, 239.296))
            path.curve(to: p(241.363, 292.259), controlPoint1: p(309.584, 244.255), controlPoint2: p(279.73, 270.838))
            path.curve(to: p(229.74, 297.428), controlPoint1: p(230.669, 298.23), controlPoint2: p(230.162, 298.354))
            path.curve(to: p(238.001, 268.383), controlPoint1: p(229.644, 297.216), controlPoint2: p(231.536, 292.583))
            path.curve(to: p(246.094, 235.499), controlPoint1: p(238.7, 265.765), controlPoint2: p(244.99, 242.219))
            path.curve(to: p(235.511, 234.735), controlPoint1: p(246.448, 233.342), controlPoint2: p(244.957, 234.453))
            path.curve(to: p(175.861, 299.444), controlPoint1: p(210.316, 235.487), controlPoint2: p(169.189, 248.728))
            path.curve(to: p(185.373, 316.397), controlPoint1: p(177.01, 308.185), controlPoint2: p(186.036, 315.402))
            path.curve(to: p(153.506, 323.572), controlPoint1: p(184.582, 317.583), controlPoint2: p(158.295, 323.224))
            path.curve(to: p(113.449, 322.818), controlPoint1: p(150.215, 323.811), controlPoint2: p(130.405, 326.122))
            path.curve(to: p(112.031, 326.734), controlPoint1: p(108.02, 321.76), controlPoint2: p(112.023, 326.718))
            path.curve(to: p(142.442, 351.621), controlPoint1: p(122.031, 345.268), controlPoint2: p(139.441, 350.686))
            path.line(to: p(143.376, 353.91))
            path.line(to: p(320.499, 233.498))
            path.curve(to: p(361.531, 158.501), controlPoint1: p(332.04, 220.354), controlPoint2: p(360.192, 193.1))
            path.curve(to: p(301.58, 117.587), controlPoint1: p(363.211, 115.112), controlPoint2: p(302.843, 116.015))
            path.curve(to: p(328.356, 185.489), controlPoint1: p(298.999, 120.8), controlPoint2: p(332.836, 127.464))
            path.curve(to: p(319.252, 232.569), controlPoint1: p(327.438, 197.38), controlPoint2: p(322.112, 222.67))
            path.curve(to: p(320.499, 233.498), controlPoint1: p(318.695, 234.496), controlPoint2: p(319.966, 233.468))
            path.line(to: p(143.376, 353.91))
            path.close()
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
