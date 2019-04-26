//
//  hardwareDecoder.swift
//  AVFRTest
//
//  Created by Johnson Chan on 2018/12/12.
//  Copyright © 2018 Johnson Chan. All rights reserved.
//
import VideoToolbox
import AVFoundation

class HardwareDecoder {
    
    var formatDesc: CMVideoFormatDescription?
    var decompressionSession: VTDecompressionSession?
    
    var spsSize: Int = 0
    var ppsSize: Int = 0
    var vpsSize: Int = 0 // need for h265

    var sps: Array<UInt8>?
    var pps: Array<UInt8>?
    var vps: Array<UInt8>? // need for h265
    
//    var playImage: AVSampleBufferDisplayLayer?
    var playImage: UIImageView!
    var streamBuffer = Array<UInt8>()
    let startCode: [UInt8] = [0,0,0,1]
    
//    func setImage(with image: AVSampleBufferDisplayLayer?){
//        self.playImage = image
//    }
    
    func setImage(with image: UIImageView){
        self.playImage = image
    }
    
    func decode_264(_ videoPacket: Array<UInt8>) {
        streamBuffer.append(contentsOf: videoPacket)
        while var packet = self.netPacket() {
            self.receivedRawVideoFrame264(&packet)
        }
    }
    
    func decode_265(_ videoPacket: Array<UInt8>) {
        streamBuffer.append(contentsOf: videoPacket)
        while var packet = self.netPacket() {
            self.receivedRawVideoFrame265(&packet)
        }
    }
    
    func netPacket() -> Array<UInt8>? {
        //make sure start with start code
        if streamBuffer.count < 5 || Array(streamBuffer[0...3]) != startCode {
            return nil
        }
        
        //find second start code , so startIndex = 4
        var startIndex = 4
        
//        while true {
        
            while ((startIndex + 3) < streamBuffer.count) {
                if Array(streamBuffer[startIndex...startIndex+3]) == startCode {
                    
                    let packet = Array(streamBuffer[0..<startIndex])
                    streamBuffer.removeSubrange(0..<startIndex)
                    return packet
                }
                startIndex += 1
            }
//            if readStremData() == 0 {
                return nil
//            }
//        }
        
    }
    func receivedRawVideoFrame265(_ videoPacket: inout Array<UInt8>) {
        
        var biglen = CFSwapInt32HostToBig(UInt32(videoPacket.count - 4))
        memcpy(&videoPacket, &biglen, 4)
        
        let nalType = videoPacket[4]

        switch nalType {
        case 0x26:
//            print("Nal type is IDR frame")
            if createDecompSession265(){
                decodeVideoPacket(videoPacket)
            }
        case 0x40:
//            print("Nal type is VPS")
            vpsSize = videoPacket.count - 4
            vps = Array(videoPacket[4..<videoPacket.count])
        case 0x42:
//            print("Nal type is SPS")
            spsSize = videoPacket.count - 4
            sps = Array(videoPacket[4..<videoPacket.count])
        case 0x44:
//            print("Nal type is PPS")
            ppsSize = videoPacket.count - 4
            pps = Array(videoPacket[4..<videoPacket.count])
        default:
//            print("Nal type is B/P frame")
            decodeVideoPacket(videoPacket)
            break;
        }
//        print("Read Nalu size \(videoPacket.count)");
    }
    func receivedRawVideoFrame264(_ videoPacket: inout Array<UInt8>) {

        var biglen = CFSwapInt32HostToBig(UInt32(videoPacket.count - 4))
        memcpy(&videoPacket, &biglen, 4)

        let nalType = videoPacket[4] & 0x1F

            switch nalType {
            case 0x05:
//                print("Nal type is IDR frame")
                if createDecompSession264() {
                    decodeVideoPacket(videoPacket)
                }
            case 0x07:
//                print("Nal type is SPS")
                spsSize = videoPacket.count - 4
                sps = Array(videoPacket[4..<videoPacket.count])
            case 0x08:
//                print("Nal type is PPS")
                ppsSize = videoPacket.count - 4
                pps = Array(videoPacket[4..<videoPacket.count])
            default:
//                print("Nal type is B/P frame")
                decodeVideoPacket(videoPacket)
                break;
            }

//        print("Read Nalu size \(videoPacket.count)");
    }
    
