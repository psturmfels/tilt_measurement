//
//  ViewController.swift
//  tilt_measurement
//
//  Created by Pascal Sturmfels on 5/5/20.
//  Copyright © 2020 LooseFuzz. All rights reserved.
//

import UIKit
import MessageUI

class ViewController: UIViewController, MFMailComposeViewControllerDelegate {
    let tiltManager: TiltManager = TiltManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tiltManager.parent = self
        
        // Do any additional setup after loading the view.
        self.tiltManager.startGyroscopeTap()
        self.tiltManager.startAccelerometerTap()
    }

    func sendDataByMail(data: Dictionary<String, Array<Double>>) {
        let mailString: NSMutableString = NSMutableString()
        guard let firstColumn = data.first else { return }
        let numRecords: Int = firstColumn.value.count
        let keyArray: Array<String> = Array(data.keys)
        
        mailString.append(keyArray.joined(separator: ",") + "\n")
        for recordIndex in 0..<numRecords {
            var row: Array<String> = Array<String>()
            for key in keyArray {
                row.append("\(data[key]![recordIndex])")
            }
            mailString.append(row.joined(separator: ",") + "\n")
        }
        
        let sendData = mailString.data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)
        
        guard let sendContent = sendData else {
            return
        }
            
        let currentDate: Date = Date()
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = DateFormatter.Style.medium
        formatter.timeStyle = DateFormatter.Style.medium
        
        let emailController: MFMailComposeViewController = MFMailComposeViewController()
        emailController.mailComposeDelegate = self
        emailController.setSubject("Motion data recorded at \(formatter.string(from: currentDate))")
        emailController.setMessageBody("Send from Pascal's iPhone.", isHTML: false)

        // Attaching the .CSV file to the email.
        emailController.addAttachmentData(sendContent, mimeType: "text/csv", fileName: "Sample.csv")
        
        if MFMailComposeViewController.canSendMail() {
            self.present(emailController, animated: true, completion: nil)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}

