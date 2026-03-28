import AVKit
import HaishinKit

class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?
    private var pipSource: AVPictureInPictureController.ContentSource?
    private weak var sourceView: MTHKView?
    private weak var sourceViewSuperview: UIView?
    
    func setupPiP(with sourceView: MTHKView, container: UIView) {
        self.sourceView = sourceView
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        let pipVC = AVPictureInPictureVideoCallViewController()
        pipVC.view.backgroundColor = .black
        self.pipVideoCallViewController = pipVC
        
        self.pipSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: container,
            contentViewController: pipVC
        )
    }
    
    func setPiPActive(_ active: Bool) {
        if active {
            if pipController == nil, let source = pipSource {
                let pip = AVPictureInPictureController(contentSource: source)
                pip.delegate = self
                pip.canStartPictureInPictureAutomaticallyFromInline = true
                self.pipController = pip
            }
        } else {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = false
            pipController = nil
        }
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let sourceView = sourceView, let pipVC = pipVideoCallViewController else { return }
        self.sourceViewSuperview = sourceView.superview
        
        sourceView.removeFromSuperview()
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        pipVC.view.addSubview(sourceView)
        NSLayoutConstraint.activate([
            sourceView.leadingAnchor.constraint(equalTo: pipVC.view.leadingAnchor),
            sourceView.trailingAnchor.constraint(equalTo: pipVC.view.trailingAnchor),
            sourceView.topAnchor.constraint(equalTo: pipVC.view.topAnchor),
            sourceView.bottomAnchor.constraint(equalTo: pipVC.view.bottomAnchor)
        ])
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let sourceView = sourceView, let superview = sourceViewSuperview else { return }
        
        sourceView.removeFromSuperview()
        sourceView.translatesAutoresizingMaskIntoConstraints = true
        sourceView.frame = superview.bounds
        sourceView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        superview.addSubview(sourceView)
    }
}
