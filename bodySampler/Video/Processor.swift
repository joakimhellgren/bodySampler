//
//  Processor.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import Vision
import Combine
import CoreImage

protocol ProcessorChainDelegate: AnyObject {
    func processorChain(_ chain: ProcessorChain,
                        didDetect poses: [Human]?,
                        in frame: DataFrame)
    
    func processorChain(_ chain: ProcessorChain,
                        didPredict prediction: Prediction,
                        for frames: Int)
    
    func processorChain(_ chain: ProcessorChain,
                        extractedPoints points: BodyPoints)
}

struct ProcessorChain {
    
    weak var delegate: ProcessorChainDelegate?
    
    var upstreamFramePublisher: AnyPublisher<Frame, Never>! {
        didSet { buildProcessorChain() }
    }
    
    private var frameProcessorChain: AnyCancellable?
    private let humanBodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private let classifier = DoubleActionClassifier.shared
    
    private let predictionWindowSize: Int
    private let windowStride = 15
    
    init() {
        predictionWindowSize = classifier.calculatePredictionWindowSize()
    }
}

extension ProcessorChain {
    
    private mutating func buildProcessorChain() {
        
        guard upstreamFramePublisher != nil else { return }
        
        frameProcessorChain = upstreamFramePublisher
            .compactMap(imageFromFrame)
            .map(findPosesInFrame)
            .map(isolateLargestPose)
            .map(multiArrayFromPose)
            .scan([MLMultiArray?](), gatherWindow)
            .filter(gateWindow)
            .map(predictActionWithWindow)
            .sink(receiveValue: sendPrediction)
    }
}

// MARK: - transform methods for Combine
extension ProcessorChain {
 
    private func imageFromFrame(_ buffer: Frame) -> CGImage? {
        
        guard let imageBuffer = buffer.imageBuffer else { return nil }
        
        let ciContext = CIContext(options: nil),
            ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return cgImage
    }
    
    private func findPosesInFrame(_ frame: CGImage) -> [Human]? {
        
        let visionRequestHandler = VNImageRequestHandler(cgImage: frame)
        
        do {
            try visionRequestHandler.perform([humanBodyPoseRequest])
        } catch {
            assertionFailure("vision request handler failed")
        }
        
        let poses = Human.fromObservation(humanBodyPoseRequest.results)
        var points: [VNRecognizedPoint] = []
        
        let _ = humanBodyPoseRequest.results?.compactMap { result in
            points = result.availableJointNames.compactMap { joint in
                guard joint != VNHumanBodyPoseObservation.JointName.root else {
                    return nil
                }
                
                guard let point = try? result.recognizedPoint(joint) else { return nil }
                return point
            }
        }
        self.delegate?.processorChain(self, extractedPoints: BodyPoints(points: points))
        
        DispatchQueue.main.async {
            self.delegate?.processorChain(self, didDetect: poses, in: DataFrame(frame: frame))
        }
        
        return poses
    }
    
    private func isolateLargestPose(_ poses: [Human]?) -> Human? {
        return poses?.max(by:) { pose1, pose2 in pose1.area < pose2.area }
    }
    
    private func multiArrayFromPose(_ item: Human?) -> MLMultiArray? {
        return item?.multiArray
    }
    
    private func gatherWindow(previousWindow: [MLMultiArray?],
                              multiArray: MLMultiArray?) -> [MLMultiArray?] {
        
        var currentwindow = previousWindow
        
        if previousWindow.count == predictionWindowSize {
            currentwindow.removeFirst(windowStride)
        }
        
        currentwindow.append(multiArray)
        return currentwindow
    }
    
    private func gateWindow(_ currentWindow: [MLMultiArray?]) -> Bool {
        return currentWindow.count == predictionWindowSize
    }
    
    private func predictActionWithWindow(_ currentWindow: [MLMultiArray?]) -> Prediction {
        
        var poseCount = 0
        
        /// fill nil elements with empty human array
        let filledWindow: [MLMultiArray] = currentWindow.map { multiArray in
            
            if let multiArray = multiArray {
                poseCount += 1
                return multiArray
            } else {
                guard let emptyMultiArray = try? MLMultiArray(shape: [1, 3, 18] as [NSNumber],
                                                              dataType: .double) else {
                    
                    fatalError("Creating a empty multi array should not fail")
                }
                
                guard let pointer = try? UnsafeMutableBufferPointer<Double>(emptyMultiArray) else {
                    fatalError("unable to initialize empty multiarray with zeroes")
                }
                
                pointer.initialize(repeating: 0.0)
                return emptyMultiArray
            }
        }
        /// use at least 60% real data for prediction
        let minimum = predictionWindowSize * 60 / 100
        
        guard poseCount >= minimum else {
            return Prediction(label: PredictionLabel.other.rawValue, confidence: 0.0)
        }
        
        /// merge array window of multiarray into one multiarray
        let mergedWindow = MLMultiArray(concatenating: filledWindow, axis: 0, dataType: .float)
        
        do {
            let output = try DoubleActionClassifier.shared.prediction(poses: mergedWindow)
            let action = output.label
            let confidence = output.labelProbabilities[output.label]!
            
            return checkConfidence(Prediction(label: action, confidence: confidence))
        } catch {
            fatalError("Making a prediction failed..")
        }
    }
    
    private func checkConfidence(_ prediction: Prediction) -> Prediction {
        let minimumConfidence = 0.6
        
        let lowConfidence = prediction.confidence < minimumConfidence
        return lowConfidence ? Prediction(label: PredictionLabel.other.rawValue, confidence: 0.0) : prediction
    }
    
    private func sendPrediction(_ prediction: Prediction) {
        
        DispatchQueue.main.async {
            self.delegate?.processorChain(self, didPredict: prediction, for: windowStride)
        }
    }
    
}
