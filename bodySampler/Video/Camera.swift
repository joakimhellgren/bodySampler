//
//  Camera.swift
//  bodySampler
//
//  Created by Joakim Hellgren on 2021-05-12.
//

import UIKit
import Combine
import AVFoundation

typealias Frame = CMSampleBuffer
typealias FramePublisher = AnyPublisher<Frame, Never>

protocol CameraDelegate: AnyObject {
    
    /// inform delegate when a new publisher is created
    func camera(_ camera: Camera, didCreate framePublisher: FramePublisher)
}

class Camera: NSObject {
    
    /// set property to receive human + prediction notifications
    weak var delegate: CameraDelegate! { didSet { createFramePublisher() } }
    
    /// video frame source
    private let captureSession = AVCaptureSession()
    
    /// initial combine publisher that forward frames as session creates them
    private var framePublisher: PassthroughSubject<Frame, Never>?
    
    /// thread used by capture session to publish frames
    private let captureQueue = DispatchQueue(label: "Capture Queue", qos: .userInitiated)
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput frame: Frame, from connection: AVCaptureConnection) {
        
        /// send frame(s) through publisher
        framePublisher?.send(frame)
    }
}

// MARK: - Methods
extension Camera {
    
    private func createFramePublisher() {
        /// configure / reconfigure session
        guard let dataOutput = configureSession() else { return }
        
        /// create a new passthrough subject that publishes frames to subscribers
        let passthroughSubject = PassthroughSubject<Frame, Never>()
        
        /// ref to publisher
        framePublisher = passthroughSubject
        
        /// set the camera input as the video output's delegate
        dataOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        /// Create a generic publisher by type erasing the passthrough publisher.
        let genericFramePublisher = passthroughSubject.eraseToAnyPublisher()
        
        /// Send the generic publisher to the Camera delegate.
        delegate.camera(self, didCreate: genericFramePublisher)
    }
    
    func configureSession() -> AVCaptureVideoDataOutput? {
        
        if captureSession.isRunning { captureSession.stopRunning() }
        
        /// start / restart the session after this method returns
        defer { if !captureSession.isRunning { captureSession.startRunning() } }
        
        captureSession.sessionPreset = .high
        captureSession.startRunning()
        captureSession.beginConfiguration()
        
        /// finalize configuration after method returns
        defer { captureSession.commitConfiguration() }
        
        let framerate = 30.0
        
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: AVCaptureDevice.Position.front) else {
            return nil
        }
        
        /// configrue the capture device to use the best available
        /// frame rate range around the target frame rate
        do {
            try captureDevice.lockForConfiguration()
        } catch { return nil }
        
        /// sort available frame rate ranges by descending
        let sortedRanges = captureDevice.activeFormat.videoSupportedFrameRateRanges.sorted {
            $0.maxFrameRate > $1.maxFrameRate
        }
        
        /// get highest maxFrameRate
        guard let range = sortedRanges.first else { return nil }
        
        /// check so target frarme rate is not below range
        guard framerate >= range.minFrameRate else { return nil }
        
        /// define duration based on target frame rate
        let duration = CMTime(value: 1, timescale: CMTimeScale(framerate))
        
        /// if target frame rate is within the range use it as the minimum
        let inRange = framerate <= range.maxFrameRate
        captureDevice.activeVideoMinFrameDuration = inRange ? duration : range.minFrameDuration
        captureDevice.activeVideoMaxFrameDuration = range.maxFrameDuration
        
        /// create input from camera
        guard let captureInput = try? AVCaptureDeviceInput(device: captureDevice) else { return nil }
        
        /// set sample buffer to view controller on capture queue
        let dataOutput = AVCaptureVideoDataOutput()
        
        let validPixelTypes = dataOutput.availableVideoPixelFormatTypes
        guard validPixelTypes.contains(kCVPixelFormatType_32BGRA) else { return nil }
        let pixelTypeKey = String(kCVPixelBufferPixelFormatTypeKey)
        
        dataOutput.videoSettings = [pixelTypeKey: kCVPixelFormatType_32BGRA]
        
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        
        guard captureSession.canAddInput(captureInput) && captureSession.canAddOutput(dataOutput) else {
            return nil
        }
        
        captureSession.addInput(captureInput)
        captureSession.addOutput(dataOutput)
        
        guard captureSession.connections.count == 1 else { return nil }
        guard let connection = captureSession.connections.first else { return nil }
        
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = true
        
        dataOutput.alwaysDiscardsLateVideoFrames = true
        
        return dataOutput
        
    }
}

