import CoreLocation
import Foundation
import Observation

/// Thin wrapper over CoreLocation. Beeline works fine without location — it
/// just can't route "from here" — so nothing blocks on authorization.
@MainActor
@Observable
public final class LocationProvider: NSObject {
    public private(set) var coordinate: CLLocationCoordinate2D?
    public private(set) var authorization: CLAuthorizationStatus
    /// Heading in degrees, for orienting the walking arrow.
    public private(set) var heading: Double?

    private let manager = CLLocationManager()

    public override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    public var isAuthorized: Bool {
        #if os(iOS)
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        #else
        authorization == .authorizedAlways
        #endif
    }

    public func request() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            start()
        }
    }

    public func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        #if os(iOS)
        manager.startUpdatingHeading()
        #endif
    }

    public func stop() {
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            if isAuthorized { start() }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = last.coordinate
        Task { @MainActor in coordinate = c }
    }

    #if os(iOS)
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in heading = value }
    }
    #endif

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure just means no fix yet; the UI already handles nil.
    }
}
