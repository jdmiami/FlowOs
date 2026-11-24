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
