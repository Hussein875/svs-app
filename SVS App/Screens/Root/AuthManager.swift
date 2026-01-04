//
//  AuthManager.swift
//  SVS App
//
//  Created by Hussein Souleiman on 04.01.26.
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: FirebaseAuth.User?

    init() {
        self.user = Auth.auth().currentUser
        Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
        }
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
    }

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.user = result.user
    }

    func signOut() throws {
        try Auth.auth().signOut()
        self.user = nil
    }
}
