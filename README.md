# FlowOS 0.5 — Living Intelligence

A native iPhone companion with offline GPU inference, pastel Liquid Glass and a generative artifact workspace.

## Build and install

Open [Actions](https://github.com/jdmiami/FlowOs/actions), select the latest successful iPhone unsigned IPA run, download an artifact, and extract the IPA from the archive.

- **FlowOS-unsigned-IPA**: standard build for free sideloading; widget extension omitted.
- **FlowOS-LiveActivities-unsigned-IPA**: includes the ActivityKit / WidgetKit extension. Your signing tool must support the embedded extension. Enable Live Activity status in FlowOS Settings and allow Live Activities in iOS.

Both packages require your own signing before installation. If the extension cannot be signed, use the standard build. Free provisioning may require renewal after seven days. Keep the same app identifier and signing account to improve the chance of retaining data; do not uninstall an existing copy without backing up important data.

## Living Intelligence

- Tap the orb to expand radial navigation; drag to deform, release to rebound; pinch to close; long press for shortcuts.
- Home → Open spatial workspace: drag cards, pan and pinch; list view is available for accessibility.
- Labs / Chat → Build app: the local model plans, streams a structured app definition, validates it, retries invalid output once and publishes an artifact.
- Generated apps support text, sliders, toggles, dates, record counts, sums, sum-of-products calculations, grouped bar charts and category boards. They use a validated declarative schema, not arbitrary executable code.
- Settings → Living appearance: choose a preset, generate a palette locally, toggle graphics, custom haptics, interface sounds and Live Activities. Generated palettes are previewable in Labs → Artifacts.
- The Metal membrane shader uses analytic distance-field merging and simulated optical highlights/dispersion, not a full fluid solver. iOS 26+ uses native Liquid Glass where available.
- Rich graphics are disabled while AI runs, under Low Power Mode, Reduce Motion and thermal pressure. No change to the working LiteRT-LM 0.20.0 GPU backend, streaming API or context limit.

## Validation

The Swift core tests cover legacy JSON, artifact parsing, component allowlists, arithmetic and theme validation. Full Xcode and Metal compilation runs through the macOS GitHub Actions workflow. Device performance and Live Activities signing must be tested on a physical iPhone.

Live Activities are opt-in and show only generic local status, not prompts. They do not enable unlimited background inference. Native communications and manual workflow functionality remain as in previous versions.


## Previous setup notes

# FlowOS
Native SwiftUI companion for iPhone 14 Pro Max with pastel glass design and on-device AI.

## Free installation
1. Open the Actions tab and select the iPhone unsigned IPA workflow. A push to main also starts it.
2. After a successful build, download the FlowOS-unsigned-IPA artifact and unzip the outer archive.
3. Use AltStore Classic or Sideloadly on a trusted Mac or Windows PC to sign and install the .ipa using your own free Apple ID. Alternatively use Xcode Personal Team signing from source.
4. Enable Developer Mode if prompted. Free provisioning normally expires after seven days; refresh the signature as needed.

No paid developer membership, TestFlight, cloud inference, or account secrets are required for this path. The unsigned IPA is not directly installable.

## Local development
Install Xcode and XcodeGen, run xcodegen generate, open FlowOS.xcodeproj, select your signing team and device. Use a unique bundle identifier if required.

Import a compatible small quantized .litertlm model in Settings from https://huggingface.co/litert-community. No weights included. GPU runtime and memory limits require physical device testing. No cloud fallback.

## Scope
Includes pastel UI, chat, AI-generated record trackers, persistent local storage, manual workflow checklists, existing Shortcut launcher, phone dialer, email composer, calendar creation, notes and embedded browser.
Autonomous native tool execution, full email inbox, AI voice calls, advanced generated application logic and background automation are not implemented. Calls and email use user review. Not a replacement for iOS.

## Validation
The starter's Swift syntax and seven core schema checks were tested on Linux. Native Xcode compilation, dependency resolution, signing, and iPhone inference must be verified separately. This workflow is intended to test actual iOS compilation. No guarantee of successful signing with third-party libraries until tested.

## Dependencies
Google LiteRT-LM: https://github.com/google-ai-edge/LiteRT-LM
XcodeGen: https://github.com/yonaskolb/XcodeGen
