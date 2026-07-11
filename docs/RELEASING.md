# Releasing MacCleaner

MacCleaner releases are published from version tags (`v1.1`, `v1.2`, and so on). GitHub Actions builds a Developer ID-signed app, creates and notarizes the DMG, signs it with Sparkle Ed25519, creates the GitHub Release, and updates `appcast.xml` on `main`.

## One-time GitHub secrets

- `DEVELOPER_ID_APPLICATION`: full signing identity, for example `Developer ID Application: Name (TEAMID)`.
- `DEVELOPER_ID_APPLICATION_P12_BASE64`: exported Developer ID Application certificate and private key (`.p12`), base64 encoded.
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: password used when exporting the `.p12`.
- `APPLE_API_KEY_P8_BASE64`: App Store Connect API private key (`.p8`), base64 encoded.
- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID.
- `SPARKLE_PRIVATE_KEY`: exported Sparkle Ed25519 private key. This repository already has this secret configured.

The corresponding Sparkle public key is embedded in `MacCleaner/Info.plist`. Never commit the private key, certificate, or App Store Connect key.

## Publish a release

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Update `docs/release-notes.md`.
3. Merge the release commit into `main`.
4. Create and push the matching tag, for example `git tag v1.1 && git push origin v1.1`.
5. Verify the `Release MacCleaner` workflow, notarization, GitHub Release asset, and updated `appcast.xml`.

Sparkle checks the HTTPS appcast every six hours. Every release must have a strictly increasing `CFBundleVersion`; changing only the marketing version is not sufficient.
