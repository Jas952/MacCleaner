# Releasing MacCleaner

MacCleaner releases are published from version tags (`v1.1`, `v1.2`, and so on). GitHub Actions builds an unsigned DMG with an ad-hoc signed app bundle, signs the Sparkle appcast with Ed25519, creates the GitHub Release, and updates `appcast.xml` on `main`.

The app is not Developer ID signed or notarized. macOS Gatekeeper will show an unknown developer warning on first launch. Users may need to right-click the app and choose `Open`.

## One-time GitHub secrets

- `SPARKLE_PRIVATE_KEY`: exported Sparkle Ed25519 private key. This repository already has this secret configured.

The corresponding Sparkle public key is embedded in `MacCleaner/Info.plist`. Never commit the private key.

## Publish a release

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Update `docs/release-notes.md`.
3. Merge the release commit into `main`.
4. Create and push the matching tag, for example `git tag v1.1 && git push origin v1.1`.
5. Verify the `Release MacCleaner` workflow, GitHub Release asset, and updated `appcast.xml`.

Sparkle checks the HTTPS appcast every six hours. Every release must have a strictly increasing `CFBundleVersion`; changing only the marketing version is not sufficient.
