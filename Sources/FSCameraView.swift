//
//  FSCameraView.swift
//  Fusuma
//
//  Created by Yuta Akizuki on 2015/11/14.
//  Copyright © 2015年 ytakzk. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion
import Photos

@objc protocol FSCameraViewDelegate: class {
    func cameraShotFinished(_ image: UIImage)
}

final class FSCameraView: UIView, UIGestureRecognizerDelegate {

    @IBOutlet weak var previewViewContainer: UIView!
    @IBOutlet weak var shotButton: UIButton!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var flipButton: UIButton!
    @IBOutlet weak var fullAspectRatioConstraint: NSLayoutConstraint!
    var croppedAspectRatioConstraint: NSLayoutConstraint?
    
    weak var delegate: FSCameraViewDelegate? = nil
    
    fileprivate var session: AVCaptureSession?
    fileprivate var device: AVCaptureDevice?
    fileprivate var videoInput: AVCaptureDeviceInput?
    fileprivate var imageOutput: AVCaptureStillImageOutput?
    fileprivate var focusView: UIView?

    fileprivate var flashOffImage: UIImage?
    fileprivate var flashOnImage: UIImage?
    
    fileprivate var motionManager: CMMotionManager?
    fileprivate var currentDeviceOrientation: UIDeviceOrientation?
    
    
    static func instance() -> FSCameraView {
        
        return UINib(nibName: "FSCameraView", bundle: Bundle(for: self.classForCoder())).instantiate(withOwner: self, options: nil)[0] as! FSCameraView
    }
    
