//
//  BodyPoints.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import Vision

struct BodyPoints {
    let locationY: [CGFloat],
        locationX: [CGFloat]
    
    init(points: [VNRecognizedPoint]) {
        let y = points.compactMap { $0.location.y },
            x = points.compactMap { $0.location.x }
        
        self.locationY = y
        self.locationX = x
    }
}
