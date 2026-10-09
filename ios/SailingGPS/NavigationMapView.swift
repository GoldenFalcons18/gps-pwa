import SwiftUI
import MapKit

/// Map projection and course marks are display-only; they never enter the recorded track.
struct NavigationMapView: UIViewRepresentable {
    let location: CLLocation?
    let heading: Double?
    let waypoints: [Waypoint]
    let track: [CLLocationCoordinate2D]
    @Binding var selected: UUID?
    @Binding var following: Bool
    let showAllRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.showsCompass = true
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 35.30, longitude: 139.48), latitudinalMeters: 3000, longitudinalMeters: 3000), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Defer until MapKit has a laid-out view so the physical scale can be measured.
        DispatchQueue.main.async { coordinator.render(map) }
    }

    final class Pin: MKPointAnnotation {
        var id: UUID?
        var kind = "waypoint"
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NavigationMapView
        var lastShowAll = 0
        private var rendering = false
        private var signature = ""
        init(_ parent: NavigationMapView) { self.parent = parent }

        func render(_ map: MKMapView) {
            guard !rendering else { return }
            rendering = true
            defer { rendering = false }
            let p = parent
            let key = "\(p.location?.timestamp.timeIntervalSince1970 ?? 0)|\(p.heading ?? -1)|\(p.selected?.uuidString ?? "")|\(p.waypoints.map { $0.id.uuidString }.joined())|\(p.track.count)"
            if key != signature {
                signature = key
                map.removeAnnotations(map.annotations)
                map.removeOverlays(map.overlays)
                for wp in p.waypoints {
                    let pin = Pin(); pin.id = wp.id; pin.title = wp.name; pin.coordinate = wp.coordinate
                    map.addAnnotation(pin)
                }
                if p.track.count > 1 { map.addOverlay(MKPolyline(coordinates: p.track, count: p.track.count)) }
                if let location = p.location {
                    let pin = Pin(); pin.kind = "boat"; pin.title = "現在地"; pin.coordinate = location.coordinate
                    map.addAnnotation(pin)
                    if let heading = p.heading {
                        var coordinates = [location.coordinate]
                        for distance in stride(from: 100, through: 500, by: 100) {
                            let q = CoordinateInput.destination(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, bearing: heading, meters: Double(distance))
                            let coordinate = CLLocationCoordinate2D(latitude: q.latitude, longitude: q.longitude)
                            coordinates.append(coordinate)
                            let dot = Pin(); dot.kind = "course"; dot.title = "\(distance) m"; dot.coordinate = coordinate
                            map.addAnnotation(dot)
                        }
                        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                        line.title = "course"
                        map.addOverlay(line)
                    }
                }
            }
            if lastShowAll != p.showAllRequest {
                lastShowAll = p.showAllRequest
                let pins = map.annotations.compactMap { $0 as? Pin }.filter { $0.kind != "course" }
                if !pins.isEmpty { map.showAnnotations(pins, animated: false) }
            } else if p.following, let point = p.location, map.bounds.width > 0, map.bounds.height > 0 {
                let camera = map.camera.copy() as! MKMapCamera
                if let heading = p.heading {
                    let center = CoordinateInput.destination(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude, bearing: heading, meters: 250)
                    camera.centerCoordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
                } else { camera.centerCoordinate = point.coordinate }
                camera.heading = p.heading ?? 0
                camera.pitch = 0
                map.setCamera(camera, animated: false)
                // UIKit does not expose screen PPI. Nominal iPhone/iPad points per inch
                // provide an approximate physical cm (iPhone 11: 326 PPI at 2x).
                let pointsPerCm = (UIDevice.current.userInterfaceIdiom == .pad ? 132.0 : 163.0) / 2.54
                let desiredMetersPerPoint = 200 / pointsPerCm
                let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
                let a = map.convert(CGPoint(x: mid.x - 25, y: mid.y), toCoordinateFrom: map)
                let b = map.convert(CGPoint(x: mid.x + 25, y: mid.y), toCoordinateFrom: map)
                let measured = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 50
                if measured.isFinite && measured > 0 {
                    let ratio = desiredMetersPerPoint / measured
                    if abs(ratio - 1) > 0.005 {
                        camera.altitude = max(1, camera.altitude * ratio)
                        map.setCamera(camera, animated: false)
                    }
                }
            }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            var interacting = false
            for child in mapView.subviews {
                for gesture in child.gestureRecognizers ?? [] {
                    if gesture.state == UIGestureRecognizer.State.began || gesture.state == UIGestureRecognizer.State.changed { interacting = true }
                }
            }
            if interacting && parent.following { DispatchQueue.main.async { self.parent.following = false } }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.title == "course" ? .cyan : .orange
                renderer.lineWidth = line.title == "course" ? 2 : 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            if pin.kind == "course" {
                let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
                view.backgroundColor = .cyan; view.layer.cornerRadius = 4; view.canShowCallout = true
                return view
            }
            let view = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: nil)
            view.markerTintColor = pin.kind == "boat" ? .red : pin.id == parent.selected ? .orange : .systemBlue
            view.glyphImage = UIImage(systemName: pin.kind == "boat" ? "location.north.fill" : "flag.fill")
            view.titleVisibility = .visible
            view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let id = (view.annotation as? Pin)?.id { parent.selected = id }
        }
    }
}