    func initialize() {
        
        if session != nil { return }
        
        self.backgroundColor = fusumaBackgroundColor
        
        let bundle = Bundle(for: self.classForCoder)
        
        flashOnImage = fusumaFlashOnImage != nil ? fusumaFlashOnImage : UIImage(named: "ic_flash_on", in: bundle, compatibleWith: nil)
        flashOffImage = fusumaFlashOffImage != nil ? fusumaFlashOffImage : UIImage(named: "ic_flash_off", in: bundle, compatibleWith: nil)
        let flipImage = fusumaFlipImage != nil ? fusumaFlipImage : UIImage(named: "ic_loop", in: bundle, compatibleWith: nil)
        let shotImage = fusumaShotImage != nil ? fusumaShotImage : UIImage(named: "ic_radio_button_checked", in: bundle, compatibleWith: nil)
        
        if fusumaTintIcons {
            
            flashButton.tintColor = fusumaBaseTintColor
            flipButton.tintColor  = fusumaBaseTintColor
            shotButton.tintColor  = fusumaBaseTintColor
            
            flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
            flipButton.setImage(flipImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
            shotButton.setImage(shotImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
        
        } else {
        
            flashButton.setImage(flashOffImage, for: UIControlState())
            flipButton.setImage(flipImage, for: UIControlState())
            shotButton.setImage(shotImage, for: UIControlState())
        }

        self.isHidden = false
        
        // AVCapture
        session = AVCaptureSession()
        
        guard let session = session else { return }
        
        for device in AVCaptureDevice.devices() {
            
            if let device = device as? AVCaptureDevice,
                device.position == AVCaptureDevicePosition.front {
                
                self.device = device
                
                flashButton.isHidden = !device.hasFlash
            }
        }
        
        do {
            
            videoInput = try AVCaptureDeviceInput(device: device)
            
            session.addInput(videoInput)
            
            imageOutput = AVCaptureStillImageOutput()
            
            session.addOutput(imageOutput)
            
            let videoLayer = AVCaptureVideoPreviewLayer(session: session)
            videoLayer?.frame = self.previewViewContainer.bounds
            videoLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            
            self.previewViewContainer.layer.addSublayer(videoLayer!)
            
            session.sessionPreset = AVCaptureSessionPresetPhoto
            
            session.startRunning()

            // Focus View
            self.focusView         = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
            let tapRecognizer      = UITapGestureRecognizer(target: self, action:#selector(FSCameraView.focus(_:)))
            tapRecognizer.delegate = self
            self.previewViewContainer.addGestureRecognizer(tapRecognizer)
            
        } catch {
            
        }
        
        flashConfiguration()
        
        self.startCamera()
        
        NotificationCenter.default.addObserver(self, selector: #selector(FSCameraView.willEnterForegroundNotification(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
    }
    
    func willEnterForegroundNotification(_ notification: Notification) {
        shotButton.isEnabled = true
        startCamera()
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
    }
    
    func startCamera() {
        
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
            
        case .authorized:
            
            session?.startRunning()
            
            motionManager = CMMotionManager()
            motionManager!.accelerometerUpdateInterval = 0.2
            motionManager!.startAccelerometerUpdates(to: OperationQueue()) { [unowned self] (data, _) in
                
                if let data = data {
                    
                    if abs(data.acceleration.y) < abs(data.acceleration.x) {
                        
                        self.currentDeviceOrientation = data.acceleration.x > 0 ? .landscapeRight : .landscapeLeft

                    } else {
                        
                        self.currentDeviceOrientation = data.acceleration.y > 0 ? .portraitUpsideDown : .portrait
                    }
                }
            }
            
        case .denied, .restricted:
            
            stopCamera()
            
        default:
            
            break
        }
    }
    
    func stopCamera() {
        
        session?.stopRunning()
        motionManager?.stopAccelerometerUpdates()
        currentDeviceOrientation = nil
    }

    @IBAction func shotButtonPressed(_ sender: UIButton) {
        shotButton.isEnabled = false
        
        guard let imageOutput = imageOutput else {
            
            return
        }
        
        DispatchQueue.global(qos: .default).async(execute: { () -> Void in

            let videoConnection = imageOutput.connection(withMediaType: AVMediaTypeVideo)

            let orientation = self.currentDeviceOrientation ?? UIDevice.current.orientation
            
            switch (orientation) {
            
            case .portrait:
            
                videoConnection?.videoOrientation = .portrait
            
            case .portraitUpsideDown:
            
                videoConnection?.videoOrientation = .portraitUpsideDown
            
            case .landscapeRight:
            
                videoConnection?.videoOrientation = .landscapeLeft
            
            case .landscapeLeft:
            
                videoConnection?.videoOrientation = .landscapeRight
            
            default:
            
                videoConnection?.videoOrientation = .portrait
            }

            imageOutput.captureStillImageAsynchronously(from: videoConnection) { (buffer, error) -> Void in
                
                self.stopCamera()
                
                guard let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer),
                    let image = UIImage(data: data),
                    let delegate = self.delegate else {
                        
                        return
                }
                
                // Image size
                let iw: CGFloat
                let ih: CGFloat
                
                switch (orientation) {
                    
                case .landscapeLeft, .landscapeRight:
                    
                    // Swap width and height if orientation is landscape
                    iw = image.size.height
                    ih = image.size.width
                    
                default:
                    
                    iw = image.size.width
                    ih = image.size.height
                    
                }
                
                // Frame size
                let sw = self.previewViewContainer.frame.width
                
                // The center coordinate along Y axis
                let rcy = ih * 0.5
                
                guard let imageRef = image.cgImage?.cropping(to: CGRect(x: rcy-iw*0.5, y: 0 , width: iw, height: iw)) else {
                    
                    return
                }
                
                DispatchQueue.main.async(execute: { () -> Void in
                    
                    var image = fusumaCropImage ? UIImage(cgImage: imageRef, scale: sw/iw, orientation: image.imageOrientation) : image
                    if self.device?.position == .front {
                        image = fusumaCropImage ? UIImage(cgImage: imageRef, scale: sw/iw, orientation: .leftMirrored) : image
                    }
                    
                    delegate.cameraShotFinished(image)
                    self.shotButton.isEnabled = true
                    
                    if fusumaSavesImage {
                        
                        self.saveImageToCameraRoll(image: image)
                    }
                    
                    self.session       = nil
                    self.device        = nil
                    self.imageOutput   = nil
                    self.motionManager = nil
                })
            }
        })
    }
    
    @IBAction func flipButtonPressed(_ sender: UIButton) {

        if !cameraIsAvailable { return }
        
        session?.stopRunning()
        
        do {

            session?.beginConfiguration()

            if let session = session {
                
                for input in session.inputs {
                    
                    session.removeInput(input as! AVCaptureInput)
                }

                let position = (videoInput?.device.position == AVCaptureDevicePosition.front) ? AVCaptureDevicePosition.back : AVCaptureDevicePosition.front

                for device in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {

                    if let device = device as? AVCaptureDevice , device.position == position {
                 
                        videoInput = try AVCaptureDeviceInput(device: device)
                        self.device = device
                        if !device.hasFlash {
                            flashButton.isHidden = true
                        } else {
                            flashButton.isHidden = false
                            switch device.flashMode {
                            case .off:
                                flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
                            case .on:
                                flashButton.setImage(flashOnImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
                            default:
                                break
                            }
                        }
                        session.addInput(videoInput)
                        
                    }
                }

            }
            
            session?.commitConfiguration()

            
        } catch {
            
        }
        
        session?.startRunning()
    }
    
    @IBAction func flashButtonPressed(_ sender: UIButton) {

        if !cameraIsAvailable { return }

        do {
            
            guard let device = device, device.hasFlash else { return }
            
            try device.lockForConfiguration()
            
            switch device.flashMode {
                
            case .off:
                
                device.flashMode = AVCaptureFlashMode.on
                flashButton.setImage(flashOnImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
                
            case .on:
                
                device.flashMode = AVCaptureFlashMode.off
                flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
                
            default:
                
                break
            }
            
            device.unlockForConfiguration()

        } catch _ {

            flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
            
            return
        }
 
    }
}

fileprivate extension FSCameraView {
    
    func saveImageToCameraRoll(image: UIImage) {
        
        PHPhotoLibrary.shared().performChanges({
            
            PHAssetChangeRequest.creationRequestForAsset(from: image)
            
        }, completionHandler: nil)
    }
    
    @objc func focus(_ recognizer: UITapGestureRecognizer) {
        
        let point = recognizer.location(in: self)
        let viewsize = self.bounds.size
        let newPoint = CGPoint(x: point.y/viewsize.height, y: 1.0-point.x/viewsize.width)
        
        guard let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) else {
            
            return
        }
        
        do {
            
            try device.lockForConfiguration()
            
        } catch _ {
            
            return
        }
        
        if device.isFocusModeSupported(AVCaptureFocusMode.autoFocus) == true {

            device.focusMode = AVCaptureFocusMode.autoFocus
            device.focusPointOfInterest = newPoint
        }

        if device.isExposureModeSupported(AVCaptureExposureMode.continuousAutoExposure) == true {
            
            device.exposureMode = AVCaptureExposureMode.continuousAutoExposure
            device.exposurePointOfInterest = newPoint
        }
        
        device.unlockForConfiguration()
        
        guard let focusView = self.focusView else { return }
        
        focusView.alpha = 0.0
        focusView.center = point
        focusView.backgroundColor = UIColor.clear
        focusView.layer.borderColor = fusumaBaseTintColor.cgColor
        focusView.layer.borderWidth = 1.0
        focusView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        addSubview(focusView)
        
        UIView.animate(withDuration: 0.8,
                       delay: 0.0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 3.0,
                       options: UIViewAnimationOptions.curveEaseIn,
                       animations: {
            
                focusView.alpha = 1.0
                focusView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        
        }, completion: {(finished) in
        
            focusView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            focusView.removeFromSuperview()
        })
    }
    
    func flashConfiguration() {
    
        do {
            
            if let device = device {
                
                guard device.hasFlash else { return }
                
                try device.lockForConfiguration()
                
                device.flashMode = AVCaptureFlashMode.off
                flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControlState())
                
                device.unlockForConfiguration()
                
            }
            
        } catch _ {
            
            return
        }
    }

    var cameraIsAvailable: Bool {

        let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)

        if status == AVAuthorizationStatus.authorized {

            return true
        }

        return false
    }
}
