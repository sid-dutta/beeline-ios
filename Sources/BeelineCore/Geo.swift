import Foundation

public enum Geo {
    static let earthRadius = 6_371_008.8

    public static func distanceMeters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lng2 - lng1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * asin(sqrt(a))
    }

    /// Initial bearing from point 1 to point 2, degrees clockwise from north.
    public static func bearing(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dl = (lng2 - lng1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed turn angle in (-180, 180]: positive is a right turn.
    public static func turnAngle(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }

    public static func compassName(_ bearing: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return names[Int((bearing + 22.5) / 45) % 8]
    }

    /// Ray-casting point-in-polygon on lat/lng — fine at campus scale.
    public static func contains(_ polygon: [Coordinate], lat: Double, lng: Double) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.lat > lat) != (pj.lat > lat),
               lng < (pj.lng - pi.lng) * (lat - pi.lat) / (pj.lat - pi.lat) + pi.lng {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
