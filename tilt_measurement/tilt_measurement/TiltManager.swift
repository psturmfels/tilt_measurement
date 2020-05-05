//
//  TiltManager.swift
//  tilt_measurement
//
//  Created by Pascal Sturmfels on 5/5/20.
//  Copyright © 2020 LooseFuzz. All rights reserved.
//

import Foundation
import CoreMotion

class TiltManager: NSObject {
    var motionManager: CMMotionManager?
    var accelerometerQueue: OperationQueue?
    var gyroscopeQueue: OperationQueue?
    
    var gyroscopeX: Array<Double>?
    var gyroscopeY: Array<Double>?
    var gyroscopeZ: Array<Double>?
    
    var accelerometerX: Array<Double>?
    var accelerometerY: Array<Double>?
    var accelerometerZ: Array<Double>?
    
    var gotDataFromGyro: Bool = false
    var gotDataFromAccel: Bool = false
    
    var parent: ViewController?
    
    var totalRecords: Int = 6000
    
    override init() {
        super.init()
            
        self.motionManager = CMMotionManager()
        self.accelerometerQueue = OperationQueue()
        self.gyroscopeQueue = OperationQueue()
        
        self.motionManager!.gyroUpdateInterval = 1.0 / 20.0
        self.motionManager!.accelerometerUpdateInterval = 1.0 / 20.0
    }
    
    func handleRecordedData(fromGyroscope: Bool) {
        if fromGyroscope {
            self.gotDataFromGyro = true
        }
        if !fromGyroscope {
            self.gotDataFromAccel = true
        }
        
        guard let parent = self.parent else { return }
        
        if self.gotDataFromAccel && self.gotDataFromGyro {
            let data: Dictionary<String, Array<Double>> = [
                "gyroscopeX": self.gyroscopeX!,
                "gyroscopeY": self.gyroscopeY!,
                "gyroscopeZ": self.gyroscopeZ!,
                "accelerometerX": self.accelerometerX!,
                "accelerometerY": self.accelerometerY!,
                "accelerometerZ": self.accelerometerZ!,
            ]
            DispatchQueue.main.async { [unowned parent] in
                parent.sendDataByMail(data: data)
            }
            
        }
    }
    
    func startGyroscopeTap() {
        guard let motionManager = self.motionManager else { return }
        guard let gyroscopeQueue = self.gyroscopeQueue else {return }
        
        guard motionManager.isGyroAvailable else {
            print("Attempted to start the gyroscope but measurements were not available.")
            return
        }
        
        self.gyroscopeX = Array<Double>()
        self.gyroscopeY = Array<Double>()
        self.gyroscopeZ = Array<Double>()
        
        
        motionManager.startGyroUpdates(to: gyroscopeQueue) { [weak self] (data, error) in
            if let error = error {
                print("Failed to get gyroscope updates with error \(error)")
                return
            }
            guard let data = data else {
                print("Unable to unwrap gyroscope data variable")
                return
            }
            guard let self = self else {
                return
            }
            
            let x: Double = data.rotationRate.x
            let y: Double = data.rotationRate.y
            let z: Double = data.rotationRate.z
            
            self.gyroscopeX!.append(x)
            self.gyroscopeY!.append(y)
            self.gyroscopeZ!.append(z)
            
            if self.gyroscopeX!.count % 100 == 0 {
                print("Gyroscope records so far: \(self.gyroscopeX!.count)")
            }
            
            if self.gyroscopeX!.count >= self.totalRecords {
                print("Reached \(self.totalRecords) records for the gyroscope.")
                motionManager.stopGyroUpdates()
                
                self.handleRecordedData(fromGyroscope: true)
            }
        }
    }
    
    func startAccelerometerTap() {
        guard let motionManager = self.motionManager else { return }
        guard let accelerometerQueue = self.accelerometerQueue else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("Attempted to start the accelerometer but measurements were not available.")
            return
        }
        print("Getting updates with a frequency of \(motionManager.accelerometerUpdateInterval)")
        
        self.accelerometerX = Array<Double>()
        self.accelerometerY = Array<Double>()
        self.accelerometerZ = Array<Double>()
        
        motionManager.startAccelerometerUpdates(to: accelerometerQueue) { [weak self] (data, error) in
            if let error = error {
                print("Failed to get accelerometer updates with error \(error)")
                return
            }
            guard let data = data else {
                print("Unable to unwrap accelerometer data variable")
                return
            }
            guard let self = self else {
                return
            }
            
            let x: Double = data.acceleration.x
            let y: Double = data.acceleration.y
            let z: Double = data.acceleration.z
            
            self.accelerometerX!.append(x)
            self.accelerometerY!.append(y)
            self.accelerometerZ!.append(z)
            
            if self.accelerometerX!.count % 100 == 0 {
                print("Accelorometer records so far: \(self.accelerometerX!.count)")
            }
            
            if self.accelerometerX!.count >= self.totalRecords {
                print("Reached \(self.totalRecords) records for the accelerometer.")
                motionManager.stopAccelerometerUpdates()
                
                self.handleRecordedData(fromGyroscope: false)
            }
        }
    }
}
