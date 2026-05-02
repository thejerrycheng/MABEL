//
//  TeleopImmersiveSpace.swift
//  MabelTeleop
//

import SwiftUI
import RealityKit
import simd
import UIKit

struct TeleopImmersiveSpace: View {

    @EnvironmentObject private var session: TeleopSession
    
    @State private var root = Entity()
    @State private var leftJoints:  [HandJoint: ModelEntity] = [:]
    @State private var rightJoints: [HandJoint: ModelEntity] = [:]
    @State private var headMarker: ModelEntity?
    
    // Virtual Joystick Visuals
    @State private var joystickOriginMarker: ModelEntity?
    @State private var isPinched: Bool = false
    @State private var pinchOrigin: SIMD3<Float>? = nil

    var body: some View {
        RealityView { content in
            content.add(root)
            buildSkeletons()
            buildHeadMarker()
            buildJoystickVisuals()
        } update: { _ in
            applyFrame(session.lastFrame)
        }
    }

    // MARK: - Build Visuals

    private func buildSkeletons() {
        for joint in HandJoint.allCases {
            let l = Self.makeJointEntity(color: .cyan)
            let r = Self.makeJointEntity(color: .magenta)
            l.isEnabled = false
            r.isEnabled = false
            root.addChild(l)
            root.addChild(r)
            leftJoints[joint] = l
            rightJoints[joint] = r
        }
    }

    private func buildHeadMarker() {
        let mesh = MeshResource.generateBox(size: 0.04)
        let material = SimpleMaterial(color: .yellow, roughness: 0.4, isMetallic: false)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.isEnabled = false
        root.addChild(marker)
        headMarker = marker
    }
    
    private func buildJoystickVisuals() {
        // A glowing yellow sphere to mark the center of the virtual joystick
        let mesh = MeshResource.generateSphere(radius: 0.015)
        var material = UnlitMaterial(color: .yellow)
        material.blending = .transparent(opacity: 0.6)
        
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.isEnabled = false
        root.addChild(marker)
        joystickOriginMarker = marker
    }

    // MARK: - Update Logic

    private func applyFrame(_ frame: TeleopFrame?) {
        guard let frame else { hideAll(); return }
        
        apply(hand: frame.leftHand,  into: leftJoints)
        apply(hand: frame.rightHand, into: rightJoints)
        applyHead(frame.head)
        
        if session.currentMode == .baseNavigation {
            applyVirtualJoystick(hand: frame.rightHand)
        } else {
            // Hide joystick visuals if we switch back to manipulation
            isPinched = false
            joystickOriginMarker?.isEnabled = false
        }
    }

    private func applyVirtualJoystick(hand: HandPose?) {
        guard let marker = joystickOriginMarker else { return }
        guard let hand, hand.isTracked else {
            marker.isEnabled = false
            isPinched = false
            return
        }
        
        // Find thumb and index joints
        let anchor = hand.anchorTransform.simd
        var thumbWorld: SIMD3<Float>?
        var indexWorld: SIMD3<Float>?
        
        for jointPose in hand.joints {
            if jointPose.joint == .thumbTip && jointPose.isTracked {
                let worldTx = anchor * jointPose.localTransform.simd
                thumbWorld = SIMD3<Float>(worldTx.columns.3.x, worldTx.columns.3.y, worldTx.columns.3.z)
            }
            if jointPose.joint == .indexFingerTip && jointPose.isTracked {
                let worldTx = anchor * jointPose.localTransform.simd
                indexWorld = SIMD3<Float>(worldTx.columns.3.x, worldTx.columns.3.y, worldTx.columns.3.z)
            }
        }
        
        guard let thumb = thumbWorld, let index = indexWorld else { return }
        
        let distance = simd_distance(thumb, index)
        let pinchThreshold: Float = 0.025 // 2.5 cm
        
        if distance < pinchThreshold {
            if !isPinched {
                // Just Pinched! Set origin.
                isPinched = true
                pinchOrigin = thumb
                
                // Move origin marker to this spot
                var transform = matrix_identity_float4x4
                transform.columns.3 = SIMD4<Float>(thumb.x, thumb.y, thumb.z, 1.0)
                marker.transform = Transform(matrix: transform)
                marker.isEnabled = true
            }
            
            // Optional: You could scale the sphere or change its color based on distance
            // from the origin here to give more dynamic feedback!
            
        } else {
            // Released pinch
            isPinched = false
            marker.isEnabled = false
        }
    }

    // ... (Keep your existing apply(hand:) and applyHead() functions down here) ...
    private func apply(hand: HandPose?, into map: [HandJoint: ModelEntity]) {
        // [Existing code stays the same]
        guard let hand, hand.isTracked else {
            map.values.forEach { $0.isEnabled = false }
            return
        }
        let anchor = hand.anchorTransform.simd
        var present: Set<HandJoint> = []
        for jointPose in hand.joints {
            guard jointPose.isTracked, let entity = map[jointPose.joint] else { continue }
            let world = anchor * jointPose.localTransform.simd
            entity.transform = Transform(matrix: world)
            entity.isEnabled = true
            present.insert(jointPose.joint)
        }
        for (joint, entity) in map where !present.contains(joint) {
            entity.isEnabled = false
        }
    }

    private func applyHead(_ head: HeadPose) {
        // [Existing code stays the same]
        guard let marker = headMarker else { return }
        var m = head.transform.simd
        let forward = SIMD4<Float>(0, 0, -0.3, 1)
        let p = m * forward
        m.columns.3 = p
        marker.transform = Transform(matrix: m)
        marker.isEnabled = head.trackingState == .normal
    }

    private func hideAll() {
        leftJoints.values.forEach  { $0.isEnabled = false }
        rightJoints.values.forEach { $0.isEnabled = false }
        headMarker?.isEnabled = false
        joystickOriginMarker?.isEnabled = false
    }

    private static func makeJointEntity(color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.008)
        let material = SimpleMaterial(color: color, roughness: 0.3, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
