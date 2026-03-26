import Foundation
import CoreLocation
import Combine

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
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.delegate = self
    }
    
    func startTracking() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        isTracking = true
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
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
