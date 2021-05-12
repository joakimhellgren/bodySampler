//
//  DoubleActionClassifier+Singleton.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import CoreML

extension DoubleActionClassifier {
    
    static let shared: DoubleActionClassifier = {
        let config = MLModelConfiguration()
        
        guard let classifier = try? DoubleActionClassifier(configuration: config) else {
            fatalError("Classifier failed to initialize")
        }
        
        return classifier
    }()
    
}
