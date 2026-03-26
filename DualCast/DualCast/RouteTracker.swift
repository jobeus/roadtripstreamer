import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
class RouteTracker: NSObject, ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentSpeed: CLLocationSpeed = 0
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var isTracking = false
    
    private let locationManager = CLLocationManager()
    private let minDistanceFilter: CLLocationDistance = 10 // meters between route points
    
    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minDistanceFilter
        locationManager.delegate = self
        
        updateHeadingOrientation()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func orientationChanged() {
        updateHeadingOrientation()
    }
    
    private func updateHeadingOrientation() {
        let orientation = UIDevice.current.orientation
        if orientation.isValidInterfaceOrientation {
            switch orientation {
            case .portrait:
                locationManager.headingOrientation = .portrait
            case .portraitUpsideDown:
                locationManager.headingOrientation = .portraitUpsideDown
            case .landscapeLeft:
                locationManager.headingOrientation = .landscapeRight // UI landscapeLeft means device rotated right
            case .landscapeRight:
                locationManager.headingOrientation = .landscapeLeft  // UI landscapeRight means device rotated left
            default: break
            }
        }
    }
    
    func startTracking() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isTracking = true
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isTracking = false
    }
    
    func clearRoute() {
        routeCoordinates.removeAll()
    }
}

extension RouteTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.currentSpeed = max(0, location.speed)
            
            // Only add to route if accuracy is reasonable
            if location.horizontalAccuracy < 50 {
                self.routeCoordinates.append(location.coordinate)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Mapbox automatically reads heading from CoreLocation when we call startUpdatingHeading!
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] Error: \(error.localizedDescription)")
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.isTracking {
                    manager.startUpdatingLocation()
                }
            default:
                break
            }
        }
    }
}
