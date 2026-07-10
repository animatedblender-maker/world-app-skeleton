import SceneKit
import SwiftUI
import UIKit
import simd

struct PhotorealGlobeSceneRepresentable: UIViewRepresentable {
    let entries: [CountryMapEntry]
    let selectedISO: String?
    let onSelectEntry: (CountryMapEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectEntry: onSelectEntry)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isPlaying = true
        view.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)

        context.coordinator.scnView = view
        context.coordinator.buildScene(entries: entries, selectedISO: selectedISO)
        view.pointOfView = context.coordinator.cameraNode
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateSelection(entries: entries, selectedISO: selectedISO)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        let onSelectEntry: (CountryMapEntry) -> Void
        weak var scnView: SCNView?

        let scene = SCNScene()
        let globeNode = SCNNode()
        let cameraNode = SCNNode()
        private var labelsNode = SCNNode()
        private var markerNode = SCNNode()
        private var markerRingNode = SCNNode()
        private var globeAssets: PhotorealGlobeBuilder.BuiltGlobe?
        private var cloudsNode: SCNNode?

        private var entries: [CountryMapEntry] = []
        private var lastPinchScale: CGFloat = 1
        private var isUserInteracting = false
        private var isPinching = false
        private var lastPanLocation: CGPoint?

        private var lastFrameTime: TimeInterval = 0
        private var cloudRotation: Float = 0

        private var yaw: Float = 0.55
        private var pitch: Float = -0.28
        private var yawVelocity: Float = 0
        private var pitchVelocity: Float = 0

        private var cameraDistance: Float = 3.25

        private let minCameraDistance: Float = 2.05
        private let maxCameraDistance: Float = 5.0
        private let minPitch: Float = -1.32
        private let maxPitch: Float = 1.32
        private let decelerationRate: Float = 3.2

        init(onSelectEntry: @escaping (CountryMapEntry) -> Void) {
            self.onSelectEntry = onSelectEntry
            super.init()
        }

        func buildScene(entries: [CountryMapEntry], selectedISO: String?) {
            guard let view = scnView else { return }
            self.entries = entries
            view.scene = scene

            configureSpaceBackground()

            let camera = SCNCamera()
            camera.fieldOfView = 40
            camera.zNear = 0.1
            camera.zFar = 100
            camera.wantsHDR = false
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)
            updateCameraPosition()

            scene.rootNode.addChildNode(globeNode)
            applyGlobeOrientation(animated: false)

            let assets = PhotorealGlobeBuilder.prepare()
            globeAssets = assets
            cloudsNode = assets.cloudsNode
            PhotorealGlobeBuilder.attach(to: globeNode, assets: assets)
            PhotorealGlobeBuilder.refreshTextures(on: assets)

            labelsNode = GlobeCountryLabels.buildNodes(from: entries, selectedISO: selectedISO)
            globeNode.addChildNode(labelsNode)

            configureMarkerNodes()
            globeNode.addChildNode(markerRingNode)
            globeNode.addChildNode(markerNode)

            updateMarker(selectedISO: selectedISO)
        }

        func updateSelection(entries: [CountryMapEntry], selectedISO: String?) {
            self.entries = entries
            GlobeCountryLabels.refreshSelection(on: labelsNode, entries: entries, selectedISO: selectedISO)
            updateMarker(selectedISO: selectedISO)
        }

        private func configureSpaceBackground() {
            scene.background.contents = StarfieldGenerator.image()
            scene.lightingEnvironment.contents = UIColor.black
            scene.lightingEnvironment.intensity = 0
        }

        private func configureMarkerNodes() {
            markerNode.geometry = SCNSphere(radius: 0.012)
            let markerMat = SCNMaterial()
            markerMat.diffuse.contents = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
            markerMat.emission.contents = UIColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 0.8)
            markerMat.lightingModel = .constant
            markerNode.geometry?.materials = [markerMat]
            markerNode.isHidden = true
            markerNode.categoryBitMask = PhotorealGlobeBuilder.decorCategory

            let ring = SCNTorus(ringRadius: 0.028, pipeRadius: 0.0022)
            let ringMat = SCNMaterial()
            ringMat.diffuse.contents = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 0.95)
            ringMat.emission.contents = UIColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 0.55)
            ringMat.lightingModel = .constant
            ring.firstMaterial = ringMat
            markerRingNode.geometry = ring
            markerRingNode.isHidden = true
            markerRingNode.categoryBitMask = PhotorealGlobeBuilder.decorCategory
        }

        private func updateMarker(selectedISO: String?) {
            if let selected = selectedISO?.uppercased(),
               let entry = entries.first(where: {
                   $0.iso3.uppercased() == selected || $0.iso2.uppercased() == selected
               }) {
                placeMarker(for: entry)
            } else {
                markerNode.isHidden = true
                markerRingNode.isHidden = true
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if lastFrameTime == 0 {
                lastFrameTime = time
                return
            }
            let dt = Float(min(time - lastFrameTime, 1.0 / 30.0))
            lastFrameTime = time
            guard dt > 0 else { return }

            cloudRotation += dt * 0.012
            cloudsNode?.eulerAngles = SCNVector3(0, cloudRotation, 0)

            GlobeCountryLabels.updateVisibility(
                container: labelsNode,
                globeWorldTransform: globeNode.presentation.worldTransform,
                cameraWorldPosition: cameraNode.presentation.worldPosition
            )

            guard !isUserInteracting else { return }
            applyMomentum(dt: dt)
        }

        private func applyMomentum(dt: Float) {
            guard abs(yawVelocity) > 0.00015 || abs(pitchVelocity) > 0.00015 else {
                yawVelocity = 0
                pitchVelocity = 0
                return
            }

            yaw += yawVelocity * dt
            pitch = clampPitch(pitch + pitchVelocity * dt)
            applyGlobeOrientation(animated: false)

            let decay = exp(-decelerationRate * dt)
            yawVelocity *= decay
            pitchVelocity *= decay
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = scnView else { return }

            switch gesture.state {
            case .began:
                isUserInteracting = true
                yawVelocity = 0
                pitchVelocity = 0
                lastPanLocation = gesture.location(in: view)
            case .changed:
                guard !isPinching else { return }
                let location = gesture.location(in: view)
                guard let last = lastPanLocation else {
                    lastPanLocation = location
                    return
                }

                let delta = CGPoint(x: location.x - last.x, y: location.y - last.y)
                lastPanLocation = location

                let sensitivity = Float.pi / Float(max(view.bounds.width, 320))
                // Natural grab-and-spin: finger pulls the globe in the same direction.
                yaw -= Float(delta.x) * sensitivity
                pitch = clampPitch(pitch + Float(delta.y) * sensitivity)
                applyGlobeOrientation(animated: false)
            case .ended, .cancelled:
                isUserInteracting = false
                lastPanLocation = nil
                guard !isPinching else { return }

                let velocity = gesture.velocity(in: view)
                let sensitivity = Float.pi / Float(max(view.bounds.width, 320))
                yawVelocity = -Float(velocity.x) * sensitivity * 0.0012
                pitchVelocity = Float(velocity.y) * sensitivity * 0.0012
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                isPinching = true
                isUserInteracting = true
                lastPinchScale = gesture.scale
                yawVelocity = 0
                pitchVelocity = 0
            case .changed:
                let delta = Float(gesture.scale / lastPinchScale)
                lastPinchScale = gesture.scale
                cameraDistance = clampZoom(cameraDistance / delta)
                updateCameraPosition()
            case .ended, .cancelled:
                isPinching = false
                isUserInteracting = false
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = scnView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .categoryBitMask: PhotorealGlobeBuilder.earthHitCategory,
            ])

            guard let hit = hits.first else { return }

            let geo = CountryMapData.geographicCoordinate(
                x: Float(hit.worldCoordinates.x),
                y: Float(hit.worldCoordinates.y),
                z: Float(hit.worldCoordinates.z)
            )
            guard let entry = CountryMapData.country(containing: geo.lng, lat: geo.lat, in: entries) else { return }

            yawVelocity = 0
            pitchVelocity = 0
            onSelectEntry(entry)
            focus(on: entry)
            placeMarker(for: entry)
        }

        private func focus(on entry: CountryMapEntry) {
            yaw = Float(-entry.lng * .pi / 180.0) - Float.pi / 2
            pitch = clampPitch(Float(-entry.lat * .pi / 180.0) * 0.82)
            applyGlobeOrientation(animated: true)
        }

        private func placeMarker(for entry: CountryMapEntry) {
            let coord = CountryMapData.sphereCoordinate(
                lat: entry.lat,
                lng: entry.lng,
                radius: CountryMapData.globeRadius + 0.018
            )
            let position = SCNVector3(coord.x, coord.y, coord.z)
            markerNode.position = position
            markerRingNode.position = position
            markerNode.isHidden = false
            markerRingNode.isHidden = false
        }

        private func applyGlobeOrientation(animated: Bool) {
            let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let pitchQuat = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            let orientation = simd_mul(pitchQuat, yawQuat)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.55 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            globeNode.simdOrientation = orientation
            SCNTransaction.commit()
        }

        private func updateCameraPosition() {
            cameraNode.position = SCNVector3(0, 0, cameraDistance)
            cameraNode.eulerAngles = SCNVector3Zero
        }

        private func clampPitch(_ value: Float) -> Float {
            max(minPitch, min(maxPitch, value))
        }

        private func clampZoom(_ value: Float) -> Float {
            max(minCameraDistance, min(maxCameraDistance, value))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer || other is UITapGestureRecognizer {
                return true
            }
            let isPanPinch =
                (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
                || (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
            return isPanPinch
        }


    }
}