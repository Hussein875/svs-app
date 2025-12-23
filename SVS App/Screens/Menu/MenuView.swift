//
//  MenuView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

    struct MenuView: View {
        @EnvironmentObject var appState: AppState
        
        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Menü")
                            .font(.largeTitle.weight(.bold))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    
                    List {
                        Section(header: Text("Benutzer")) {
                            if let user = appState.currentUser {
                                HStack {
                                    Text("Eingeloggt als:")
                                    Spacer()
                                    Text(user.name)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        
                        Section(header: Text("Aktionen")) {
                            Button(role: .destructive) {
                                appState.currentUser = nil
                                appState.sessionUserId = nil
                            } label: {
                                Label("Ausloggen", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                        
                        Section(header: Text("App-Info")) {
                            HStack {
                                Text("Version")
                                Spacer()
                                Text("1.0")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Entwickelt für")
                                Spacer()
                                Text("SV Souleiman")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }
