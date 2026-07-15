# Slouch Play Guide

Slouch is intended to feel more like guiding a glider than operating a joystick. Movements should be small, smooth, and comfortable. The phone stays still; the player moves only within an easy personal range.

## Before a flight

1. Sit or stand in a supported, balanced position.
2. Place the iPhone upright in portrait on a stable surface or stand. Do not hold it in a way that requires the neck to chase the screen.
3. Frame the face and upper shoulders in soft, even light. Avoid bright windows directly behind the player.
4. Look comfortably at the center of the display and let the calibration hold finish.
5. Keep enough room around the body for small side bends without reaching or twisting.

Do not play while walking, driving, riding, or in any situation where the phone or the player cannot remain stationary.

## Modes

### Casual Flight — 90 seconds

Casual maps head direction continuously: turn to steer horizontally and make a small nod to move vertically. There are no discrete boost or roll gestures in this mode; every obstacle is navigable with simple head-follow steering. It is the best first camera-control experience and the simplest place to tune sensitivity.

### Tech Neck Journey — three minutes

Tech Neck presents an authored sequence of on-screen cues and hazards. The route moves through neutral holds, alternating turns, gentle retractions, side bends, nods, and optional shoulder-set cues. Quality scoring favors smooth, controlled input and time near the calibrated neutral position; it is never an instruction to force farther movement.

The shoulder signal is an approximate two-dimensional cue when the upper body is visible. It must not be treated as a posture measurement or diagnosis.

## Camera controls

| Movement | Response | Technique cue |
| --- | --- | --- |
| Comfortable turn left/right | Horizontal steering | Keep the eyes and jaw relaxed; use a small range. |
| Small chin nod | Vertical follow or nod action | Think “small yes,” then return to neutral. |
| Gentle retraction | Shielded boost in Tech Neck | Move the head softly backward without looking up or down. |
| Gentle side bend left/right | Roll dodge in Tech Neck | Keep the movement controlled and return through center. |
| Relaxed shoulder set | Optional Tech Neck recovery cue | Let the shoulders soften; do not squeeze or force. |
| Neutral hold | Rearms gestures and supports flow | Use the position that felt comfortable during calibration. |

Discrete gestures trigger once and require a stable return to neutral before they can fire again. If a control repeats or feels too eager, slow the return to center or lower sensitivity in Settings.

## Calibration and tracking

Slouch calibrates at the beginning of a camera-controlled flight. On compatible devices, ARKit TrueDepth tracking is preferred. If it is unavailable, the app attempts an on-device Vision front-camera path.

During calibration:

- Keep the face visible and avoid talking or making a large expression.
- Hold the most comfortable forward-looking position; there is no universal “correct” angle.
- If calibration fails, improve the lighting, center the face, and try again.
- If the ship drifts after the player or phone moves, pause the flight and choose recalibration.

Tracking temporarily withholds control when confidence is low, the face is lost, or abrupt motion exceeds the interaction safeguard. Hold still and return to the calibrated center rather than making a larger correction.

## Touch demo and Simulator

The iOS Simulator automatically enters synthetic-input mode. A physical iPhone can also choose **Use touch demo** if camera access is unavailable.

- Drag the circular pad left/right to steer and up/down for the vertical channel.
- In Tech Neck, tap the left circular-arrow button to roll left.
- In Tech Neck, tap the shield button to boost.
- In Tech Neck, tap the right circular-arrow button to roll right.

Touch mode is useful for checking gameplay and accessibility without camera input. Its results are kept locally and are not submitted to Game Center.

## Scoring, points, and streaks

Score grows with flight time, cleared hazards, pickups, course completion, and the run's smoothness, neutral, balance, and tracking quality. Collisions reduce hull and quality; the scoring system does not ask the player to increase movement range.

Completed courses award points and update the daily streak. The app keeps 50 recent attempts plus any older records needed to preserve each mode's genuine local top ten. If a streak freeze is available, it is consumed automatically to protect exactly one missed day. Longer gaps begin a new streak.

Camera-controlled completed runs must also satisfy tracking-quality and smoothness safeguards before Game Center submission. Casual and Tech Neck scores use separate boards.

## Comfort and safety

Slouch is entertainment with general movement prompts. It does not evaluate posture, diagnose a condition, prescribe an exercise dose, or promise a health outcome.

- Use only a pain-free, comfortable range.
- Never force a cue or continue to chase a score.
- Stop immediately for pain, dizziness, numbness, tingling, weakness, headache, visual disturbance, nausea, or unusual discomfort.
- If symptoms are significant, persistent, new, or associated with recent injury, seek guidance from a qualified healthcare professional before resuming.
- Anyone with a condition affecting balance, movement, vision, or neurological function should get appropriate individual guidance before using movement controls.

Touch demo remains available when movement control is not appropriate.

## Privacy

The tracking layer exposes normalized pose values and gesture events to the game; it does not expose a camera-frame recording API. Frames are processed in memory on the iPhone and are not written to photos or app storage, retained by Slouch, or uploaded by Slouch.

Stored locally:

- Settings and onboarding completion
- Points, themes, streaks, and freezes
- Run summaries and local scores

Not stored by Slouch:

- Camera photos or video
- A face model or face identity
- Raw frame history

When Game Center is enabled and the player is authenticated, Slouch may send an eligible final numeric score to Apple. Apple manages the Game Center account and leaderboard data. Resetting progress inside Slouch clears local data but does not delete Game Center records.

Camera access can be changed at any time in **iOS Settings → Privacy & Security → Camera**. Denying access leaves the touch demo available.

## Quick troubleshooting

| Symptom | What to try |
| --- | --- |
| Calibration fails or remains at “Preparing camera” | Confirm camera permission, center the face, use even light, then choose **Retry camera**. |
| Tracking frequently pauses | Remove backlighting, keep the phone still, and keep the whole face visible. |
| Ship drifts | Reposition the phone, return to a comfortable center, and recalibrate from Pause. |
| Controls feel too sensitive | Reduce sensitivity in Settings and recalibrate. |
| No camera controls in Simulator | Expected: use the on-screen touch deck or run on a physical iPhone. |
| Global score is missing | Confirm Game Center sign-in and the App Store Connect leaderboard setup in the Development Guide. Local score remains available. |
