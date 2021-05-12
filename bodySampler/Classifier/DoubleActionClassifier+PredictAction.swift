//
//  DoubleActionClassifier+PredictAction.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import CoreML

extension DoubleActionClassifier {
    
    func predictActionFromWindow(_ window: MLMultiArray) -> Prediction {
        
        do {
            
            let output = try prediction(poses: window)
            let action = output.label
            let confidence = output.labelProbabilities[output.label]!
            
            return Prediction(label: action, confidence: confidence)
        } catch {
            
            fatalError("Classifier prediction error: \(error)")
        }
    }
}
