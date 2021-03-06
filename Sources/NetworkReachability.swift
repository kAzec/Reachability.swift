//
//  NetworkReachability.swift
//  Reachability
//
//  Created by kAzec on 24/03/2018.
//  Copyright © 2018 kAzec. All rights reserved.
//

import os.lock
import Foundation
import SystemConfiguration

public final class NetworkReachability : CustomStringConvertible {
    public enum Error : Swift.Error {
        case failedToSetCallback
        case failedToSetDispatchQueue
    }
    
    private static var singleton: NetworkReachability?
    private static var singletonLock = os_unfair_lock()
    
    public static var `default`: NetworkReachability? {
        os_unfair_lock_lock(&singletonLock)
        defer {
            os_unfair_lock_unlock(&singletonLock)
        }
        
        if let instance = singleton {
            return instance
        } else {
            singleton = NetworkReachability()
            return singleton
        }
    }
    
    public static var isReachable: Bool {
        return NetworkReachability.default?.isReachable ?? false
    }
    
    public var flags: SCNetworkReachabilityFlags {
        var flags = SCNetworkReachabilityFlags()
        
        if !SCNetworkReachabilityGetFlags(reachabilityRef, &flags) {
            return []
        } else {
            return flags
        }
    }
    
    public var status: Status {
        var flags = SCNetworkReachabilityFlags()
        
        if !SCNetworkReachabilityGetFlags(reachabilityRef, &flags) {
            return .unreachable
        } else {
            return Status(flags: flags)
        }
    }
    
    public var isReachable : Bool {
        return isReachable(for: status)
    }
    
    public var description: String {
        let flags = self.flags
        
        #if targetEnvironment(simulator)
        let W: Character = "X"
        #else
        let W: Character = "-"
        #endif
        let R: Character = flags.contains(.reachable) ? "R" : "-"
        let c: Character = flags.contains(.connectionRequired) ? "c" : "-"
        let t: Character = flags.contains(.transientConnection) ? "t" : "-"
        let i: Character = flags.contains(.interventionRequired) ? "i" : "-"
        let C: Character = flags.contains(.connectionOnTraffic) ? "C" : "-"
        let D: Character = flags.contains(.connectionOnDemand) ? "D" : "-"
        let l: Character = flags.contains(.isLocalAddress) ? "l" : "-"
        let d: Character = flags.contains(.isDirect) ? "d" : "-"
        
        return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)"
    }
    
    public var delegate: NetworkReachabilityDelegate? {
        get {
            return (notifyingQueue ?? monitoringQueue).sync { underlyingDelegate }
        }
        
        set {
            (notifyingQueue ?? monitoringQueue).sync { underlyingDelegate = newValue }
        }
    }
    
    public var allowsWWANConnection: Bool
    
    public let notifyingQueue: DispatchQueue?
    public let notificationCenter: NotificationCenter
    
    private var isMonitoring = atomic_flag()
    private var monitoringFlags: SCNetworkReachabilityFlags = []
    private let reachabilityRef: SCNetworkReachability
    
    private lazy var monitoringQueue = DispatchQueue(label: "com.uncosmos.Reachability.monitoring", qos: .utility)
    private weak var underlyingDelegate: NetworkReachabilityDelegate?
    
    private init(
        reachabilityRef: SCNetworkReachability,
        delegate: NetworkReachabilityDelegate?,
        allowsWWANConnection: Bool,
        notifyingQueue: DispatchQueue?,
        notificationCenter: NotificationCenter
    ) {
        self.notifyingQueue = notifyingQueue
        self.reachabilityRef = reachabilityRef
        self.underlyingDelegate = delegate
        self.allowsWWANConnection = allowsWWANConnection
        self.notificationCenter = notificationCenter
    }
    
    public func startMonitoring() throws {
        guard !atomic_flag_test_and_set(&isMonitoring) else { return }
        
        var context = SCNetworkReachabilityContext(
            version:         0,
            info:            UnsafeMutableRawPointer(Unmanaged<NetworkReachability>.passUnretained(self).toOpaque()),
            retain:          nil,
            release:         nil,
            copyDescription: nil
        )
        
        if !SCNetworkReachabilitySetCallback(self.reachabilityRef, reachabilityCallback, &context) {
            atomic_flag_clear(&isMonitoring)
            throw Error.failedToSetCallback
        }
        
        if !SCNetworkReachabilitySetDispatchQueue(reachabilityRef, monitoringQueue) {
            SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
            atomic_flag_clear(&isMonitoring)
            throw Error.failedToSetDispatchQueue
        }
        
        (notifyingQueue ?? monitoringQueue).async(execute: notifyInitialReachabilityStatus)
    }
    
    public func stopMonitoring() {
        atomic_flag_clear(&isMonitoring)
        SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachabilityRef, nil)
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Convenience Initializers
public extension NetworkReachability {
    convenience init?(
        hostname: String,
        delegate: NetworkReachabilityDelegate? = nil,
        allowsWWANConnection: Bool = true,
        notifyingQueue: DispatchQueue? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        guard let reachabilityRef = SCNetworkReachabilityCreateWithName(nil, hostname) else {
            return nil
        }
        
        self.init(
            reachabilityRef:      reachabilityRef,
            delegate:             delegate,
            allowsWWANConnection: allowsWWANConnection,
            notifyingQueue:       notifyingQueue,
            notificationCenter:   notificationCenter
        )
    }
    
