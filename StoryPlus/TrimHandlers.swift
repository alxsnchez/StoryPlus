//
//  TrimHandlers.swift
//  StoryPlus
//
//  Created by Alex Sanchez on 22/03/2017.
//  Copyright © 2017 Alex Sanchez. All rights reserved.
//

import Foundation
import AVFoundation
import Photos
import SwiftSpinner
import UIKit
import Speech

extension TrimController {

    func handleAutoTrim(){
        type = "trim"
        if interstitial.isReady {
            self.interstitial.present(fromRootViewController: self)
        } else {
            detectAssetLenght()
        }
        
    }
    
    func handleTranscript(){
        thumbnails.removeAll()
        type = "transcript"
        videoURLs = []
        if interstitial.isReady {
            self.interstitial.present(fromRootViewController: self)
        } else {
            detectAssetLenght()
        }
        
    }
    
    func detectAssetLenght(){
        
        if type == "trim" {
            Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.exportFire), userInfo: nil, repeats: true)
        } else if type == "transcript" || type == "translate" {
            Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.createURLFire), userInfo: nil, repeats: true)
        }
        
        // Get video url and trim/parts duration from previous controller
        guard let url = videoURL else { return }
        guard let duration = trimDuration else { return }
        
        // Get asset from url and detect is total length
        let asset = AVAsset(url: url)
        self.assetDuration = Float(asset.duration.value) / Float(asset.duration.timescale)
        
        if let length = self.assetDuration {
            self.numberOfVideos = length / duration
            if (length.truncatingRemainder(dividingBy: duration)) > 0 {
                self.numberOfVideos += 1
            }
            // Detect if trim duration is longer than asset duration or not
            if duration > length {
                self.endTime = length
            } else {
                self.endTime = duration
            }
        }
        
        
        createComposition(asset: asset)
        
    }
    
    func createComposition(asset: AVAsset){
        // Create composition for video and audio mix and orientation fix
        let mixComposition = AVMutableComposition()
        
        // Add video to composition
        let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo,preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration),
                                                      of: asset.tracks(withMediaType: AVMediaTypeVideo)[0] ,
                                                      at: kCMTimeZero)
        } catch _ {
            print("Failed to load first track")
        }
        
        // Add audio to composition
        let audioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: 0)
        do {
            try audioTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration),
                                           of: asset.tracks(withMediaType: AVMediaTypeAudio)[0] ,
                                           at: kCMTimeZero)
        } catch _ {
            print("Failed to load audio track")
        }
        
        // Set preferred transform for video so it stays as original asset
        let assetVideoTrack = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
        compositionVideoTrack.preferredTransform = assetVideoTrack.preferredTransform
        
        
        trimVideo(video: mixComposition) { (url) in
            if url.absoluteString != "" {
                if self.type == "trim" {
                    self.exportMediaToLibrary(mediaURL: url)
                } else if self.type == "transcript" || self.type == "translate" {
                    self.createURLArray(mediaURL: url)
                } else {
                    return
                }
                
            }
            
        }
        
    }
    
    func trimVideo(video: AVMutableComposition, completion: @escaping (_ result: URL) -> Void) {
        let manager = FileManager.default
        if let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            
            var outputURL = documentDirectory.appendingPathComponent("videos")
            
            do {
                try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
                outputURL = outputURL.appendingPathComponent("\(UUID().uuidString).mp4")
            } catch let error {
                print(error)
            }
            
            _ = try? manager.removeItem(at: outputURL)
            
            if let exportSession = AVAssetExportSession(asset: video, presetName: AVAssetExportPresetHighestQuality) {
                exportSession.outputURL = outputURL
                exportSession.outputFileType = AVFileTypeQuickTimeMovie
                
                if let length = self.assetDuration {
                    if self.endTime > length {
                        self.endTime = length
                    }
                    
                    let startTime = CMTime(seconds: Double(self.startTime), preferredTimescale: 1000)
                    let endTime = CMTime(seconds: Double(self.endTime), preferredTimescale: 1000)
                    let timeRange = CMTimeRange(start: startTime, end: endTime)
                    exportSession.timeRange = timeRange
                    
                    exportSession.exportAsynchronously{
                        switch exportSession.status {
                        case .completed:
                            completion(outputURL)
                            print("Trimed video")
                        case .failed:
                            print("failed \(exportSession.error)")
                        case .cancelled:
                            print("cancelled \(exportSession.error)")
                            
                        default: break
                            
                        }
                    }
                }
                
            }
        }
        
    }
    
    func createURLArray(mediaURL: URL) {
        guard let url = videoURL else { return }
        let asset = AVAsset(url: url)
        
        thumbnailForVideoAtURL(url: mediaURL)
        videoURLs.append(mediaURL)
        print("Video urls count is: \(videoURLs.count)")
        
        if let length = self.assetDuration {
            if self.endTime < length {
                if let trim = self.trimDuration {
                    self.startTime = self.startTime + trim
                    self.endTime = self.endTime + trim
                    self.currentVideo += 1.0
                    self.progress = Double(self.currentVideo / self.numberOfVideos)
                    print("Progress is: \(self.progress)")
                    self.createComposition(asset: asset)
                }
            } else {
                self.progress = 1.0
            }
        }
        
    }
    
    func exportMediaToLibrary(mediaURL: URL){
        guard let url = videoURL else { return }
        let asset = AVAsset(url: url)
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: mediaURL)
        }) { saved, error in
            if saved {
                if let length = self.assetDuration {
                    if self.endTime < length {
                        if let trim = self.trimDuration {
                            self.startTime = self.startTime + trim
                            self.endTime = self.endTime + trim
                            self.currentVideo += 1.0
                            self.progress = Double(self.currentVideo / self.numberOfVideos)
                            print("Progress is: \(self.progress)")
                            self.createComposition(asset: asset)
                        }
                    } else {
                        self.progress = 1.0
                    }
                }
            }
        }
    }
    
    func trimOptions(){
        let optionsMenu = UIAlertController()
        //let optionsMenu = UIAlertController(title: NSLocalizedString("MenuTitle", comment: "This is the message that will be shown on top of the alert controller"), message: nil, preferredStyle: .actionSheet)
        let snapchat = UIAlertAction(title: "Custom (5 sec)", style: .default, handler: {(action) in
            self.trimDuration = 5
            self.handleAutoTrim()
        })
        
        let instagram = UIAlertAction(title: "Instagram (15 sec)", style: .default, handler: {(action) in
            self.trimDuration = 15
            self.handleAutoTrim()
        })
        
        let facebook = UIAlertAction(title: "Facebook (20 sec)", style: .default, handler: {(action) in
            self.trimDuration = 20
            self.handleAutoTrim()
        })
        
        let whatsapp = UIAlertAction(title: "WhatsApp (30 sec)", style: .default, handler: {(action) in
            self.trimDuration = 30
            self.handleAutoTrim()
        })
        
        let cancelOptions = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        optionsMenu.addAction(snapchat)
        optionsMenu.addAction(instagram)
        optionsMenu.addAction(facebook)
        optionsMenu.addAction(whatsapp)
        optionsMenu.addAction(cancelOptions)
        
        present(optionsMenu, animated: true, completion: nil)
    }
    
    func transcriptOptions(){
        let optionsMenu = UIAlertController()
        //let optionsMenu = UIAlertController(title: NSLocalizedString("MenuTitle", comment: "This is the message that will be shown on top of the alert controller"), message: nil, preferredStyle: .actionSheet)
        let snapchat = UIAlertAction(title: "Custom (5 sec)", style: .default, handler: {(action) in
            self.trimDuration = 5
            self.handleTranscript()
        })
        
        let instagram = UIAlertAction(title: "Instagram (15 sec)", style: .default, handler: {(action) in
            self.trimDuration = 15
            self.handleTranscript()
        })
        
        let facebook = UIAlertAction(title: "Facebook (20 sec)", style: .default, handler: {(action) in
            self.trimDuration = 20
            self.handleTranscript()
        })
        
        let whatsapp = UIAlertAction(title: "WhatsApp (30 sec)", style: .default, handler: {(action) in
            self.trimDuration = 30
            self.handleTranscript()
        })
        
        let cancelOptions = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        optionsMenu.addAction(snapchat)
        optionsMenu.addAction(instagram)
        optionsMenu.addAction(facebook)
        optionsMenu.addAction(whatsapp)
        optionsMenu.addAction(cancelOptions)
        
        present(optionsMenu, animated: true, completion: nil)
    }
    
    func exportFire(_ timer: Timer) {
        
        SwiftSpinner.show(progress: progress, title: "Exporting... \(Int(progress*100))%")
        if progress >= 1.0 {
            timer.invalidate()
            SwiftSpinner.show(duration: 2.0, title: "Exported to camera roll.", animated: false)
            self.numberOfVideos = 0.0
            self.currentVideo = 1.0
            self.endTime = 0.0
            self.startTime = 0.0
            self.progress = 0.0
        }
    }
    
    func createURLFire(_ timer: Timer) {
        
        //guard let duration = trimDuration else { return }
        SwiftSpinner.show(progress: progress, title: "Trimming... \(Int(progress*100))%")
        if progress >= 1.0 {
            timer.invalidate()
            SwiftSpinner.hide()
            self.numberOfVideos = 0.0
            self.currentVideo = 1.0
            self.endTime = 0.0
            self.startTime = 0.0
            self.progress = 0.0
            showTranscriptController()
            //recognizeFile()
            //Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.listenForEnd), userInfo: nil, repeats: true)
        }
    }
    
    func listenForEnd( _ timer: Timer) {
        SwiftSpinner.show(progress: progress, title: "Transcribing... \(Int(progress*100))%")
        if progress >= 1.0 {
            timer.invalidate()
            SwiftSpinner.show(duration: 2.0, title: "Done.", animated: false)
            self.numberOfVideos = 0.0
            self.currentVideo = 1.0
            self.endTime = 0.0
            self.startTime = 0.0
            self.progress = 0.0
        }
    }
    
    func saveFire( _ timer: Timer) {
        if isSaved {
            timer.invalidate()
            SwiftSpinner.show(duration: 2.0, title: "Saved.", animated: false)
            self.isSaved = false
        }
    }
    
    func saveVideo(){
        SwiftSpinner.show("Saving...", animated: true)
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.saveFire), userInfo: nil, repeats: true)
        guard let url = videoURL else { return }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { saved, error in
            if saved {
                self.isSaved = true
            }
        }
    }
    
    
    
    private func thumbnailForVideoAtURL(url: URL){
        
        let asset = AVAsset(url: url)
        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        
        var time = asset.duration
        time.value = min(time.value, 2)
        
        do {
            let imageRef = try assetImageGenerator.copyCGImage(at: time, actualTime: nil)
            thumbnails.append(UIImage(cgImage: imageRef))
            
        } catch {
            print("error")
        }
    }
    
    func showTranscriptController(){
        let transcriptController = TranscriptController()
        print(thumbnails)
        transcriptController.thumbnails = thumbnails
        transcriptController.videoURLs = videoURLs
        transcriptController.title = "Videos"
        self.navigationController?.pushViewController(transcriptController, animated: true)
        
    
    }
}
