# Asset and Dependency Attribution

Slouch's visual and audio identity was created for this project. No third-party game asset pack, stock illustration, 3D model, texture, or music track is bundled in the repository.

## Original and AI-assisted assets

| Asset | Location | Origin |
| --- | --- | --- |
| Slouch app icon | `Slouch/Resources/Assets.xcassets/AppIcon.appiconset/Slouch-AppIcon-1024.png` | Original AI-assisted image generated for Slouch with OpenAI image generation on July 15, 2026, then resized and integrated into the asset catalog. |
| Spacecraft, asteroids, drones, gates, laser walls, planet, starfield, pickups and trails | `Slouch/Game/GameSceneController.swift` | Original runtime geometry and materials authored in code with SceneKit primitives and custom procedural meshes. |
| Ambient music loop and game sound effects | `Slouch/Services/SoundscapeEngine.swift` | Original waveforms synthesized at runtime with AVFoundation; no sampled or downloaded recordings. |
| Interface artwork | SwiftUI source in `Slouch/Design` and `Slouch/Views` | Original shapes, gradients, materials and layout authored for Slouch. |

The app-icon generation brief described a premium moonstone manta-seed spacecraft, a centered rear/three-quarter silhouette, teal and lavender ion light, an orbital arc, deep midnight-indigo space, calm cinematic lighting, no text, no logos, and no imitation of an existing entertainment property.

The concept reference screenshots supplied during development were used only to understand broad product categories and control ideas. Their artwork, layouts, branding, typography, and other expressive elements were not copied or bundled.

## Apple platform resources

Slouch uses Apple system frameworks and platform-provided resources:

- SwiftUI and Observation
- SceneKit
- ARKit
- Vision and AVFoundation
- GameKit / Game Center
- UIKit feedback and haptics APIs
- SF Symbols through system image names
- Apple system fonts and materials

Use of Apple frameworks, SF Symbols, Game Center, and distribution services remains subject to Apple's current developer agreements and platform terms.

## External code dependencies

There are no external Swift packages or third-party runtime libraries in the current project. XcodeGen may be used as a development-time project generator from `project.yml`; it is not linked into or shipped with the app.

If a future version adds a downloaded visual, audio asset, font, SDK, package, or generated asset from another provider, record its source, creator, license, modification status, and shipped path here before release.
