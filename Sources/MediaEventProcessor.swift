/*
 Copyright 2022 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import AEPCore
import AEPServices
import Foundation

class MediaEventProcessor: MediaEventProcessing {
    private static let LOG_TAG = MediaConstants.LOG_TAG
    private static let CLASS_NAME = "MediaEventProcessor"
    private let dispatchQueue = DispatchQueue(label: "MediaEventProcessor.DispatchQueue")
    private let mediaState: MediaState
    #if DEBUG
    var mediaSessions: [String: MediaSession] = [:]
    var uuid: String {
        return UUID().uuidString
    }
    #else
    private var mediaSessions: [String: MediaSession] = [:]
    private var uuid: String {
        return UUID().uuidString
    }
    #endif

    private var dispatcher: ((_ event: Event) -> Void)?

    init(dispatcher: ((_ event: Event) -> Void)?) {
        self.mediaState = MediaState()
        self.dispatcher = dispatcher
    }

    /// Creates session with provided tracker configuration
    /// - Parameters:
    ///    - trackerConfig: tracker configuration.
    ///    - trackerSessionId: A `UUID` string representing tracker session ID which can be used for debugging.
    func createSession(trackerConfig: [String: Any], trackerSessionId: String?) -> String? {
        dispatchQueue.sync {
            let sessionId = uuid
            let session = MediaRealTimeSession(id: sessionId, trackerSessionId: trackerSessionId, state: mediaState, dispatchQueue: dispatchQueue, dispatcher: dispatcher)

            mediaSessions[sessionId] = session
            Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Created a new session (\(sessionId))")
            return sessionId
        }
    }

    /// Queues the media experience`Event` with XDM data for session with `sessionId`
    /// - Parameters:
    ///    - sessionId: UniqueId of session to which media experience`Event` belongs.
    ///    - event: a `MediaXDMEvent` containing media event name and media experience XDM.
    func processEvent(sessionId: String, event: MediaXDMEvent) {
        dispatchQueue.async {
            guard let session = self.mediaSessions[sessionId] else {
                Log.debug(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Can not process session (\(sessionId)). SessionId is invalid.")
                return
            }

            session.queue(event: event)
            Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Successfully queued event (\(event.eventType) for Session (\(sessionId)).")
        }
    }

    /// Ends the session `sessionId`.
    ///
    /// - Parameter sessionId: Unique session id for session to end.
    func endSession(sessionId: String) {
        dispatchQueue.async {
            guard let session = self.mediaSessions[sessionId] else {
                Log.debug(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Cannot end media session (\(sessionId)). SessionId is invalid.")
                return
            }

            session.end {
                self.mediaSessions.removeValue(forKey: sessionId)
                Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Successfully ended media session (\(sessionId))")
            }

            Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Scheduled end for media session (\(sessionId))")
        }
    }

    /// Aborts all the active sessions.
    func abortAllSessions() {
        dispatchQueue.async {
            self.mediaSessions.forEach(self.abort)
        }
    }

    /// Update Media state and notify sessions
    /// - Parameter configurationSharedStateData: Dictionary containing configuration  shared state data
    func updateMediaState(configurationSharedStateData: [String: Any]?) {
        dispatchQueue.async {
            self.mediaState.updateConfigurationSharedState(configurationSharedStateData)
            self.mediaSessions.forEach { sessionId, _ in self.notifyMediaStateUpdate(sessionId: sessionId) }
        }
    }

    /// Notify media sessions with backend session id
    /// - Parameters:
    ///  - requestEventId: UUID `String` denoting edge request event id.
    ///  - backendSessionId: UUID `String` returned by the backend.
    func notifyBackendSessionId(requestEventId: String, backendSessionId: String?) {
        dispatchQueue.async {
            self.mediaSessions.forEach { sessionId, _ in self.mediaSessions[sessionId]?.handleSessionUpdate(requestEventId: requestEventId, backendSessionId: backendSessionId) }
        }
    }

    /// Notify media sessions with error responses from the backend
    /// - Parameters:
    ///  - requestEventId: UUID denoting edge request event id.
    ///  - data: dictionary containing errors returned by the backend.
    func notifyErrorResponse(requestEventId: String, data: [String: Any?]) {
        dispatchQueue.async {
            self.mediaSessions.forEach { sessionId, _ in self.mediaSessions[sessionId]?.handleErrorResponse(requestEventId: requestEventId, data: data) }
        }

    }

    /// Notify MediaState updates
    /// - Parameter sessionId: Unique sessionId of session
    private func notifyMediaStateUpdate(sessionId: String) {
        guard let session = self.mediaSessions[sessionId] else {
            Log.debug(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Cannot notify states changes for media session (\(sessionId)). SessionId is invalid.")
            return
        }

        session.handleMediaStateUpdate()
    }

    /// Abort the session `sessionId`.
    ///
    /// - Parameter sessionId: Unique sessionId of session to be aborted.
    private func abort(sessionId: String, session: MediaSession) {
        guard let session = self.mediaSessions[sessionId] else {
            Log.debug(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Cannot abort media session (\(sessionId)). SessionId is invalid.")
            return
        }

        session.abort {
            self.mediaSessions.removeValue(forKey: sessionId)
            Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Successfully aborted media session (\(sessionId)).")
        }

        Log.trace(label: Self.LOG_TAG, "[\(Self.CLASS_NAME)<\(#function)>] - Scheduled abort for media session (\(sessionId).")
    }
}
