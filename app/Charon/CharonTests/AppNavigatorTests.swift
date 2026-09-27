// AppNavigatorTests.swift
// CharonTests

import Testing
@testable import Charon

@MainActor
struct AppNavigatorTests {
    @Test func drillDownAndBackForward() {
        let navigator = AppNavigator()
        navigator.setDefaultVolume("boot")
        navigator.focus("/Users")
        navigator.focus("/Users/me")
        #expect(navigator.focusPath == "/Users/me")

        navigator.goBack()
        #expect(navigator.focusPath == "/Users")
        navigator.goForward()
        #expect(navigator.focusPath == "/Users/me")
        #expect(!navigator.canGoForward)
    }

    @Test func newNavigationDropsForwardHistory() {
        let navigator = AppNavigator()
        navigator.focus("/a")
        navigator.goBack()
        navigator.selectTab(.ferry)
        #expect(!navigator.canGoForward)
        #expect(navigator.tab == .ferry)
    }

    @Test func focusingFromAnotherTabReturnsToAnalyze() {
        let navigator = AppNavigator()
        navigator.selectTab(.ferry)
        navigator.focus("/Users")
        #expect(navigator.tab == .analyze)
        #expect(navigator.volumeID == nil)
    }

    @Test func selectingAVolumeResetsFocus() {
        let navigator = AppNavigator()
        navigator.focus("/Users")
        navigator.selectVolume("external")
        #expect(navigator.focusPath == nil)
        #expect(navigator.volumeID == "external")
        #expect(navigator.selectedPath == nil)
    }
}
