import SwiftUI
import HaishinKit
import AVFoundation

struct HKViewRepresentation: UIViewRepresentable {
    let stream: RTMPStream
    var isStreaming: Bool
    
    class Coordinator {
        let pipManager = PiPManager()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        
        let view = MTHKView(frame: .zero)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.attachStream(stream)
        
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.frame = container.bounds
        container.addSubview(view)
        
        DispatchQueue.main.async {
            context.coordinator.pipManager.setupPiP(with: view, container: container)
            context.coordinator.pipManager.setPiPActive(self.isStreaming)
        }
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.pipManager.setPiPActive(isStreaming)
    }
}
