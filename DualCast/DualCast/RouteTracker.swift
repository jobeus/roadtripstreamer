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
    @Published var currentCityState: String?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?
    private let minDistanceFilter: CLLocationDistance = 10 // meters between route points
    
    private var savedRouteURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("saved_route.json")
    }
    
    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = minDistanceFilter
        locationManager.delegate = self
        
        loadRoute()
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
    
    private func loadRoute() {
        guard let data = try? Data(contentsOf: savedRouteURL),
              let saved = try? JSONDecoder().decode([SavedCoordinate].self, from: data) else { return }
        self.routeCoordinates = saved.map { $0.coordinate }
    }
    
    private func saveRoute() {
        let codableCoords = routeCoordinates.map { SavedCoordinate($0) }
        if let data = try? JSONEncoder().encode(codableCoords) {
            try? data.write(to: savedRouteURL)
        }
    }
    
    @objc private func orientationChanged() {
        updateHeadingOrientation()
    }
    
    private func updateHeadingOrientation() {
        var interfaceOrientation: UIInterfaceOrientation = .unknown
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) as? UIWindowScene {
            interfaceOrientation = scene.interfaceOrientation
        }
        
        var targetOrientation: CLDeviceOrientation = .portrait
        if interfaceOrientation != .unknown {
            switch interfaceOrientation {
            case .portrait: targetOrientation = .portrait
            case .portraitUpsideDown: targetOrientation = .portraitUpsideDown
            case .landscapeLeft: targetOrientation = .landscapeRight // UI landscapeLeft means device rotated right
            case .landscapeRight: targetOrientation = .landscapeLeft  // UI landscapeRight means device rotated left
            @unknown default: break
            }
        } else {
            let orientation = UIDevice.current.orientation
            if orientation.isValidInterfaceOrientation {
                switch orientation {
                case .portrait: targetOrientation = .portrait
                case .portraitUpsideDown: targetOrientation = .portraitUpsideDown
                case .landscapeLeft: targetOrientation = .landscapeRight
                case .landscapeRight: targetOrientation = .landscapeLeft
                default: break
                }
            }
        }
        
        locationManager.headingOrientation = targetOrientation
    }
    
    func startTracking() {
        updateHeadingOrientation()
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
        saveRoute()
    }
    
    private func reverseGeocode(location: CLLocation) {
        // Geocode if we haven't yet, or if we moved more than 1000 meters
        if let last = lastGeocodedLocation, location.distance(from: last) < 1000 {
            return
        }
        
        lastGeocodedLocation = location
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first, error == nil else { return }
            
            Task { @MainActor in
                var components: [String] = []
                if let locality = placemark.locality { components.append(locality) }
                if let state = placemark.administrativeArea { components.append(state) }
                
                if !components.isEmpty {
                    self.currentCityState = components.joined(separator: ", ")
                }
            }
        }
    }
}

struct SavedCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ coord: CLLocationCoordinate2D) { latitude = coord.latitude; longitude = coord.longitude }
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
                self.saveRoute()
            }
            
            self.reverseGeocode(location: location)
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
