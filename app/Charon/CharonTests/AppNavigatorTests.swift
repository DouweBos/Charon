// AppNavigatorTests.swift
// CharonTests

import Testing
@testable import Charon

@MainActor
struct AppNavigatorTests {
    @Test func drillDownAndBackForward() {
        let navigator = AppNavigator()
        navigator.setDefaultTarget("boot")
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
        #expect(navigator.targetID == nil)
    }

    @Test func selectingAVolumeResetsFocus() {
        let navigator = AppNavigator()
        navigator.focus("/Users")
        navigator.selectTarget("external")
        #expect(navigator.focusPath == nil)
        #expect(navigator.targetID == "external")
        #expect(navigator.selectedPath == nil)
    }

    @Test func hoverNeverReplacesSelection() {
        let navigator = AppNavigator()
        navigator.select("/a")
        navigator.hover("/b")
        navigator.hover(nil)
        #expect(navigator.selectedPath == "/a")
    }

    @Test func previewToggles() {
        let navigator = AppNavigator()
        navigator.togglePreview("/a")
        #expect(navigator.previewPath == "/a")
        navigator.togglePreview("/a")
        #expect(navigator.previewPath == nil)
    }
}
