//
//  Replication.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


public extension Database {
    /** Creates a replication between this database and a remote one,
        or returns an existing one if it's already been created. */
    public func replication(with url: URL) -> Replication {
        return Replication(impl: _impl.replication(with: url),
                           database: self )
    }

    /** Creates a replication between this database and another local database,
        or returns an existing one if it's already been created. */
    public func replication(with otherDB: Database) -> Replication {
        return Replication(impl: _impl.replication(with: otherDB._impl),
                           database: self,
                           otherDatabase: otherDB)
    }
}


/** A replication between a local and a remote database.
    Before starting the replication, you just set either the `push` or `pull` property, or both.
    The replication runs asynchronously, so set a delegate or observe the status property
    to be notified of progress. */
public final class Replication {

    /** Activity level of a replication. */
    public enum ActivityLevel : UInt8 {
        case Stopped = 0
        case Offline
        case Connecting
        case Idle
        case Busy
    }

    /** Progress of a replication. If `total` is zero, the progress is indeterminate; otherwise,
        dividing the two will produce a fraction that can be used to draw a progress bar. */
    public struct Progress {
        public let completed: UInt64
        public let total: UInt64
    }

    /** Combined activity level and progress of a replication. */
    public struct Status {
        public let activity: ActivityLevel
        public let progress: Progress

        init(_ status: CBLReplicationStatus) {
            activity = ActivityLevel(rawValue: UInt8(status.activity.rawValue))!
            progress = Progress(completed: status.progress.completed, total: status.progress.total)
        }
    }


    /** The local database. */
    public let database: Database

    /** The URL of the remote database to replicate with, or nil if the target database is local. */
    public var remoteURL: URL? {
        return _impl.remoteURL
    }

    /** The target database, if it's local, else nil. */
    public let otherDatabase: Database?

    /** Should the replication push documents to the target? */
    public var push: Bool {
        get {return _impl.push}
        set {_impl.push = newValue}
    }

    /** Should the replication pull documents from the target? */
    public var pull: Bool {
        get {return _impl.pull}
        set {_impl.pull = newValue}
    }

    /** Should the replication stay active indefinitely, and push/pull changed documents? */
    public var continuous: Bool {
        get {return _impl.continuous}
        set {_impl.continuous = newValue}
    }

    /** An object that will receive progress and error notifications. */
    public var delegate: ReplicationDelegate? {
        get {
            let bridge = _impl.delegate as? DelegateBridge
            return bridge?.swiftDelegate
        }
        set {
            var bridge = _impl.delegateBridge as? DelegateBridge
            if bridge == nil {
                bridge = DelegateBridge()
                _impl.delegateBridge = _bridge
            }
            bridge!.swiftDelegate = newValue
            _impl.delegate = bridge
        }
    }

    /** Starts the replication. This method returns immediately; the replication runs asynchronously
        and will report its progress to the delegate.
        (After the replication starts, changes to the `push`, `pull` or `continuous` properties are
        ignored.) */
    public func start() {
        _impl.start()
    }

    /** Stops a running replication. This method returns immediately; when the replicator actually
        stops, the CBLReplication will change its status's activity level to `kCBLStopped`
        and call the delegate. */
    public func stop() {
        _impl.stop()
    }

    /** The replication's current status: its activity level and progress. */
    public var status: Status {
        return Status(_impl.status)
    }

    /** Any error that's occurred during replication. */
    public var lastError: Error? {
        return _impl.lastError
    }


    // MARK: Internal

    private let _impl: CBLReplication
    private weak var _bridge: DelegateBridge?

    init(impl: CBLReplication, database: Database, otherDatabase: Database? = nil) {
        self._impl = impl
        self.database = database
        self.otherDatabase = otherDatabase
    }


    // An implementation of CBLReplicationDelegate that forwards to a Swift ReplicationDelegate
    class DelegateBridge : NSObject, CBLReplicationDelegate {
        func replication(_ replication: CBLReplication, didChange status: CBLReplicationStatus) {
            swiftDelegate?.replication(replication, didChange: Status(status))
        }
        func replication(_ replication: CBLReplication, didStopWithError error: Error?) {
            swiftDelegate?.replication(replication, didStopWithError: error)
        }

        var swiftDelegate :ReplicationDelegate?
    }
}


/** A Replication's delegate is called with progress information while the replication is
    running and when it stops. */
public protocol ReplicationDelegate {
    /** Called when a replication changes its status (activity level and/or progress) while running. */
    func replication(_ replication: CBLReplication, didChange status: Replication.Status)

    /** Called when a replication stops, either because it finished or due to an error. */
    func replication(_ replication: CBLReplication, didStopWithError error: Error?)
}


