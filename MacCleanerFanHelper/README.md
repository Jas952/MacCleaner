# Local fan control

MacCleaner supports administrator-approved local installation without a paid Apple Developer membership. Open **Fans → Enable Fan Control**. The helper is installed in `/Library/PrivilegedHelperTools/com.maccleaner.fanhelper`, with a launchd job in `/Library/LaunchDaemons/com.maccleaner.fanhelper.plist`.

The app and helper authenticate each XPC message with code-signing requirements pinned to their exact code hashes. A root-owned `.client.plist` beside the helper stores the approved app identity. Rebuilding or replacing the app requires using **Enable Fan Control** again. Both development and release bundles must be signed (ad-hoc signing is sufficient locally). Developer ID and notarization remain separate distribution concerns.

## Controls

- **Manual** selects RPM within the hardware-reported minimum/maximum.
- **Maximum for 10s** sets every fan to its own maximum, then returns Auto.
- **Auto / All Auto** releases fans controlled by this MacCleaner session.
- The UI displays actual RPM, target RPM and the hardware mode.

Choose Auto in other fan-control applications first. MacCleaner rejects taking over an existing manual controller. It cannot prevent another application from taking over after a command.

## Menu-bar panel

The top **Fan control** icon beside Graphs opens two live fan schematics. Each channel has a Manual selector and a custom slider (drag/release, arrow keys, and accessibility increment/decrement). Auto fades and disables the slider. The power button selects macOS Auto; green indicates the hardware confirms Auto. It does not force a stopped fan to spin or disable cooling. Auto may be firmware mode 0 or system mode 3. The panel has no scrolling, maximum/all-auto shortcuts or live badge; feedback has a fixed, inset status area. Live RPM is sampled only while the panel is visible. The drawings are schematic and the animation is not speed-calibrated.

## Recovery

The helper serializes writes, validates both the IOKit return value and SMC result, encodes targets according to their SMC type, and waits for firmware readback. System-mode unlock allows up to eight seconds for thermal management to yield; mode and Ftst recovery wait for readback. Already-restored Auto is accepted without a redundant firmware write. Failed writes trigger rollback; failed rollback is reported and retried. The helper owns the ten-second boost deadline. Closing the app’s connection returns Auto. A 15-second lease covers lost heartbeats, including an unresponsive main thread. A root-owned `.active` marker enables recovery after a helper restart; normal restoration removes it. No manual targets are restored after sleep/restart. Physical firmware behavior and forced shutdown cannot be guaranteed by a userspace process.

## Verification

Run the controller fault-injection checks without changing hardware:

```sh
swiftc -D FAN_HELPER_TESTING MacCleanerFanHelper/SMCFanHelper.swift MacCleanerFanHelper/Tests/FanControllerTests.swift -o .build/fan-controller-tests
.build/fan-controller-tests
```

Build and launch through `./script/build_and_run.sh --verify`. Verify installation, a bounded boost and return to Auto in the Fans screen. Do not describe simulation/build success as a hardware test.
