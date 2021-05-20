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
                        frame: DataFrame, points: BodyPoints)
    
    func processorChain(_ chain: ProcessorChain,
                        didPredict prediction: Prediction)
    
}

struct ProcessorChain {
    
    /// set to receive human poses and predictions
    weak var delegate: ProcessorChainDelegate?
    
    /// when property is set; begins to extract poses and predict actions.
    var upstreamFramePublisher: AnyPublisher<Frame, Never>! {
        didSet { buildProcessorChain() }
    }
    /// cancellation token for the active processing chain
    private var frameProcessorChain: AnyCancellable?
    
    private let humanBodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private let classifier = DoubleActionClassifier.shared
    
    /// how many frames we need to make a prediction
    private let predictionWindowSize: Int
    /// frequency of predictions
    private let windowStride = 15
    
    init() {
        predictionWindowSize = classifier.calculatePredictionWindowSize()
    }
}

extension ProcessorChain {
    
    private mutating func buildProcessorChain() {
        
        guard upstreamFramePublisher != nil else { return }
        
        /// transforms video frames from upstreamFramePublisher
        frameProcessorChain = upstreamFramePublisher
            /// convert frame(s) to CGImages, skip nil's with compactMap
            .compactMap(imageFromFrame)
            /// Detect any (if any) humans in frame
            .map(findPosesInFrame)
            /// if more than one person is found filter out the ones that take up a smaller area of the screen
            .map(isolateLargestPose)
            /// publish locations of human body parts as a multiarray to next subscriber
            .map(multiArrayFromPose)
            /// gather the window of multiarrays, starting with empty window
            .scan([MLMultiArray?](), gatherWindow)
            /// only pases when the window has enough data
            .filter(gateWindow)
            /// make an prediction from the accurate window
            .map(predictActionWithWindow)
            /// send prediction to delegate
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

        DispatchQueue.main.async {
            self.delegate?.processorChain(self, frame: DataFrame(frame: frame), points: BodyPoints(points: points))
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
            self.delegate?.processorChain(self, didPredict: prediction)
        }
    }
    
}
