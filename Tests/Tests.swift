//
//  ReachabilityTests.swift
//  ReachabilityTests
//
//  Created by Fengwei Liu on 2018/04/21.
//  Copyright © 2018 Fengwei Liu. All rights reserved.
//

import XCTest
@testable import Reachability

class ReachabilityTests: XCTestCase, NetworkReachabilityDelegate {
    let delegate = NetworkReachabilityDelegateThunk()
    
    func testStatus() {
        let reachability: NetworkReachability! = .default
        
        XCTAssertNotNil(reachability, "Failed to get default reachability object.")
        
        print("Network is currently: '\(reachability.status)'")
    }
    
    func testValidHost() {
        let hostname = "example.com"
        let reachability = NetworkReachability(hostname: hostname, delegate: delegate, notifyingQueue: .main)
        
        XCTAssertNotNil(reachability, "Failed to create reachability object for host name: \(hostname).")
        
        let expectation = self.expectation(description: "Reachability for valid host: \(hostname) should be reachable.")
        
        delegate.thunk.didBecomeReachable = { status in
            print("Success: \(hostname) is reachable - \(reachability!)")
            expectation.fulfill()
        }
        
        delegate.thunk.didBecomeUnreachable = { status in
            print("\(hostname) is initially unreachable - \(reachability!)")
        }
        
        XCTAssertNoThrow(try reachability!.startMonitoring(), "Failed to start monitoring reachability status.")
        wait(for: [expectation], timeout: 5)
        reachability!.stopMonitoring()
    }
    
    func testInvalidHost() {
        let hostname = "invalidhostname"
        let reachability = NetworkReachability(hostname: hostname, delegate: delegate, notifyingQueue: .main)
        
        XCTAssertNotNil(reachability, "Failed to create reachability object for host name: \(hostname)")
        
        let expectation = self.expectation(
            description: "Reachability for invalid host: \(hostname) should be unreachable."
        )
        
        delegate.thunk.didBecomeReachable = { status in
            XCTAssert(false, "Failure: \(hostname) should never be reachable - \(reachability!)")
        }
        
        delegate.thunk.didBecomeUnreachable = { status in
            print("Success: \(hostname) is unreachable - \(reachability!)")
            expectation.fulfill()
        }
        
        XCTAssertNoThrow(try reachability!.startMonitoring(), "Failed to start monitoring reachability status.")
        wait(for: [expectation], timeout: 5)
        reachability!.stopMonitoring()
    }
}

class NetworkReachabilityDelegateThunk : NetworkReachabilityDelegate {
    struct Thunk {
        var didChangeStaus: ((NetworkReachability.Status) -> Void)? = nil
        var didBecomeReachable: ((NetworkReachability.Status) -> Void)? = nil
        var didBecomeUnreachable: ((NetworkReachability.Status) -> Void)? = nil
    }
    
    var thunk: Thunk
    
    init() {
        thunk = Thunk()
    }
    
    func reachability(_ reachability: NetworkReachability, didChangeStatus status: NetworkReachability.Status) {
        print("reachability: \(reachability) did change status: \(status)")
        thunk.didChangeStaus?(status)
    }
    
    func reachability(_ reachability: NetworkReachability, didBecomeReachableWith status: NetworkReachability.Status) {
        thunk.didBecomeReachable?(status)
    }
    
    func reachability(_ reachability: NetworkReachability, didBecomeUnreachableWith status: NetworkReachability.Status) {
        thunk.didBecomeUnreachable?(status)
    }
}
