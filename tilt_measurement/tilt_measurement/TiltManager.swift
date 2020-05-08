//
//  TiltManager.swift
//  tilt_measurement
//
//  Created by Pascal Sturmfels on 5/5/20.
//  Copyright © 2020 LooseFuzz. All rights reserved.
//

import Foundation
import CoreMotion
import simd

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
    var shouldRecordToEmailPartTwo: Bool = false
    
    var complementaryAngle: Array<Double>?
    var gyroAngle: Array<Double>?
    var accelAngle: Array<Double>?
    
    var gyroLastDataPoint: CMGyroData? = nil
    var accelLastDataPoint: CMAccelerometerData? = nil
    
    // Initialize the current estimated rotation as the zero quaternion
    var currentEstimatedRotation: simd_quatd = simd_quatd(ix: 0.0, iy: 0.0, iz: 0.0, r: 1.0)
    var estimateUsingGyro: simd_quatd = simd_quatd(ix: 0.0, iy: 0.0, iz: 0.0, r: 1.0)
    
    let alpha: Double = 0.02
    let updateInterval: Double = 1.0 / 20.0
    
    let angleBiasX: Double = -0.012881
    let angleBiasY: Double = 0.024203
    let angleBiasZ: Double = -0.021752
    
    let accelBiasX: Double = 0.002524
    let accelBiasY: Double = -0.000348
    let accelBiasZ: Double = -0.004805
    
    override init() {
        super.init()
            
        self.motionManager = CMMotionManager()
        self.accelerometerQueue = OperationQueue()
        self.gyroscopeQueue = OperationQueue()
        
        self.motionManager!.gyroUpdateInterval = TimeInterval(updateInterval)
        self.motionManager!.accelerometerUpdateInterval = TimeInterval(updateInterval)
        
        self.complementaryAngle = Array<Double>()
        self.gyroAngle = Array<Double>()
        self.accelAngle = Array<Double>()
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
        
        let measured_w: simd_double3 = simd_double3(x: gyroLastDataPoint.rotationRate.x - self.angleBiasX,
                                                    y: gyroLastDataPoint.rotationRate.y - self.angleBiasY,
                                                    z: gyroLastDataPoint.rotationRate.z - self.angleBiasZ)
        let measured_l: Double = simd_length(measured_w)
        let theta: Double = updateInterval * measured_l
        let gyro_update: simd_quatd = simd_quatd(angle: theta, axis: simd_normalize(measured_w))
        self.estimateUsingGyro = simd_mul(self.estimateUsingGyro, gyro_update)
        self.currentEstimatedRotation = simd_mul(self.currentEstimatedRotation, gyro_update)
        
        let measured_gravity: simd_double3 = simd_double3(x: accelLastDataPoint.acceleration.x - self.accelBiasX,
                                                          y: accelLastDataPoint.acceleration.y - self.accelBiasY,
                                                          z: accelLastDataPoint.acceleration.z - self.accelBiasZ)
        
        let measured_gravity_quaternion: simd_quatd = simd_quatd(angle: Double.pi, axis: simd_normalize(measured_gravity))
        
        // Note: I had to invert this formula in order to get it to work for me. Perhaps
        // the swift hardware has a sign difference with the paper somewhere?
        let measured_global_gravity: simd_quatd = simd_mul(simd_mul(self.currentEstimatedRotation, measured_gravity_quaternion),
                                                                     simd_inverse(self.currentEstimatedRotation))
        let gravity_axis: simd_double3 = simd_double3(x: 0.0, y: 0.0, z: -1.0)
        // I also had to modify this because the measured gravity vector has a z of -1.0
        // rather than 1.0. Sometimes the conversion changes it to 1.0, but sometimes
        // it does not, meaning the tilt_error could fluctuate between close to 0.0
        // and close to pi!
        let tilt_error: Double = acos(abs(simd_normalize(measured_global_gravity.axis).z))
    
        let projected_global_gravity: simd_double3 = simd_double3(x: measured_global_gravity.axis.x, y: measured_global_gravity.axis.y, z: 0.0)
        let tilt_axis: simd_double3 = simd_double3(x: projected_global_gravity.y, y: -projected_global_gravity.x, z: 0.0)
        
        let filter_correction: simd_quatd = simd_quatd(angle: -self.alpha * tilt_error, axis: simd_normalize(tilt_axis))
        self.currentEstimatedRotation = simd_mul(filter_correction, self.currentEstimatedRotation)
        
        let estimateUsingAccel: Double = acos(simd_dot(gravity_axis, simd_normalize(measured_gravity)))
        
        let originalNormal: simd_double3 = simd_double3(x: 0.0, y: 0.0, z: 1.0)
        let rotatedComplementary: simd_double3 = simd_normalize(self.currentEstimatedRotation.act(originalNormal))
        let estimateUsingComplementary: Double = acos(simd_dot(originalNormal, rotatedComplementary))
        
        let rotatedGyro: simd_double3 = simd_normalize(self.estimateUsingGyro.act(originalNormal))
        let estimateUsingGyro: Double = acos(simd_dot(originalNormal, rotatedGyro))
        
        accelAngle!.append(estimateUsingAccel)
        gyroAngle!.append(estimateUsingGyro)
        complementaryAngle!.append(estimateUsingComplementary)
        
        guard let parent = self.parent else {
            return
        }
        
        DispatchQueue.main.async { [unowned parent] in
            let angleInDegrees: Double = estimateUsingComplementary * 180.0 / Double.pi
            parent.updateLabels(withAngle: angleInDegrees)
        }
        
        if self.shouldRecordToEmailPartTwo {
            if self.accelAngle!.count >= self.totalRecords {
                motionManager!.stopGyroUpdates()
                motionManager!.stopAccelerometerUpdates()
                DispatchQueue.main.async { [unowned parent, self] in
                    let angleData: Dictionary<String, Array<Double>> = ["angle_using_accelerometer": self.accelAngle!,
                                                                        "angle_using_gyroscope": self.gyroAngle!,
                                                                        "angle_using_complementary_filter": self.complementaryAngle!]
                    parent.sendDataByMail(data: angleData)
                }
            } else if self.accelAngle!.count % 100 == 0 {
                print("Current gathered records: \(self.accelAngle!.count)/\(self.totalRecords)")
            }
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
