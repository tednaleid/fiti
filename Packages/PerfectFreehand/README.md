# PerfectFreehand (Swift)

Swift port of [perfect-freehand](https://github.com/steveruizok/perfect-freehand) 1.2.3 (MIT, Steve Ruiz).

Given an array of input points and a `StrokeOptions`, returns a closed polygon's vertices representing a tapered, velocity-aware stroke outline — suitable for filling on any 2D canvas.

```swift
import PerfectFreehand

var options = StrokeOptions()
options.size = 8
options.simulatePressure = true

let polygon: [Point2D] = getStroke(points: inputPoints, options: options)
```

See upstream README for option semantics. This port mirrors the TS public API 1:1; fixture-parity tests assert byte equivalence within `abs ≤ 1e-9`.

## License

MIT — see `LICENSE` (preserved from upstream).
