//
//  Replicator.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A replicator for replicating document changes between a local database and a target database.
/// The replicator can be bidirectional or either push or pull. The replicator can also be one-short
/// or continuous. The replicator runs asynchronously, so observe the status property to
/// be notified of progress.
public final class Replicator {
    
    /// Activity level of a replicator.
    ///
    /// - stopped: The replicator is finished or hit a fatal error.
    /// - offline: The replicator is offline as the remote host is unreachable.
    /// - connecting: The replicator is connecting to the remote host.
    /// - idle: The replicator is inactive waiting for changes or offline.
    /// - busy: The replicator is actively transferring data.
    public enum ActivityLevel : UInt8 {
        case stopped = 0
        case offline
        case connecting
        case idle
        case busy
    }
    
    
    /// Progress of a replicator. If `total` is zero, the progress is indeterminate; otherwise,
    /// dividing the two will produce a fraction that can be used to draw a progress bar.
    public struct Progress {
        
        /// The total number of changes to be processed.
        public let completed: UInt64
        
        /// The total number of changes to be processed.
        public let total: UInt64
    }
    
    
    /// Combined activity level and progress of a replicator.
    public struct Status {
        
        /// The current activity level.
        public let activity: ActivityLevel
        
        /// The current progress of the replicator.
        public let progress: Progress
        
        /// The current error if there is an error occurred.
        public let error: Error?
        
        /* internal */ init(_ status: CBLReplicatorStatus) {
            activity = ActivityLevel(rawValue: UInt8(status.activity.rawValue))!
            progress = Progress(completed: status.progress.completed, total: status.progress.total)
            error = status.error
        }
    }
    
    /// Initializes a replicator with the given configuration.
    ///
    /// - Parameter config: The configuration.
    public init(config: ReplicatorConfiguration) {
        let c: CBLReplicatorConfiguration;
        
        if let url = config.target as? URL {
            c = CBLReplicatorConfiguration(database: config.database._impl, targetURL: url)
        } else {
            let db = (config.target as! Database)._impl
            c = CBLReplicatorConfiguration(database: config.database._impl, targetDatabase: db)
        }
        
        c.continuous = config.continuous
        c.replicatorType = CBLReplicatorType(rawValue: UInt32(config.replicatorType.rawValue))
        c.conflictResolver = nil // TODO
        c.authenticator = config.authenticator
        c.pinnedServerCertificate = config.pinnedServerCertificate
        c.headers = config.headers
        c.channels = config.channels
        c.documentIDs = config.documentIDs
        
        #if os(iOS)
        c.runInBackground = config.runInBackground
        #endif
        
        _impl = CBLReplicator(config: c);
        _config = config
    }
    
    
    /// The replicator's configuration.
    public var config: ReplicatorConfiguration {
        return _config
    }
    
    
    /// The replicator's current status: its activity level and progress. Observable.
    public var status: Status {
        return Status(_impl.status)
    }
    
    
    /// Starts the replicator. This method returns immediately; the replicator runs asynchronously
    /// and will report its progress throuh the replicator change notification.
    public func start() {
        _impl.start()
    }
    
    
    /// Stops a running replicator. This method returns immediately; when the replicator actually
    /// stops, the replicator will change its status's activity level to `.stopped`
    /// and the replicator change notification will be notified accordingly.
    public func stop() {
        _impl.stop()
    }
    
    
    /// Adds a replicator change listener block.
    ///
    /// - Parameter block: The block to be executed when the change is received.
    /// - Returns: An opaque object to act as the listener and for removing the listener
    ///            when calling the removeChangeListener() function.
    @discardableResult
    public func addChangeListener(_ block: @escaping (ReplicatorChange) -> Void) -> NSObjectProtocol {
        return _impl.addChangeListener({ [unowned self] change in
            block(ReplicatorChange(replicator: self, status: Status(change.status)))
        })
    }
    
    
    /// Removes a change listener. The given change listener is the opaque object
    /// returned by the addChangeListener() method.
    ///
    /// - Parameter listener: The listener object to be removed.
    public func removeChangeListener(_ listener: NSObjectProtocol) {
        _impl.removeChangeListener(listener)
    }
    
    
    // MARK: Private
    
    
    private let _impl: CBLReplicator
    
    private let _config: ReplicatorConfiguration
    
    
    // MARK: deinit
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
