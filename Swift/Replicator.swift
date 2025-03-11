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
import Combine
import CouchbaseLiteSwift_Private


/// A replicator for replicating document changes between a local database and a target database.
/// The replicator can be bidirectional or either push or pull. The replicator can also be one-short
/// or continuous. The replicator runs asynchronously, so observe the status property to
/// be notified of progress.
public final class Replicator {
    
    /// Activity level of a replicator.
    ///
    /// - Note:
    ///   - stopped: The replicator is finished or hit a fatal error.
    ///   - offline: The replicator is offline as the remote host is unreachable.
    ///   - connecting: The replicator is connecting to the remote host.
    ///   - idle: The replicator is inactive waiting for changes or offline.
    ///   - busy: The replicator is actively transferring data.
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
        self.config = ReplicatorConfiguration(config: config)
        impl = CBLReplicator(config: config.toImpl());
    }
    
    /// The replicator's configuration.
    public let config: ReplicatorConfiguration
    
    /// The replicator's current status: its activity level and progress. Observable.
    public var status: Status {
        return Status(withStatus: impl.status)
    }
    
    /// The SSL/TLS certificate received when connecting to the server.
    public var serverCertificate: SecCertificate? {
        return impl.serverCertificate
    }
    
    /// Starts the replicator. This method returns immediately; the replicator runs asynchronously
    /// and will report its progress through the replicator change notification.
    ///  - Note: This method MUST NOT be called within database's inBatch() block, as it will enter deadlock.
    public func start() {
        registerActiveReplicator()
        impl.start()
    }
    
    /// Starts the replicator with an option to reset the local checkpoint of the replicator. When the local checkpoint
    /// is reset, the replicator will sync all changes since the beginning of time from the remote database.
    /// This method returns immediately; the replicator runs asynchronously and will report its progress through
    /// the replicator change notification.
    ///
    /// - Parameters:
    ///   - reset: Resets the local checkpoint before starting the replicator.
    public func start(reset: Bool) {
        registerActiveReplicator()
        impl.start(withReset: reset);
    }
    
    /// Stops a running replicator. This method returns immediately; when the replicator actually
    /// stops, the replicator will change its status's activity level to `.stopped`
    /// and the replicator change notification will be notified accordingly.
    public func stop() {
        impl.stop()
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
        let token = impl.addChangeListener(with: queue, listener: { (change) in
            listener(ReplicatorChange(replicator: self, status: Status(withStatus: change.status)))
        })
        return ListenerToken(token)
    }
    
    /// Adds a document replication event listener. The document replication events will be posted
    /// on the main queue.
    ///
    /// According to performance optimization in the replicator, the document replication listeners need to be added
    /// before starting the replicator. If the listeners are added after the replicator is started, the replicator needs to be
    /// stopped and restarted again to ensure that the listeners will get the document replication events.
    ///
    /// - Parameter listener: The listener to post document replication events.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addDocumentReplicationListener(
        _ listener: @escaping (DocumentReplication) -> Void) -> ListenerToken {
        return self.addDocumentReplicationListener(withQueue: nil, listener);
    }
    
    /// Adds a document replication event listener with the dispatch queue on which events
    /// will be posted. If the dispatch queue is not specified, the document replication
    /// events will be posted on the main queue.
    ///
    /// According to performance optimization in the replicator, the document replication listeners need to be added
    /// before starting the replicator. If the listeners are added after the replicator is started, the replicator needs to be
    /// stopped and restarted again to ensure that the listeners will get the document replication events.
    ///
    /// - Parameters:
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post document replication events.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addDocumentReplicationListener(withQueue queue: DispatchQueue?,
        _ listener: @escaping (DocumentReplication) -> Void) -> ListenerToken {
        let token = impl.addDocumentReplicationListener(with: queue, listener: { (replication) in
            let docs = replication.documents.map {
                return ReplicatedDocument(id: $0.id,
                                          flags: DocumentFlags(rawValue: Int($0.flags.rawValue)),
                                          error: $0.error,
                                          scope: $0.scope,
                                          collection: $0.collection)
            }
            listener(DocumentReplication(replicator: self, isPush: replication.isPush,documents: docs))
        })
        return ListenerToken(token)
    }
    
    /// Removes a change listener with the given listener token.
    ///
    /// - Parameter token: The listener token.
    public func removeChangeListener(withToken token: ListenerToken) {
        impl.removeChangeListener(with: token.impl)
    }
    
    // MARK: Combine Publisher
    
    @available(iOS 13.0, *)
    public func changePublisher(on queue: DispatchQueue = .main) -> AnyPublisher<ReplicatorChange, Never> {
        let subject = PassthroughSubject<ReplicatorChange, Never>()
        
        let token = self.addChangeListener(withQueue: queue) { change in
            subject.send(change)
        }

        return subject
            .receive(on: queue)
            .handleEvents(receiveCancel: { token.remove()})
            .eraseToAnyPublisher()
    }
    
    @available(iOS 13.0, *)
    public func documentReplicationPublisher(on queue: DispatchQueue = .main) -> AnyPublisher<DocumentReplication, Never> {
        let subject = PassthroughSubject<DocumentReplication, Never>()
        
        let token = self.addDocumentReplicationListener(withQueue: queue) { change in
            subject.send(change)
        }

        return subject
            .receive(on: queue)
            .handleEvents(receiveCancel: { token.remove() })
            .eraseToAnyPublisher()
    }
    
    /// Get pending document ids for default collection. If the default collection is not part of
    /// the replication, an Illegal State Exception will be thrown.
    ///
    /// - Returns: A  set of document Ids, each of which has one or more pending revisions
    @available(*, deprecated, message: "Use pendingDocumentIds(collection:) instead.")
    public func pendingDocumentIds() throws -> Set<String> {
        return try impl.pendingDocumentIDs()
    }

    /// Check whether the document in the default collection is pending to push or not. If the
    /// default collection is not  part of the replicator, an Illegal State Exception will be thrown.
    ///
    /// - Parameter documentID: The ID of the document to check
    /// - Returns: true if the document has one or more revisions pending, false otherwise
    @available(*, deprecated, message: "Use isDocumentPending(_ documentID:collection:) instead.")
    public func isDocumentPending(_ documentID: String) throws -> Bool {
        var error: NSError?
        let result = impl.isDocumentPending(documentID, error: &error)
        if let err = error {
            throw err
        }

        return result
    }
    
    /// Get pending document ids for the given collection. If the given collection is not part of
    /// the replication, an Invalid Parameter Exception will be thrown.
    ///
    /// - Parameter collection The collection where the document belongs
    /// - Returns: A  set of document Ids, each of which has one or more pending revisions
    public func pendingDocumentIds(collection: Collection) throws -> Set<String> {
        return try impl.pendingDocumentIDs(for: collection.impl)
    }

    /// Check whether the document in the given collection is pending to push or not. If the given collection
    /// is not part of the replicator, an Invalid Parameter Exception will be thrown.
    ///
    /// - Parameters:
    ///   - collection: The collection where the document belongs.
    ///   - documentID: The ID of the document to check.
    /// - Returns: true if the document has one or more revisions pending, false otherwise
    public func isDocumentPending(_ documentID: String, collection: Collection) throws -> Bool {
        var error: NSError?
        let result = impl.isDocumentPending(documentID, collection: collection.impl, error: &error)
        if let err = error {
            throw err
        }

        return result
    }
    
    // MARK: Internal
    
    func registerActiveReplicator() {
        lock.lock()
        if listenerToken == nil {
            config.database.addReplicator(self)
            listenerToken = impl.addChangeListener({ [unowned self] (change) in
                if change.status.activity == kCBLReplicatorStopped {
                    self.unregisterActiveReplicator()
                }
            })
        }
        lock.unlock()
    }
    
    func unregisterActiveReplicator() {
        lock.lock()
        if let token = listenerToken {
            impl.removeChangeListener(with: token)
            config.database.removeReplicator(self)
            listenerToken = nil
        }
        lock.unlock()
    }
    
    private let impl: CBLReplicator
    
    private var listenerToken: CBLListenerToken?
    
    private let lock = NSLock()
    
}
