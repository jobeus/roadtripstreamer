import SwiftUI
import MapboxMaps

struct MapOverlayView: UIViewRepresentable {
    let routeCoordinates: [CLLocationCoordinate2D]
    let currentLocation: CLLocationCoordinate2D?
    @ObservedObject var streamManager: StreamManager
    
    func makeUIView(context: Context) -> MapView {
        // Set access token before creating MapView
        MapboxOptions.accessToken = Secrets.mapboxPublicToken
        
        let mapView = MapView(frame: .zero)
        mapView.mapboxMap.setCamera(to: CameraOptions(
            center: currentLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            zoom: 14
        ))
        
        // Use dark style
        mapView.mapboxMap.loadStyle(.dark)
        
        // Hide ornaments for compact overlay
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden
        
        // Enable location puck
        mapView.location.options.puckType = .puck2D(.makeDefault(showBearing: true))
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Follow user location
        if let loc = currentLocation {
            mapView.camera.ease(to: CameraOptions(center: loc, zoom: 14), duration: 1.0)
        }
        
        // Update route polyline
        context.coordinator.updateRoute(routeCoordinates, on: mapView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(streamManager: streamManager)
    }
    
    class Coordinator {
        weak var mapView: MapView?
        let streamManager: StreamManager
        private var routeSourceAdded = false
        private var timer: Timer?
        
        init(streamManager: StreamManager) {
            self.streamManager = streamManager
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.snapshotMap()
            }
        }
        
        deinit {
            timer?.invalidate()
        }
        
        private func snapshotMap() {
            guard let mapView = mapView else { return }
            // Only capture if bounding box is valid
            guard mapView.bounds.size.width > 0 else { return }
            
            UIGraphicsBeginImageContextWithOptions(mapView.bounds.size, false, 0.0)
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: false)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let cgImage = image?.cgImage {
                streamManager.updateMapImage(cgImage)
            }
        }
        func updateRoute(_ coordinates: [CLLocationCoordinate2D], on mapView: MapView) {
            guard coordinates.count >= 2 else { return }
            
            var geoJSON = GeoJSONObject.geometry(.lineString(.init(coordinates)))
            
            if !routeSourceAdded {
                var source = GeoJSONSource(id: "route-source")
                source.data = .geometry(.lineString(.init(coordinates)))
                try? mapView.mapboxMap.addSource(source)
                
                var layer = LineLayer(id: "route-layer", source: "route-source")
                layer.lineColor = .constant(StyleColor(.systemBlue))
                layer.lineWidth = .constant(3.0)
                layer.lineOpacity = .constant(0.8)
                try? mapView.mapboxMap.addLayer(layer)
                
                routeSourceAdded = true
            } else {
                try? mapView.mapboxMap.updateGeoJSONSource(withId: "route-source", geoJSON: .geometry(.lineString(.init(coordinates))))
            }
        }
    }
}
