# Liquid Menu Motion Implementation Plan

> **Status: archived on 2026-07-20.** This plan records an earlier motion direction and must not be executed as a current checklist. The current wheel reuses one persistent window and uses the source-contract tests in `work/` as its active regression boundary.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add approved liquid-feel appear, dismiss, and icon-focus motion to Arcly while preserving the current glass material.

**Architecture:** Keep all visual motion in `ArclyWheelView.swift` as explicit constants and SwiftUI transforms. Keep mouse selection and hit testing in `ArclyWheelWindow.swift` unchanged except for dismiss timing if the visual close duration changes.

**Tech Stack:** SwiftUI, AppKit, Python source-contract test.

---

### Task 1: Motion Contract Test

**Files:**
- Create: `work/arcly-liquid-motion-contract-test.py`

- [ ] **Step 1: Write the failing test**

Create a Python script that reads `Sources/Arcly/ArclyWheelView.swift` and asserts the presence of named motion constants plus the specific motion hooks for menu visibility, icon focus, running-dot breathing, and center content transition.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 work/arcly-liquid-motion-contract-test.py`

Expected: FAIL because the current source does not yet contain `MenuMotion` constants or the new motion hooks.

### Task 2: Menu Appear And Dismiss Motion

**Files:**
- Modify: `Sources/Arcly/ArclyWheelView.swift`
- Optionally modify: `Sources/Arcly/ArclyWheelWindow.swift`

- [ ] **Step 1: Add `MenuMotion` constants**

Define timing and transform constants in `ArclyWheelView.swift` so the motion values are named and easy to tune.

- [ ] **Step 2: Replace the current global menu scale**

Change the existing `scaleEffect(appState.isMenuVisible ? 1.0 : 0.3)` into a subtle x/y liquid compression plus opacity and blur.

- [ ] **Step 3: Keep close timing aligned**

If the dismiss animation is shorter than the existing `0.35s` order-out delay, keep the delay long enough that the animation can finish before hiding the window.

### Task 3: Icon Focus Switch Motion

**Files:**
- Modify: `Sources/Arcly/ArclyWheelView.swift`

- [ ] **Step 1: Reduce selected icon motion**

Change selection from a large `1.18` scale and fixed 8-point push to a smaller surface-tension float using named constants.

- [ ] **Step 2: Animate the running dot**

When an icon is selected, scale the dot slightly and move it with the icon.

- [ ] **Step 3: Add a subtle focus glow**

Add a very light, material-neutral focus halo behind the selected icon. It must not connect icons or change the glass material.

### Task 4: Center Content Swap Motion

**Files:**
- Modify: `Sources/Arcly/ArclyWheelView.swift`

- [ ] **Step 1: Add a stable identity for center content**

Use a derived string identity for selected app/music/gear state so text swaps animate predictably.

- [ ] **Step 2: Add blur/scale cross-fade**

Use a short asymmetric transition for the selected app label and music/gear state.

### Task 5: Verification

**Files:**
- Test: `work/arcly-liquid-motion-contract-test.py`

- [ ] **Step 1: Run the contract test**

Run: `python3 work/arcly-liquid-motion-contract-test.py`

Expected: PASS.

- [ ] **Step 2: Build Arcly**

Run: `xcodebuild -project Arcly.xcodeproj -scheme Arcly -configuration Release build`

Expected: build succeeds with exit code 0.

- [ ] **Step 3: Install for manual trial**

Copy the Release app into `/Applications/Arcly.app` only after the build succeeds.
