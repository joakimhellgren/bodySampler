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
    @IBOutlet weak var currentSampleLabel: UILabel!
    
    var audioManager: AudioManager!
    var camera: Camera!
    var processorChain: ProcessorChain!

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        
        currentSampleLabel.text = "Selected sample: \(AudioState.currentSample.rawValue)"
        predictionLabel.text = "Latest action: "
        loopStateLabel.text = AudioState.isRepeatingSample ? "Looping: enabled" : "Looping: disabled"
        
        audioManager = AudioManager()
        audioManager.delegate = self
        
        processorChain = ProcessorChain()
        processorChain.delegate = self
        
        camera = Camera()
        camera.delegate = self
        
    }
}

// MARK: - AudioManagerDelegate

extension AppViewController: AudioManagerDelegate {
    func audioManager(_ audioManager: AudioManager, currentSample: String) {
        DispatchQueue.main.async {
            self.currentSampleLabel.text = "Selected sample: \(currentSample)"
        }
    }
    
    func audioManager(_ audioManager: AudioManager, loopState: Bool) {
        DispatchQueue.main.async {
            self.loopStateLabel.text = loopState ? "Looping: enabled" : "Looping: disabled"
        }
    }
}

// MARK: - CameraDelegate

extension AppViewController: CameraDelegate {
    func camera(_ camera: Camera, didCreate framePublisher: FramePublisher) {
        
        processorChain.upstreamFramePublisher = framePublisher
    }
}

// MARK: - ProcessorChainDelegate

extension AppViewController: ProcessorChainDelegate {
    
    func processorChain(_ chain: ProcessorChain, frame: DataFrame, points: BodyPoints) {
        drawScreen(frame.image)
        audioManager.observeMotions(poses: points)
    }
    
    func processorChain(_ chain: ProcessorChain, didPredict prediction: Prediction) {
        updateActionLabel(prediction.label)
        audioManager.validatePrediction(prediction)
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
        
        imageView.image = frames
    }
    
    private func updateActionLabel(_ label: String) {
        if label == PredictionLabel.none.rawValue || label == PredictionLabel.other.rawValue {
            return
        }
        
        DispatchQueue.main.async { self.predictionLabel.text = "Latest action: \(label)" }
    }
}
