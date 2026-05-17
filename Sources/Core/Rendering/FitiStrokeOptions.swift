// ABOUTME: fiti's central perfect-freehand options. Single tuning surface;
// ABOUTME: if a default feels wrong in practice, it changes here.

import PerfectFreehand

enum FitiStrokeOptions {
    static func make(width: Double, last: Bool) -> StrokeOptions {
        var opts = StrokeOptions()
        opts.size = width
        opts.thinning = 0.5
        opts.smoothing = 0.5
        opts.streamline = 0.5
        opts.simulatePressure = true
        opts.start = TaperOptions(taper: .none, cap: true)
        opts.end   = TaperOptions(taper: .none, cap: true)
        opts.last = last
        return opts
    }
}
