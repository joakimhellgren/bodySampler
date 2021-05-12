//
//  AudioManager.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import AVFoundation

protocol AudioManagerDelegate: AnyObject {
    func audioManager(_ audioManager: AudioManager, didSet loopState: Bool)
}


class AudioManager {
    weak var delegate: AudioManagerDelegate?
    
    private var player: AVAudioPlayer?
    
    private var currentPrediction = PredictionLabel.other.rawValue
    private var confidence = 0.0
    private var isLooping = false
    
    private let engine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private let speedControl = AVAudioUnitVarispeed()
    private let pitchControl = AVAudioUnitTimePitch()
    private let reverb = AVAudioUnitReverb()
    
    func validatePrediction(_ prediction: Prediction) {
        
        if currentPrediction == prediction.label { return }
        configureAudioSession(configureAudioState(prediction))
    }
    
    private func configureAudioState(_ validPrediction: Prediction) -> Bool {
        
        currentPrediction = validPrediction.label
        confidence = validPrediction.confidence
        
        if currentPrediction == PredictionLabel.duck.rawValue {
            isLooping.toggle()
            delegate?.audioManager(self, didSet: self.isLooping)
        }
        
        
        return currentPrediction != PredictionLabel.other.rawValue || currentPrediction != PredictionLabel.none.rawValue
    }
    
    func observeMotions(poses: BodyPoints?) {
        
        guard let poses = poses,
              !poses.locationX.isEmpty,
              !poses.locationY.isEmpty else { return }
        
        pitchControl.rate = Float(poses.locationY[1]) * 2
        pitchControl.pitch = Float(poses.locationY[1]) * 1000
        reverb.wetDryMix = Float(poses.locationY[5]) * 80
    }
    
    private func playSound(_ shouldPlay: Bool) {
        
        if !shouldPlay { return }
        if audioPlayer.isPlaying { audioPlayer.stop() }
        
        if !audioPlayer.isPlaying && !isLooping { audioPlayer.play() }
    }
    
    
    func configureAudioSession(_ shouldPlay: Bool) {
        if !shouldPlay { return }
        if audioPlayer.isPlaying { audioPlayer.stop() }
        
        audioPlayer.volume = 0.8
        reverb.wetDryMix = 10.0

        let path = Bundle.main.path(forResource: isLooping ? "truck" : "kick", ofType: "wav")!
        let url = NSURL.fileURL(withPath: path)

        let file = try? AVAudioFile(forReading: url)
        
        let buffer = AVAudioPCMBuffer(pcmFormat: file!.processingFormat,
                                      frameCapacity: AVAudioFrameCount(file!.length))
        
        do { try file!.read(into: buffer!) }
        catch _ { }

        engine.attach(audioPlayer)
        engine.attach(pitchControl)
        engine.attach(speedControl)
        engine.attach(reverb)

        engine.connect(audioPlayer, to: speedControl, format: buffer?.format)
        engine.connect(speedControl, to: pitchControl, format: buffer?.format)
        engine.connect(pitchControl, to: reverb, format: buffer?.format)
        engine.connect(reverb, to: engine.mainMixerNode, format: buffer?.format)

        audioPlayer.scheduleBuffer(buffer!, at: nil, options: isLooping ? AVAudioPlayerNodeBufferOptions.loops : AVAudioPlayerNodeBufferOptions.interrupts , completionHandler: nil)

        engine.prepare()
        do {
            try engine.start()
        } catch _ {
        }
        
        audioPlayer.play()
    }
}