    convenience init?(
        address: inout sockaddr,
        delegate: NetworkReachabilityDelegate? = nil,
        allowsWWANConnection: Bool = true,
        notifyingQueue: DispatchQueue? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        guard let reachabilityRef = SCNetworkReachabilityCreateWithAddress(nil, &address) else {
            return nil
        }
        
        self.init(
            reachabilityRef:      reachabilityRef,
            delegate:             delegate,
            allowsWWANConnection: allowsWWANConnection,
            notifyingQueue:       notifyingQueue,
            notificationCenter:   notificationCenter
        )
    }
    
    convenience init?(
        delegate: NetworkReachabilityDelegate? = nil,
        allowsWWANConnection: Bool = true,
        notifyingQueue: DispatchQueue? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        var zeroAddress = sockaddr()
        zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zeroAddress.sa_family = sa_family_t(AF_INET)
        
        self.init(
            address:              &zeroAddress,
            delegate:             delegate,
            allowsWWANConnection: allowsWWANConnection,
            notifyingQueue:       notifyingQueue,
            notificationCenter:   notificationCenter
        )
    }
}

// MARK: - Status
public extension NetworkReachability {
    enum Status : String, Hashable {
        case unreachable = "Unreachable"
        case reachableViaWLAN = "WLAN"
        case reachableViaWWAN = "WWAN"
        
        init(flags: SCNetworkReachabilityFlags) {
            guard flags.contains(.reachable) else {
                self = .unreachable
                return
            }
            
            #if targetEnvironment(simulator)
            self = .reachableViaWLAN
            #else
            if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
                if !flags.contains(.interventionRequired) {
                    self = .reachableViaWLAN
                }
            }
            
            self = flags.contains(.connectionRequired) ? .unreachable : .reachableViaWLAN
            #endif
        }
    }
}

// MARK: - Reachability Delegate
public protocol NetworkReachabilityDelegate : class {
    func reachability(_ reachability: NetworkReachability, didChangeFlags flags: SCNetworkReachabilityFlags)
    func reachability(_ reachability: NetworkReachability, didChangeStatus status: NetworkReachability.Status)
    func reachability(_ reachability: NetworkReachability, didBecomeReachableWith status: NetworkReachability.Status)
    func reachability(_ reachability: NetworkReachability, didBecomeUnreachableWith status: NetworkReachability.Status)
}

public extension NetworkReachabilityDelegate {
    func reachability(_ reachability: NetworkReachability, didChangeFlags flags: SCNetworkReachabilityFlags) { }
    func reachability(_ reachability: NetworkReachability, didChangeStatus status: NetworkReachability.Status) { }
    func reachability(_ reachability: NetworkReachability, didBecomeReachableWith status: NetworkReachability.Status) {}
    func reachability(
        _ reachability: NetworkReachability,
        didBecomeUnreachableWith status: NetworkReachability.Status
    ) { }
}

// MARK: - Notification
public extension NSNotification.Name {
    static let networkReachabilityDidChange = NSNotification.Name("NRNetworkReachabilityDidChange")
}

// MARK: - Private
private extension NetworkReachability {
    func isReachable(for status: Status) -> Bool {
        switch status {
        case .unreachable:      return false
        case .reachableViaWLAN: return true
        case .reachableViaWWAN: return allowsWWANConnection
        }
    }
    
    func reachabilityDidChange(with newFlags: SCNetworkReachabilityFlags) {
        guard monitoringFlags != newFlags else { return }
        
        if let notifyingQueue = notifyingQueue {
            notifyingQueue.async {
                self.notifyReachabilityChanges(for: newFlags)
            }
        } else {
            notifyReachabilityChanges(for: newFlags)
        }
        
        monitoringFlags = newFlags
    }
    
    func notifyInitialReachabilityStatus() {
        let flags = self.flags
        let status = Status(flags: flags)
        
        if let delegate = underlyingDelegate {
            delegate.reachability(self, didChangeFlags: flags)
            delegate.reachability(self, didChangeStatus: status)
            
            if self.isReachable(for: status) {
                delegate.reachability(self, didBecomeReachableWith: status)
            } else {
                delegate.reachability(self, didBecomeUnreachableWith: status)
            }
        }
        
        notificationCenter.post(name: .networkReachabilityDidChange, object: self)
        monitoringFlags = flags
    }
    
    func notifyReachabilityChanges(for flags: SCNetworkReachabilityFlags) {
        let status = Status(flags: flags)
        
        if let delegate = underlyingDelegate {
            delegate.reachability(self, didChangeFlags: flags)
            
            let monitoringStatus = Status(flags: monitoringFlags)
            if status != monitoringStatus {
                delegate.reachability(self, didChangeStatus: status)
                
                switch (isReachable(for: monitoringStatus), isReachable(for: status)) {
                case (true, false): delegate.reachability(self, didBecomeUnreachableWith: status)
                case (false, true): delegate.reachability(self, didBecomeReachableWith: status)
                default:            break
                }
            }
        }
        
        notificationCenter.post(name: .networkReachabilityDidChange, object: self)
        monitoringFlags = flags
    }
}

private func reachabilityCallback(
    reachability: SCNetworkReachability,
    flags: SCNetworkReachabilityFlags,
    info: UnsafeMutableRawPointer?
) {
    guard let info = info else { return }
    
    let reachability = Unmanaged<NetworkReachability>.fromOpaque(info).takeUnretainedValue()
    reachability.reachabilityDidChange(with: flags)
}
