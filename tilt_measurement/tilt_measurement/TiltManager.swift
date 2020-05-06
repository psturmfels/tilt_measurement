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
    var shouldRecordToEmail: Bool = false
    
    var currentEstimateAngleX: Double = 0.0
    var currentEstimateAngleY: Double = 0.0
    
    var gyroLastDataPoint: CMGyroData? = nil
    var accelLastDataPoint: CMAccelerometerData? = nil
    
    let beta: Double = 0.98
    let updateInterval: Double = 1.0 / 20.0
    
    let angleBiasX: Double = -0.012881
    let angleBiasY: Double = 0.024203
    
    let accelBiasX: Double = 0.002524
    let accelBiasY: Double = -0.000348
    
    override init() {
        super.init()
            
        self.motionManager = CMMotionManager()
        self.accelerometerQueue = OperationQueue()
        self.gyroscopeQueue = OperationQueue()
        
        self.motionManager!.gyroUpdateInterval = TimeInterval(updateInterval)
        self.motionManager!.accelerometerUpdateInterval = TimeInterval(updateInterval)
    }
    
    func handleUpdate(gyroData: CMGyroData? = nil, accelData: CMAccelerometerData? = nil) {
        if let gyroData = gyroData {
            self.gyroLastDataPoint = gyroData
        }
        
        if let accelData = accelData {
            self.accelLastDataPoint = accelData
        }
        
        guard let gyroLastDataPoint = self.gyroLastDataPoint else {
            return
        }
        guard let accelLastDataPoint = self.accelLastDataPoint else {
            return
        }
        
        let angularVelocityX: Double = gyroLastDataPoint.rotationRate.y - angleBiasY
        let angularVelocityY: Double = -gyroLastDataPoint.rotationRate.x + angleBiasX
        
        let accelerationX: Double = max(min(accelLastDataPoint.acceleration.x - accelBiasX, 1.0), -1.0)
        let accelerationY: Double = max(min(accelLastDataPoint.acceleration.y - accelBiasY, 1.0), -1.0)
        
        self.currentEstimateAngleX = beta * (self.currentEstimateAngleX + angularVelocityX * updateInterval) + (1.0 - beta) * asin(accelerationX)
        self.currentEstimateAngleY = beta * (self.currentEstimateAngleY + angularVelocityY * updateInterval) + (1.0 - beta) * asin(accelerationY)
        
        guard let parent = self.parent else {
            return
        }
        
        DispatchQueue.main.async { [unowned parent] in
            parent.updateLabels(withAngleX: self.currentEstimateAngleX * 180.0 / Double.pi,
                                withAngleY: self.currentEstimateAngleY * 180.0 / Double.pi)
        }
        
        self.gyroLastDataPoint = nil
        self.accelLastDataPoint = nil
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
            
            self.handleUpdate(gyroData: data, accelData: nil)
            
            guard self.shouldRecordToEmail else {
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
            
            self.handleUpdate(gyroData: nil, accelData: data)
            
            guard self.shouldRecordToEmail else {
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
