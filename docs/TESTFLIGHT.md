# TestFlight delivery (CI)

Every merge to `main` builds the app and uploads it to TestFlight via the
`.github/workflows/testflight.yml` workflow (fastlane `beta` lane). You can also
run it manually from the Actions tab (**Run workflow**).

## One-time setup

### 1. App Store Connect
- Create the app record for bundle id **`com.smartairkey.seamless`** (App Store
  Connect ▸ My Apps ▸ +). This must exist before the first upload.

### 2. App Store Connect API key
App Store Connect ▸ **Users and Access ▸ Integrations ▸ App Store Connect API** ▸
generate a key with the **App Manager** role. You get three things:
- **Key ID** (e.g. `2X9…`)
- **Issuer ID** (a UUID shown above the keys list)
- the **`AuthKey_XXXX.p8`** file (downloadable once)

### 3. Apple Distribution certificate (.p12)
On a Mac with Xcode: create/keep an **Apple Distribution** certificate, then in
**Keychain Access** select the certificate *and its private key* ▸ right-click ▸
**Export** ▸ save as `.p12` with a password.

### 4. Team ID
Apple Developer ▸ **Membership** ▸ Team ID (10 chars, e.g. `AB12CD34EF`).

## GitHub repository secrets
Repo ▸ **Settings ▸ Secrets and variables ▸ Actions ▸ New repository secret**:

| Secret | Value |
|--------|-------|
| `ASC_KEY_ID` | App Store Connect API **Key ID** |
| `ASC_ISSUER_ID` | App Store Connect API **Issuer ID** |
| `ASC_KEY_CONTENT` | the `.p8` file, base64-encoded: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `DIST_CERT_P12` | the distribution `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `DIST_CERT_PASSWORD` | the password you set when exporting the `.p12` |

That's it — the workflow decodes the `.p12`, imports it into a temporary CI
keychain, lets Xcode create/download the App Store provisioning profile via the
API key (`-allowProvisioningUpdates`), builds a Release archive, and uploads it
to TestFlight. Build number = the GitHub Actions run number (unique & increasing);
marketing version comes from `MARKETING_VERSION` in `project.yml`.

## Notes
- **Signing:** the certificate's private key must be in the `.p12` (export the key
  too). The profile is managed automatically — no `.mobileprovision` secret needed.
- **Processing:** the lane returns after upload (`skip_waiting_for_build_processing`),
  so TestFlight shows the build a few minutes later once Apple finishes processing.
- **External testers / review:** internal testers get builds automatically;
  external groups still require Apple's beta review (configure in App Store Connect).
- **Run locally:** `bundle install && bundle exec fastlane beta` with the same env
  vars set (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `APPLE_TEAM_ID`,
  `DIST_CERT_PATH`, `DIST_CERT_PASSWORD`).
- **Alternative signing:** for multi-developer setups consider `fastlane match`
  (certs stored in a private repo) instead of the `.p12` secret.
