//
//  ContentView.swift
//  mini-ninebot
//
//  Created by Jeff He on 2026/7/5.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = NinebotViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                NinebotDashboardView(model: model)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tabItem {
                Label("车控", systemImage: "dot.circle.and.cursorarrow")
            }

            NavigationStack {
                NinebotTripsTabView(model: model)
            }
            .tabItem {
                Label("行程", systemImage: "road.lanes")
            }

            NavigationStack {
                NinebotRecordingView(model: model)
            }
            .tabItem {
                Label("记录", systemImage: "gauge.with.dots.needle.67percent")
            }

            NavigationStack {
                NinebotSettingsView(model: model)
                    .navigationTitle("我的")
            }
            .tabItem {
                Label("我的", systemImage: "person.crop.circle")
            }
        }
        .tint(Color(red: 0.13, green: 0.82, blue: 0.28))
        .task {
            await model.refreshOnLaunchIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.refreshWhenActiveIfPossible() }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
