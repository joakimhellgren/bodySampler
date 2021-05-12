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
        
        if currentPrediction == PredictionLabel.duck.rawValue { isLooping.toggle() }
        delegate?.audioManager(self, didSet: self.isLooping)
        
        return currentPrediction == PredictionLabel.kick.rawValue
    }
    
    private func playAudio(_ shouldPlay: Bool) {
        
        if !shouldPlay { return }
        
        if let player = player, player.isPlaying {
            player.stop()
        }
        let urlString = Bundle.main.path(forResource: isLooping ? "truck" : "kick", ofType: "wav")
        
        do {
            try AVAudioSession.sharedInstance().setMode(.default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            
            guard let urlString = urlString else { return }
            
            player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: urlString))
            guard let player = player else { return }
            player.numberOfLoops = isLooping ? -1 : 0
            player.play()
        } catch let error {
            print("Error playing sound: \(error)")
        }
    }
    
    
    func observeMotions(poses: BodyPoints?) {
        
        guard let poses = poses,
              !poses.locationX.isEmpty,
              !poses.locationY.isEmpty else { return }
        
        pitchControl.rate = Float(poses.locationY[1]) * 2
        reverb.wetDryMix = Float(poses.locationY[5]) * 100
    }
    
    private func playSound(_ shouldPlay: Bool) {
        
        if !shouldPlay { return }
        if audioPlayer.isPlaying { audioPlayer.stop() }
        
        audioPlayer.play()
    }
    
    
    func configureAudioSession(_ shouldPlay: Bool) {
        if !shouldPlay { return }
        if audioPlayer.isPlaying { audioPlayer.stop() }
        
        audioPlayer.volume = 1.0
        reverb.wetDryMix = 50.0

        let path = Bundle.main.path(forResource: "kick", ofType: "wav")!
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
