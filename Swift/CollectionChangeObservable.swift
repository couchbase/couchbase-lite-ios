//
//  CollectionChangeObservable.swift
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

public protocol CollectionChangeObservable {
    /// Add a change listener to listen to change events occurring to any documents in the collection.
    /// To remove the listener, call remove() function on the returned listener token.
    /// Throw Illegal State Exception or equivalent if the default collection doesn’t exist.
    func addChangeListener(listener: @escaping (CollectionChange) -> Void) -> ListenerToken
    
    /// Add a change listener to listen to change events occurring to any documents in the collection.
    /// If a dispatch queue is given, the events will be posted on the dispatch queue.
    /// To remove the listener, call remove() function on the returned listener token.
    /// Throw Illegal State Exception or equivalent if the default collection doesn’t exist.
    func addChangeListener(queue: DispatchQueue?,
                           listener: @escaping (CollectionChange) -> Void) -> ListenerToken
}
