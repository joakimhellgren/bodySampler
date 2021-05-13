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
    

    func observeMotions(poses: BodyPoints?) {
        
        guard let poses = poses,
              !poses.locationX.isEmpty,
              !poses.locationY.isEmpty else { return }
        
        /// the poses array will always either 0 or all body parts (18)
        /// right hand will alwats be second item and the left hand will always be the sixth.
        pitchControl.rate = Float(poses.locationY[1]) * 2
        pitchControl.pitch = Float(poses.locationY[1]) * 1000
        reverb.wetDryMix = Float(poses.locationY[5]) * 80
    }
    
    func validatePrediction(_ prediction: Prediction) {
        
        /// since we do not want to retrigger the audio manager methods after an action is performed with valid data
        /// we make sure that the incoming data is of a negative class before we let it pass on to the next function.
        if currentPrediction == prediction.label { return }
        
        /// takes a prediction and performs conditional checks for configuring audio states (i.e play sound vs. configure audio looping)
        configureAudioSession(configureAudioState(prediction))
    }
    
}

extension AudioManager {
    private func configureAudioState(_ validPrediction: Prediction) -> Bool {
        
        /// store ref to validated prediction name
        currentPrediction = validPrediction.label
        /// store ref to validated confidence
        confidence = validPrediction.confidence
        
        if currentPrediction == PredictionLabel.duck.rawValue {
            
            isLooping.toggle()
        }
        delegate?.audioManager(self, didSet: self.isLooping)
        
        
        /// return true / false depending on state
        return currentPrediction == PredictionLabel.kick.rawValue
    }
    
    private func configureAudioSession(_ shouldPlay: Bool) {
        /// if audio state is != playState just discard.
        if !shouldPlay { return }
        
        if audioPlayer.isPlaying { audioPlayer.stop() }
        
        audioPlayer.volume = 0.8
        reverb.wetDryMix = 10.0

        let path = Bundle.main.path(forResource: isLooping ? "truck" : "kick", ofType: "wav")!
        let url = NSURL.fileURL(withPath: path)

        let file = try? AVAudioFile(forReading: url)
        
        let buffer = AVAudioPCMBuffer(pcmFormat: file!.processingFormat,
                                      frameCapacity: AVAudioFrameCount(file!.length))
        
        do { try file!.read(into: buffer!) } catch _ { }

        engine.attach(audioPlayer)
        engine.attach(pitchControl)
        engine.attach(speedControl)
        engine.attach(reverb)

        engine.connect(audioPlayer, to: speedControl, format: buffer?.format)
        engine.connect(speedControl, to: pitchControl, format: buffer?.format)
        engine.connect(pitchControl, to: reverb, format: buffer?.format)
        engine.connect(reverb, to: engine.mainMixerNode, format: buffer?.format)

        /// configure buffer to match audio state (i.e will loop or interupt depending on state.
        audioPlayer.scheduleBuffer(buffer!, at: nil, options: isLooping ? AVAudioPlayerNodeBufferOptions.loops : AVAudioPlayerNodeBufferOptions.interrupts , completionHandler: nil)

        engine.prepare()
        
        do { try engine.start() } catch _ { }
        
        audioPlayer.play()
    }
}
