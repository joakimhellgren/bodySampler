//
//  Prediction.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

enum PredictionLabel: String {
    case other = "Other",
         none = "None",
         duck = "Duck",
         kick = "Kick"
}

struct Prediction {
    let label: String
    let confidence: Double!
    
    init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}
