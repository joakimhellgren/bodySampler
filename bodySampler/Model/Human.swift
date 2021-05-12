//
//  Human.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import UIKit
import Vision

struct Human {
    private let joints: [Joint]
    let multiArray: MLMultiArray?
    let area: CGFloat
    
    // create Human for each human pose observation in the array
    static func fromObservation(_ observations: [VNHumanBodyPoseObservation]?) -> [Human]? {
        observations?.compactMap { observation in Human(observation) }
    }
    

    init?(_ observation: VNHumanBodyPoseObservation) {
        joints = observation.availableJointNames.compactMap { joint in
            guard joint != VNHumanBodyPoseObservation.JointName.root else { return nil }
            guard let point = try? observation.recognizedPoint(joint) else { return nil }
            
            return Joint(point)
        }
        
        guard !joints.isEmpty else { return nil }
        
        area = Human.estimateJointArea(joints)
        multiArray = try? observation.keypointsMultiArray()
    }
    
}

extension Human {
    
    struct Joint {
        private static let treshold: Float = 0.2
        private static let radius: CGFloat = 14.0
        
        let name: VNHumanBodyPoseObservation.JointName
        let location: CGPoint
        
        init?(_ point: VNRecognizedPoint) {
            guard point.confidence >= Human.Joint.treshold else { return nil }
            
            name = VNHumanBodyPoseObservation.JointName(rawValue: point.identifier)
            location = point.location
        }
    }
}

extension Human {
    // Returns estimate of collective area on detected joints.
    static func estimateJointArea(_ joints: [Joint]) -> CGFloat {
        let x = joints.map { $0.location.x }
        let y = joints.map { $0.location.y }
        
        guard let minX = x.min() else { return 0.0 }
        guard let maxX = x.max() else { return 0.0 }
        
        guard let minY = y.min() else { return 0.0 }
        guard let maxY = y.max() else { return 0.0 }
        
        let deltaX = maxX - minX
        let deltaY = maxY - minY
        
        // returns greater than or equal to 0.0
        return deltaX * deltaY
    }
}
