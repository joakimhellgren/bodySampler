//
//  AppViewController.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import UIKit

class AppViewController: UIViewController {
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var loopStateLabel: UILabel!
    
    var audioManager: AudioManager!
    var camera: Camera!
    var processorChain: ProcessorChain!

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        
        audioManager = AudioManager()
        audioManager.delegate = self
        
        processorChain = ProcessorChain()
        processorChain.delegate = self
        
        camera = Camera()
        camera.delegate = self
        
    }
    
}

extension AppViewController: AudioManagerDelegate {
    func audioManager(_ audioManager: AudioManager, didSet loopState: Bool) {
        DispatchQueue.main.async {
            self.loopStateLabel.text = loopState ? "Looping: enabled" : "Looping: disabled"
        }
    }
    
    
}

extension AppViewController: CameraDelegate {
    func camera(_ camera: Camera, didCreate framePublisher: FramePublisher) {
        
        processorChain.upstreamFramePublisher = framePublisher
    }
    
    
}

extension AppViewController: ProcessorChainDelegate {
    func processorChain(_ chain: ProcessorChain, didDetect poses: [Human]?, in frame: DataFrame) {
        DispatchQueue.global(qos: .userInteractive).async {
            self.drawScreen(frame.image)
        }
    }
    
    func processorChain(_ chain: ProcessorChain, didPredict prediction: Prediction, for frames: Int) {
        
        DispatchQueue.main.async {
            self.predictionLabel.text = prediction.label
        }
        
        audioManager.validatePrediction(prediction)
    }
    
    func processorChain(_ chain: ProcessorChain, extractedPoints points: BodyPoints) {
        self.audioManager.observeMotions(poses: points)
    }
    
    
}

extension AppViewController {
    private func drawScreen(_ frame: CGImage) {
        
        let renderFormat = UIGraphicsImageRendererFormat()
        renderFormat.scale = 1.0
        
        let frameSize = CGSize(width: frame.width, height: frame.height)
        let renderer = UIGraphicsImageRenderer(size: frameSize, format: renderFormat)
        
        let frames = renderer.image { rendererContext in
            
            let cgContext = rendererContext.cgContext
            let inverse = cgContext.ctm.inverted()
            
            cgContext.concatenate(inverse)
            
            let imageRect = CGRect(origin: .zero, size: frameSize)
            cgContext.draw(frame, in: imageRect)
        }
        
        DispatchQueue.main.async {
            self.imageView.image = frames
        }
    }
}
