//
//  SimDevice.swift
//  SimDirs
//
//  Created by Casey Fleser on 4/30/16.
//  Copyright © 2016 Quiet Spark. All rights reserved.
//

import Foundation

class SimDevice {
	let name			: String
	let udid			: String
	let baseURL			: NSURL
	var apps			= [SimApp]()

	init(name: String, udid: String, baseURL: NSURL) {
		self.name = name
		self.udid = udid
		self.baseURL = baseURL
		
		self.gatherAppInfoFromLastLaunchMap()
		self.gatherAppInfoFromAppState()
//		self.gatherAppInfoFromCaches()	obsolete
		self.gatherAppInfoFromInstallLogs()
		self.cleanupAndRefineAppList()
	}

	// LastLaunchServicesMap.plist seems to be the most reliable location to gather app info
	func gatherAppInfoFromLastLaunchMap() {
		let launchMapInfoURL	= self.baseURL.URLByAppendingPathComponent("data/Library/MobileInstallation/LastLaunchServicesMap.plist")
		guard let launchInfo	= NSPropertyListSerialization.propertyListWithURL(launchMapInfoURL) else { return }
		guard let userInfo		= launchInfo["User"] as? [String : AnyObject] else { return }

		for (bundleID, bundleInfo) in userInfo {
			guard let bundleInfo	= bundleInfo as? [String : AnyObject] else { continue }
			let simApp				= self.apps.match({ $0.bundleID == bundleID }, orMake: { SimApp(bundleID: bundleID) })
			
			simApp.updateFromLastLaunchMapInfo(bundleInfo)
		}
	}

	// applicationState.plist sometimes has info that LastLaunchServicesMap.plist doesn't
	func gatherAppInfoFromAppState() {
		for pathComponent in ["data/Library/FrontBoard/applicationState.plist", "data/Library/BackBoard/applicationState.plist"] {
			let appStateInfoURL		= self.baseURL.URLByAppendingPathComponent(pathComponent)
			guard let stateInfo		= NSPropertyListSerialization.propertyListWithURL(appStateInfoURL) else { continue }

			for (bundleID, bundleInfo) in stateInfo {
				if !bundleID.containsString("com.apple") {
					guard let bundleInfo	= bundleInfo as? [String : AnyObject] else { continue }
					let simApp				= self.apps.match({ $0.bundleID == bundleID }, orMake: { SimApp(bundleID: bundleID) })

					simApp.updateFromAppStateInfo(bundleInfo)
				}
			}
		}
	}
	
	// mobile_installation.log.0 is my least favorite, most fragile way to scan for app installations
	// try this after everything else
	func gatherAppInfoFromInstallLogs() {
		let installLogURL	= self.baseURL.URLByAppendingPathComponent("data/Library/Logs/MobileInstallation/mobile_installation.log.0")
		
		if let installLog = try? String(contentsOfURL: installLogURL) {
			let lines	= installLog.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
			
			for line in lines.reverse() {
				if !line.containsString("com.apple") {
					if line.containsString("makeContainerLiveReplacingContainer") {
						self.extractBundleLocationFromLogEntry(line)
					}
					if line.containsString("_refreshUUIDForContainer") {
						self.extractSandboxLocationFromLogEntry(line)
					}
				}
			}
		}
	}
	
	func extractBundleLocationFromLogEntry(line: String) {
		let logComponents = line.componentsSeparatedByString(" ")
		
		if let bundlePath = logComponents.last {
			if let bundleID = logComponents[safe: logComponents.count - 3] {
				let simApp	= self.apps.match({ $0.bundleID == bundleID }, orMake: { SimApp(bundleID: bundleID) })
				
				simApp.bundlePath = bundlePath
			}
		}
	}
	
	func extractSandboxLocationFromLogEntry(line: String) {
		let logComponents = line.componentsSeparatedByString(" ")
		
		if let sandboxPath = logComponents.last {
			if let bundleID = logComponents[safe: logComponents.count - 5] {
				let simApp	= self.apps.match({ $0.bundleID == bundleID }, orMake: { SimApp(bundleID: bundleID) })
				
				simApp.sandboxPath = sandboxPath
			}
		}
	}

	func cleanupAndRefineAppList() {
		self.apps = self.apps.filter { return $0.hasValidPaths }
		
		for simApp in self.apps {
			simApp.completeInitialization()
		}
		
		// sort?
	}
}