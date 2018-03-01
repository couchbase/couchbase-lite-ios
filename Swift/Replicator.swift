//
//  Replicator.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
        
        /* internal */ init(withStatus status: CBLReplicatorStatus) {
            activity = ActivityLevel(rawValue: UInt8(status.activity.rawValue))!
            progress = Progress(completed: status.progress.completed, total: status.progress.total)
            error = status.error
        }
    }
    
    /// Initializes a replicator with the given configuration.
    ///
    /// - Parameter config: The configuration.
    public init(config: ReplicatorConfiguration) {
        _config = ReplicatorConfiguration(config: config, readonly: true)
        _impl = CBLReplicator(config: config.toImpl());
    }
    
    
    /// The replicator's configuration.
    public var config: ReplicatorConfiguration {
        return _config
    }
    
    
    /// The replicator's current status: its activity level and progress. Observable.
    public var status: Status {
        return Status(withStatus: _impl.status)
    }
    
    
    /// Starts the replicator. This method returns immediately; the replicator runs asynchronously
    /// and will report its progress throuh the replicator change notification.
    public func start() {
        registerActiveReplicator()
        _impl.start()
    }
    
    
    /// Stops a running replicator. This method returns immediately; when the replicator actually
    /// stops, the replicator will change its status's activity level to `.stopped`
    /// and the replicator change notification will be notified accordingly.
    public func stop() {
        _impl.stop()
    }
    
    
    /// Adds a replicator change listener. Changes will be posted on the main queue.
    ///
    /// - Parameter listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addChangeListener(
        _ listener: @escaping (ReplicatorChange) -> Void) -> ListenerToken {
        return self.addChangeListener(withQueue: nil, listener);
    }
    
    
    /// Adds a replicator change listener with the dispatch queue on which changes
    /// will be posted. If the dispatch queue is not specified, the changes will be
    /// posted on the main queue.
    ///
    /// - Parameters:
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addChangeListener(withQueue queue: DispatchQueue?,
        _ listener: @escaping (ReplicatorChange) -> Void) -> ListenerToken {
        let token = _impl.addChangeListener(with: queue, listener: { (change) in
            listener(ReplicatorChange(replicator: self, status: Status(withStatus: change.status)))
        })
        return ListenerToken(token)
    }
    
    
    /// Removes a change listener with the given listener token.
    ///
    /// - Parameter token: The listener token.
    public func removeChangeListener(withToken token: ListenerToken) {
        _impl.removeChangeListener(with: token._impl)
    }
    
    
    // MARK: Internal
    
    
    func registerActiveReplicator() {
        _lock.lock()
        if _listenerToken == nil {
            _config.database.addReplicator(self)
            _listenerToken = _impl.addChangeListener({ (change) in
                if change.status.activity == kCBLReplicatorStopped {
                    self.unregisterActiveReplicator()
                }
            })
        }
        _lock.unlock()
    }
    
    
    func unregisterActiveReplicator() {
        _lock.lock()
        if let token = _listenerToken {
            _impl.removeChangeListener(with: token)
            _config.database.removeReplicator(self)
            _listenerToken = nil
        }
        _lock.unlock()
    }
    
    
    private let _impl: CBLReplicator
    
    private let _config: ReplicatorConfiguration
    
    private var _listenerToken: CBLListenerToken?
    
    private let _lock = NSLock()
}
