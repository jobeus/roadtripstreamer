import SwiftUI
import MapboxMaps

struct MapOverlayView: UIViewRepresentable {
    let routeCoordinates: [CLLocationCoordinate2D]
    let currentLocation: CLLocationCoordinate2D?
    @ObservedObject var streamManager: StreamManager
    var isAppBackgrounded: Bool
    
    func makeUIView(context: Context) -> MapView {
        // Set access token before creating MapView
        MapboxOptions.accessToken = Secrets.mapboxPublicToken
        
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
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
        mapView.location.options.puckType = .puck2D(.makeDefault(showBearing: false))
        mapView.location.options.puckBearingEnabled = false
                
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
            label.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 8)
        ])
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Halt heavy Metal rendering while backgrounded to prevent freezing
        mapView.isHidden = isAppBackgrounded
        context.coordinator.isAppBackgrounded = isAppBackgrounded
        
        if let label = mapView.viewWithTag(999) as? UILabel {
            if let cityState = streamManager.currentCityState {
                label.text = " \(cityState) "
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }
        
        if streamManager.isZoomedToRoute, !routeCoordinates.isEmpty {
            if context.coordinator.lastRouteCountForZoom != routeCoordinates.count || context.coordinator.lastZoomedToRoute != streamManager.isZoomedToRoute {
                context.coordinator.lastRouteCountForZoom = routeCoordinates.count
                if routeCoordinates.count == 1 {
                    mapView.camera.ease(to: CameraOptions(center: routeCoordinates[0], zoom: 14), duration: 1.0)
                } else {
                    if let camera = try? mapView.mapboxMap.camera(for: routeCoordinates, camera: CameraOptions(), coordinatesPadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), maxZoom: nil, offset: nil) {
                        mapView.camera.ease(to: camera, duration: 1.0)
                    }
                }
            }
        } else if let loc = currentLocation {
            if context.coordinator.lastEasedLocation?.latitude != loc.latitude || context.coordinator.lastEasedLocation?.longitude != loc.longitude || context.coordinator.lastZoomedToRoute != streamManager.isZoomedToRoute {
                context.coordinator.lastEasedLocation = loc
                mapView.camera.ease(to: CameraOptions(center: loc, zoom: 14), duration: 1.0)
            }
        }
        
        context.coordinator.lastZoomedToRoute = streamManager.isZoomedToRoute
        
        // Update route polyline
        context.coordinator.updateRoute(routeCoordinates, on: mapView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(streamManager: streamManager)
    }
    
    class Coordinator {
        weak var mapView: MapView?
        let streamManager: StreamManager
        var isAppBackgrounded = false
        private var polylineAnnotationManager: PolylineAnnotationManager?
        private var timer: Timer?
        var latestRouteCoordinates: [CLLocationCoordinate2D] = []
        private var lastRenderedRouteCount = 0
        var lastEasedLocation: CLLocationCoordinate2D?
        var lastZoomedToRoute: Bool = false
        var lastRouteCountForZoom: Int = 0
        
        init(streamManager: StreamManager) {
            self.streamManager = streamManager
            self.timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard self.streamManager.isStreaming else { return }
                self.snapshotMap()
                if let mapView = self.mapView, !self.latestRouteCoordinates.isEmpty {
                    self.updateRoute(self.latestRouteCoordinates, on: mapView)
                }
            }
        }
        
        deinit {
            timer?.invalidate()
        }
        
        private func snapshotMap() {
            guard !isAppBackgrounded else { return }
            guard let mapView = mapView else { return }
            // Only capture if bounding box is valid and map is actively visible (prevents PiP unresponsiveness in background)
            guard mapView.bounds.size.width > 0, mapView.window != nil else { return }
            
            // Skip snapshotting while in background or PiP mode to avoid FigCaptureSourceRemote freeze
            guard UIApplication.shared.applicationState == .active else { return }
            
            // Use UIGraphicsImageRenderer for more efficient, modern rendering
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = false
            
            let renderer = UIGraphicsImageRenderer(size: mapView.bounds.size, format: format)
            let image = renderer.image { _ in
                mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: false)
            }
            
            if let cgImage = image.cgImage {
                streamManager.updateMapImage(cgImage)
            }
        }
        func updateRoute(_ coordinates: [CLLocationCoordinate2D], on mapView: MapView) {
            guard coordinates.count >= 2 else { return }
            guard coordinates.count != lastRenderedRouteCount else { return }
            lastRenderedRouteCount = coordinates.count
            self.latestRouteCoordinates = coordinates
            
            // Mapbox strongly recommends using AnnotationManagers for drawing lines instead of direct layer injection, 
            // as it automatically manages all style-loading races, GeoJSON sources, and renderer re-bindings natively.
            if polylineAnnotationManager == nil {
                polylineAnnotationManager = mapView.annotations.makePolylineAnnotationManager()
            }
            
            let lineString = LineString(coordinates)
            var polyline = PolylineAnnotation(lineString: lineString)
            
            // Bright neon cyan blue for maximum visibility against dark dark modes (alpha is included here instead of using lineOpacity)
            polyline.lineColor = StyleColor(UIColor(red: 0.1, green: 0.7, blue: 1.0, alpha: 0.9))
            polyline.lineWidth = 5.0
            polyline.lineJoin = .round
            
            polylineAnnotationManager?.annotations = [polyline]
        }
    }
}
