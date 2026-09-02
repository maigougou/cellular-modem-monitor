# Releasing Cellular Modem Monitor

The application uses Sparkle 2.9.6 with an Ed25519-signed archive and signed
appcast. It is ad-hoc code signed because the project does not currently have
an Apple Developer ID.

## One-time signing key setup

Generate the key into protected storage outside the Git checkout:

```sh
./scripts/generate-sparkle-key.sh /secure/private/path/sparkle-ed25519-private-key
```

Add the printed `SUPublicEDKey` to `Resources/Info.plist`. Never commit the
private key. Keep at least one offline backup: without a Developer ID, losing
this key prevents existing installations from trusting a replacement key.

The private key is a base64-encoded 32-byte Ed25519 seed accepted by Sparkle's
official `sign_update` and `generate_appcast` tools. Generating and using it
does not require Keychain access.

## Prepare a release

1. Set `CFBundleShortVersionString` to the release version and increment
   `CFBundleVersion` in `Resources/Info.plist`. Build numbers must never be
   reused or decreased.
2. Run the complete test and application build:

   ```sh
   make build
   ```

3. Generate and verify the signed feed:

   ```sh
   SPARKLE_EDDSA_KEY_FILE=/secure/private/path/sparkle-ed25519-private-key \
     ./scripts/prepare-sparkle-release.sh v1.5.0
   ```

   The script uses Sparkle's official tools, signs both the archive entry and
   feed, verifies the resulting signature, and writes `appcast.xml`.

4. Commit the versioned source and signed `appcast.xml`. Build and inspect the
   exact tagged archive again before uploading it.
5. Create a draft GitHub Release and upload both
   `dist/Cellular-Modem-Monitor-macOS.zip` and `appcast.xml`. Keep the ZIP
   filename exactly as recorded in the feed.
6. Publish the draft only after both assets are present. Clients read
   `releases/latest/download/appcast.xml`, so publishing the two assets
   together avoids announcing an update whose archive still returns 404.

`SUEnableAutomaticChecks` enables one check per day. Automatic installation is
off by default; Sparkle presents the update and the user chooses whether to
install it. System profiling is not enabled.
