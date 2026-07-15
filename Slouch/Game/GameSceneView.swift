import SceneKit
import SwiftUI

struct GameSceneView: UIViewRepresentable {
    let controller: GameSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = controller.scene
        view.pointOfView = controller.pointOfView
        view.delegate = controller
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = controller.scene
        uiView.pointOfView = controller.pointOfView
        uiView.delegate = controller
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Void) {
        uiView.isPlaying = false
        uiView.delegate = nil
        uiView.scene = nil
    }
}
