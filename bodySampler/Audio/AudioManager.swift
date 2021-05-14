//
//  AudioManager.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import AVFoundation

protocol AudioManagerDelegate: AnyObject {
    /// send sample playback state to UI
    func audioManager(_ audioManager: AudioManager, loopState: Bool)
    /// send selected sample name to UI
    func audioManager(_ audioManager: AudioManager, currentSample: String)
}

enum AudioState: String, CaseIterable {
    /// our available samples
    case Kick = "Kick",
         Truck = "Truck",
         Amen = "Amen"
    
    /// method for selecting sample. Triggered by Duckimng/Squatting.
    mutating func nextSample() {
        let cases = type(of: self).allCases
        guard let pos = cases.firstIndex(of: self) else { return }
        self = cases[(pos + 1) % cases.count]
    }
    
    /// our currently selected sample which is the reference to our audio source.
    static var currentSample: AudioState = .Kick
    
    /// playback properties for sample
    static var isRepeatingSample: Bool {
        switch currentSample {
        case .Kick: return false
        case .Truck, .Amen: return true
        }
    }
}

class AudioManager {
    weak var delegate: AudioManagerDelegate?
    
    private var currentPrediction = PredictionLabel.other.rawValue
    
    private let engine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private let speedControl = AVAudioUnitVarispeed()
    private let pitchControl = AVAudioUnitTimePitch()
    private let reverb = AVAudioUnitReverb()

    /// observes body movement received from Vision framework
    func observeMotions(poses: BodyPoints?) {
        
        guard let poses = poses,
              !poses.locationX.isEmpty,
              !poses.locationY.isEmpty else { return }
        
        /// the poses array will always either 0 or all body parts (18)
        /// right hand will alwats be second item and the left hand will always be the sixth.
        pitchControl.rate = Float(poses.locationY[1]) * 2
        pitchControl.pitch = Float(poses.locationY[1]) * 1000
        reverb.wetDryMix = Float(poses.locationY[5]) * 50
    }
    
    func validatePrediction(_ prediction: Prediction) {
        
        /// we do not want to retrigger the audio manager methods after an action is performed with valid data
        /// we make sure that the incoming data is of other class before we let it pass on to the next function.
        if currentPrediction == prediction.label { return }
        
        /// takes a Prediction and performs different actions depending on the type of action it receives
        /// returns a bool that determines if the sound is supposed to play or just prepare audio for playback (i.e for looping)
        let configuration = preparePlayback(configureAudioState(prediction))
        
        playAudio(configuration)
    }
    
}

extension AudioManager {
    
    /// a placeholder helper method for filtering out unwanted action types.
    private func checkNegativeClasses(_ prediction: String) -> Bool {
        return prediction == PredictionLabel.other.rawValue
            || prediction == PredictionLabel.none.rawValue
            || prediction == PredictionLabel.duck.rawValue
    }
    
    private func configureAudioState(_ validPrediction: Prediction) -> Bool {
        
        /// store ref to validated prediction name
        currentPrediction = validPrediction.label
        
        /// if e received a state action like ducking/squatting we change the current selected sample
        /// and tell our view controller to update the UI
        if currentPrediction == PredictionLabel.duck.rawValue {
            
            if audioPlayer.isPlaying { audioPlayer.stop() }
            
            AudioState.currentSample.nextSample()
            
            delegate?.audioManager(self, loopState: AudioState.isRepeatingSample)
            delegate?.audioManager(self, currentSample: AudioState.currentSample.rawValue)
        }
        
        /// return true of action is negative or ducking action type
        return checkNegativeClasses(currentPrediction)
    }
    
    private func preparePlayback(_ isUnwantedType: Bool) -> AVAudioPCMBuffer? {
        
        /// discard configuration if type of prediction was only for state management
        if isUnwantedType { return nil }
        
        if audioPlayer.isPlaying && AudioState.isRepeatingSample {
            audioPlayer.stop()
            return nil
        } else {
            
            if audioPlayer.isPlaying { audioPlayer.stop() }
            
            audioPlayer.volume = 0.8
            reverb.wetDryMix = 5.0

            let path = Bundle.main.path(forResource: AudioState.currentSample.rawValue, ofType: "wav")
            let url = NSURL.fileURL(withPath: path!)

            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            
            do { try file.read(into: buffer) } catch let error {
                print("failed reading file in audio manager: \(error)")
            }

            engine.attach(audioPlayer)
            engine.attach(pitchControl)
            engine.attach(speedControl)
            engine.attach(reverb)

            engine.connect(audioPlayer, to: speedControl, format: buffer.format)
            engine.connect(speedControl, to: pitchControl, format: buffer.format)
            engine.connect(pitchControl, to: reverb, format: buffer.format)
            engine.connect(reverb, to: engine.mainMixerNode, format: buffer.format)
            
            return buffer
        }
    }
    
    private func playAudio(_ buffer: AVAudioPCMBuffer?) {
        
        guard let buffer = buffer else { return }
        
        /// configure buffer to match audio state (i.e will loop or interupt depending on state.
        audioPlayer.scheduleBuffer(buffer, at: nil, options: AudioState.isRepeatingSample ? AVAudioPlayerNodeBufferOptions.loops : AVAudioPlayerNodeBufferOptions.interrupts, completionHandler: nil)

        engine.prepare()
        
        do { try engine.start() } catch _ { }
        
        audioPlayer.play()
        
    }
}
