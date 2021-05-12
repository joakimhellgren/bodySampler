//
//  DoubleActionClassifier+Framerate.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import CoreML

extension DoubleActionClassifier {
    
    func calculatePredictionWindowSize() -> Int {
        let modelDescription = model.modelDescription
        let modelInputs = modelDescription.inputDescriptionsByName
        assert(modelInputs.count == 1, "Modek should have exactly 1 input")
        
        guard let input = modelInputs.first?.value else {
            fatalError("Model must have atleast 1 input")
        }
        
        guard input.type == .multiArray else {
            fatalError("Model's input must be MLMultiArray")
        }
        
        guard let multiArrayConstraint = input.multiArrayConstraint else {
            fatalError("Multiarray input must have a constraint")
        }
        
        let dimensions = multiArrayConstraint.shape
        guard dimensions.count == 3 else {
            fatalError("Model's input multiarray must be 3 dimensions")
        }
        
        let windowSize = Int(truncating: dimensions.first!)
        
        return windowSize
        
    }
}