    func decodeVideoPacket(_ videoPacket: Array<UInt8>) {
        
        let bufferPointer = UnsafeMutablePointer<UInt8>(mutating: videoPacket)
        
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                        memoryBlock: bufferPointer,
                                                        blockLength: videoPacket.count,
                                                        blockAllocator: kCFAllocatorNull,
                                                        customBlockSource: nil,
                                                        offsetToData: 0,
                                                        dataLength: videoPacket.count,
                                                        flags: 0,
                                                        blockBufferOut: &blockBuffer)
        
        if status != kCMBlockBufferNoErr {
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray = [videoPacket.count]
        
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                           dataBuffer: blockBuffer,
                                           formatDescription: formatDesc,
                                           sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                           sampleSizeEntryCount: 1, sampleSizeArray: sampleSizeArray,
                                           sampleBufferOut: &sampleBuffer)
        
        if let buffer = sampleBuffer, let session = decompressionSession, status == kCMBlockBufferNoErr {
            
            let attachments:CFArray? = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true)
            if let attachmentArray = attachments {
                let dic = unsafeBitCast(CFArrayGetValueAtIndex(attachmentArray, 0), to: CFMutableDictionary.self)
                
                CFDictionarySetValue(dic,
                                     Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                     Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
            
            
            //diaplay with AVSampleBufferDisplayLayer
//            if let myPlatImage = self.playImage {
//                myPlatImage.enqueue(buffer)
//
//                DispatchQueue.main.async(execute: {
//                    myPlatImage.setNeedsDisplay()
//                })
//            }
            


            
            // or decompression to CVPixcelBuffer
            var flagOut = VTDecodeInfoFlags(rawValue: 0)
            var outputBuffer = UnsafeMutablePointer<CVPixelBuffer>.allocate(capacity: 1)
            status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: buffer, flags: [._EnableAsynchronousDecompression], frameRefcon: &outputBuffer, infoFlagsOut: &flagOut)
           outputBuffer.deallocate()
            
            
            /*if status == noErr {
                print("OK")
            }else*/ if(status == kVTInvalidSessionErr) {
                print("IOS8VT: Invalid session, reset decoder session");
            } else if(status == kVTVideoDecoderBadDataErr) {
                print("IOS8VT: decode failed status=\(status)(Bad data)");
            } else if(status != noErr) {
                print("IOS8VT: decode failed status=\(status)");
            }
        }
    }
    func createDecompSession265() -> Bool{
        formatDesc = nil
        
        if let spsData = sps, let ppsData = pps, let vpsData = vps{
            let pointerSPS = UnsafePointer<UInt8>(spsData)
            let pointerPPS = UnsafePointer<UInt8>(ppsData)
            let pointerVPS = UnsafePointer<UInt8>(vpsData)
            
            // make pointers array
            let dataParamArray = [pointerVPS, pointerSPS, pointerPPS]
            let parameterSetPointers = UnsafePointer<UnsafePointer<UInt8>>(dataParamArray)
            
            // make parameter sizes array
            let sizeParamArray = [vpsData.count, spsData.count, ppsData.count]
            let parameterSetSizes = UnsafePointer<Int>(sizeParamArray)
            
            // h265 need use CMVideoFormatDescriptionCreateFromHEVCParameterSets with different parameter
            if #available(iOS 11.0, *) {
                let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: parameterSetPointers, parameterSetSizes: parameterSetSizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &formatDesc)
                if let desc = formatDesc, status == noErr {
                    
                    if let session = decompressionSession {
                        VTDecompressionSessionInvalidate(session)
                        decompressionSession = nil
                    }
                    
                    var videoSessionM : VTDecompressionSession?
                    
                    let decoderParameters = NSMutableDictionary()
                    let destinationPixelBufferAttributes = NSMutableDictionary()
                    destinationPixelBufferAttributes.setValue(NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32), forKey: kCVPixelBufferPixelFormatTypeKey as String)
                    
                    var outputCallback = VTDecompressionOutputCallbackRecord()
                    outputCallback.decompressionOutputCallback = decompressionSessionDecodeFrameCallback
                    outputCallback.decompressionOutputRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                    
                    let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                              formatDescription: desc, decoderSpecification: decoderParameters,
                                                              imageBufferAttributes: destinationPixelBufferAttributes,outputCallback: &outputCallback,
                                                              decompressionSessionOut: &videoSessionM)
                    
                    if(status != noErr) {
                        print("\t\t VTD ERROR type: \(status)")
                    }
                    
                    self.decompressionSession = videoSessionM
                }else {
                    print("IOS8VT: reset decoder session failed status=\(status)")
                }
            }
        }
        
        return true
    }
    func createDecompSession264() -> Bool{
        formatDesc = nil

        if let spsData = sps, let ppsData = pps {
            let pointerSPS = UnsafePointer<UInt8>(spsData)
            let pointerPPS = UnsafePointer<UInt8>(ppsData)

            // make pointers array
            let dataParamArray = [pointerSPS, pointerPPS]
            let parameterSetPointers = UnsafePointer<UnsafePointer<UInt8>>(dataParamArray)

            // make parameter sizes array
            let sizeParamArray = [spsData.count, ppsData.count]
            let parameterSetSizes = UnsafePointer<Int>(sizeParamArray)


            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: parameterSetPointers, parameterSetSizes: parameterSetSizes, nalUnitHeaderLength: 4, formatDescriptionOut: &formatDesc)

            if let desc = formatDesc, status == noErr {

                if let session = decompressionSession {
                    VTDecompressionSessionInvalidate(session)
                    decompressionSession = nil
                }

                var videoSessionM : VTDecompressionSession?

                let decoderParameters = NSMutableDictionary()
                let destinationPixelBufferAttributes = NSMutableDictionary()
                destinationPixelBufferAttributes.setValue(NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32), forKey: kCVPixelBufferPixelFormatTypeKey as String)

                var outputCallback = VTDecompressionOutputCallbackRecord()
                outputCallback.decompressionOutputCallback = decompressionSessionDecodeFrameCallback
                outputCallback.decompressionOutputRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

                let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                          formatDescription: desc, decoderSpecification: decoderParameters,
                                                          imageBufferAttributes: destinationPixelBufferAttributes,outputCallback: &outputCallback,
                                                          decompressionSessionOut: &videoSessionM)

                if(status != noErr) {
                    print("\t\t VTD ERROR type: \(status)")
                }

                self.decompressionSession = videoSessionM
            }else {
                print("IOS8VT: reset decoder session failed status=\(status)")
            }
        }

        return true
    }
    
    func displayDecodedFrame(_ imageBuffer: CVImageBuffer?) {
        if let pixel: CVPixelBuffer = imageBuffer {
            let ciImage = CIImage(cvPixelBuffer: pixel)
            
            let uiImage = UIImage(ciImage: ciImage)
            DispatchQueue.main.async(execute: {
                guard let iv = self.playImage else {
                    return
                }
                iv.image = uiImage
            })
        }
    }
}
private func decompressionSessionDecodeFrameCallback(_ decompressionOutputRefCon: UnsafeMutableRawPointer?, _ sourceFrameRefCon: UnsafeMutableRawPointer?, _ status: OSStatus, _ infoFlags: VTDecodeInfoFlags, _ imageBuffer: CVImageBuffer?, _ presentationTimeStamp: CMTime, _ presentationDuration: CMTime) -> Void {
    
    let streamManager: HardwareDecoder = unsafeBitCast(decompressionOutputRefCon, to: HardwareDecoder.self)

    if status == noErr {
        // do something with your resulting CVImageBufferRef that is your decompressed frame
        streamManager.displayDecodedFrame(imageBuffer);
    }
}
