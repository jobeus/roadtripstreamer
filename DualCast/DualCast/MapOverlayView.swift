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
        
        // Enable location puck and heading rotation
        mapView.location.options.puckType = .puck2D(.makeDefault(showBearing: true))
        mapView.location.options.puckBearingEnabled = true
        mapView.location.options.puckBearing = .heading
        
        let label = UILabel()
        label.tag = 999
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 14)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(label)
        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 8)
        ])
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        if let label = mapView.viewWithTag(999) as? UILabel {
            if let cityState = streamManager.currentCityState {
                label.text = " \(cityState) "
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }
        
        if streamManager.isZoomedToRoute, !routeCoordinates.isEmpty {
            if routeCoordinates.count == 1 {
                mapView.camera.ease(to: CameraOptions(center: routeCoordinates[0], zoom: 14), duration: 1.0)
            } else {
                if let camera = try? mapView.mapboxMap.camera(for: routeCoordinates, camera: CameraOptions(), coordinatesPadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), maxZoom: nil, offset: nil) {
                    mapView.camera.ease(to: camera, duration: 1.0)
                }
            }
        } else if let loc = currentLocation {
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
            
            // Use 1.0 scale so the output image pixel size exactly matches the stream bounds (e.g. 256x192)
            UIGraphicsBeginImageContextWithOptions(mapView.bounds.size, false, 1.0)
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: false)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let cgImage = image?.cgImage {
                streamManager.updateMapImage(cgImage)
            }
        }
        func updateRoute(_ coordinates: [CLLocationCoordinate2D], on mapView: MapView) {
            guard coordinates.count >= 2 else { return }
            
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
                mapView.mapboxMap.updateGeoJSONSource(withId: "route-source", geoJSON: .geometry(.lineString(.init(coordinates))))
            }
        }
    }
}
