//
//  Replicator.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


extension Notification.Name {
    /** This notification is posted by a Replicator when its status/progress changes or when
     an error occurred. */
    public static let ReplicatorChange = Notification.Name(rawValue: "ReplicatorChangeNotification")
}

/** The key to access the replicator status object. */
public let ReplicatorStatusUserInfoKey = kCBLReplicatorStatusUserInfoKey

/** The key to access the replicator error object if an error occurred. */
public let ReplicatorErrorUserInfoKey = kCBLReplicatorErrorUserInfoKey


/** A replicator for replicating document changes between a local database and a target database.
    The replicator can be bidirectional or either push or pull. The replicator can also be one-short 
    or continuous. The replicator runs asynchronously, so observe the status property to 
    be notified of progress. */
public final class Replicator {
    
    /** Activity level of a replicator. */
    public enum ActivityLevel : UInt8 {
        case stopped = 0    ///< The replication is finished or hit a fatal error.
        case idle           ///< The replication is unactive; either waiting for changes or offline
                            ///< as the remote host is unreachable.
        case busy           ///< The replication is actively transferring data.
    }
    
    
    /** Progress of a replicator. If `total` is zero, the progress is indeterminate; otherwise,
     dividing the two will produce a fraction that can be used to draw a progress bar. */
    public struct Progress {
        /** The total number of changes to be processed. */
        public let completed: UInt64
        
        /** The total number of changes to be processed. */
        public let total: UInt64
    }
    
    
    /** Combined activity level and progress of a replicator. */
    public struct Status {
        /** The current activity level. */
        public let activity: ActivityLevel
        
        /** The current progress of the replicator. */
        public let progress: Progress
        
        /* internal */ init(_ status: CBLReplicatorStatus) {
            activity = ActivityLevel(rawValue: UInt8(status.activity.rawValue))!
            progress = Progress(completed: status.progress.completed, total: status.progress.total)
        }
    }
    
    /** Initializes a replicator with the given configuration. */
    public init(config: ReplicatorConfiguration) {
        precondition(config.database != nil && config.target != nil)
        
        let c = CBLReplicatorConfiguration()
        c.database = config.database!._impl
        
        switch config.target! {
        case .url(let url):
            c.target = CBLReplicatorTarget(url: url)
        case .database(let db):
            c.target = CBLReplicatorTarget(database: db._impl)
        }
        
        c.continuous = config.continuous
        c.replicatorType = CBLReplicatorType(rawValue: UInt32(config.replicatorType.rawValue))
        c.options = config.options
        c.conflictResolver = nil // TODO
        
        _impl = CBLReplicator(config: c);
        _config = config
        
        setupNotificationBridge()
    }
    
    
    /** Starts the replicator. This method returns immediately; the replicator runs asynchronously
        and will report its progress throuh the replicator change notification. */
    public func start() {
        _impl.start()
    }
    
    
    /** Stops a running replicator. This method returns immediately; when the replicator actually
        stops, the replicator will change its status's activity level to `.stopped`
        and the replicator change notification will be notified accordingly. */
    public func stop() {
        _impl.stop()
    }
    
    
    /** The replicator's configuration. */
    public var config: ReplicatorConfiguration {
        return _config
    }
    
    
    /** The replicator's current status: its activity level and progress. Observable. */
    public var status: Status {
        return Status(_impl.status)
    }
    
    
    // MARK: Private
    
    
    private let _impl: CBLReplicator
    
    private let _config: ReplicatorConfiguration
    
    
    private func setupNotificationBridge() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(replicatorChanged(notification:)),
            name: Notification.Name.cblReplicatorChange, object: _impl)
    }
    
    
    @objc func replicatorChanged(notification: Notification) {
        var userinfo = Dictionary<String, Any>()
        
        let s = notification.userInfo![kCBLReplicatorStatusUserInfoKey] as! CBLReplicatorStatus
        userinfo[ReplicatorStatusUserInfoKey] = Status(s)
        
        if let error = notification.userInfo![kCBLReplicatorErrorUserInfoKey] as? NSError {
            userinfo[ReplicatorErrorUserInfoKey] = error
        }
        
        NotificationCenter.default.post(name: .ReplicatorChange, object: self, userInfo: userinfo)
    }
    
    
    // MARK: deinit
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
