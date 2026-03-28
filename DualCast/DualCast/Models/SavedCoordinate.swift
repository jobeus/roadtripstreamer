import Foundation
import CoreLocation

struct SavedCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ coord: CLLocationCoordinate2D) { latitude = coord.latitude; longitude = coord.longitude }
}
