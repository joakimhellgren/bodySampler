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
    
    /// receive detected human + prediction notifications
    weak var delegate: CameraDelegate! { didSet { createFramePublisher() } }
    
    /// notifies delegate each time a new frame is captured
    private let captureSession = AVCaptureSession()
    
    /// combine publisher that forward frames as session creates them
    private var framePublisher: PassthroughSubject<Frame, Never>?
    private let captureQueue = DispatchQueue(label: "Capture Queue", qos: .userInitiated)
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput frame: Frame, from connection: AVCaptureConnection) {
        
        framePublisher?.send(frame)
    }
}

// MARK: - Methods
extension Camera {
    
    private func createFramePublisher() {
        
        guard let dataOutput = configureSession() else { return }
        
        /// create a new passthrough subject that publishes frames to subscribers
        let passthroughSubject = PassthroughSubject<Frame, Never>()
        
        /// ref to publisher
        framePublisher = passthroughSubject
        
        /// set the camera input as the video output's delegate
        dataOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        /// Create a generic publisher by type erasing the passthrough publisher.
        let genericFramePublisher = passthroughSubject.eraseToAnyPublisher()
        
        /// Send the publisher to the Camera delegate.
        delegate.camera(self, didCreate: genericFramePublisher)
    }
    
    func configureSession() -> AVCaptureVideoDataOutput? {
        
        if captureSession.isRunning { captureSession.stopRunning() }
        
        /// restart the session after this method returns
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
        
        do {
            try captureDevice.lockForConfiguration()
        } catch { return nil }
        
        defer { captureDevice.unlockForConfiguration() }
        
        let sortedRanges = captureDevice.activeFormat.videoSupportedFrameRateRanges.sorted {
            $0.maxFrameRate > $1.maxFrameRate
        }
        
        guard let range = sortedRanges.first else { return nil }
        guard framerate >= range.minFrameRate else { return nil }
        
        let duration = CMTime(value: 1, timescale: CMTimeScale(framerate))
        
        let inRange = framerate <= range.maxFrameRate
        captureDevice.activeVideoMinFrameDuration = inRange ? duration : range.minFrameDuration
        
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

