# Running without a paid Apple Developer account

The phone-control app (WebDriverAgent, "WDA") that this workspace installs on each iPhone must be signed by an Apple account signed in to Xcode on the host Mac. A **free Apple ID (Personal Team)** works, but it needs **weekly manual maintenance**. A paid Apple Developer Program membership removes this chore. This guide covers the free path.

## What a free account means in practice

| Limit | Effect on this workspace |
| --- | --- |
| **Signatures expire after 7 days.** | After expiry, iOS refuses to launch the control app. A copy already running usually keeps working until it is next launched. Any phone restart, cable reconnect, Mac restart, `local:reload`/`local:stop`, or controller restart after expiry takes that phone **offline** until someone refreshes the signature. Keeping the phone plugged in does not renew it. |
| **Startup never re-signs.** | `local:start`, `Start Dashboard.command`, and the optional login LaunchAgent reuse the existing signed build (`xcodebuild test-without-building`). Only `npm run wda:prepare` re-signs. |
| **Xcode reuses an unexpired signature.** | On the reference host, a rebuild one day after signing kept the original expiry date. Rebuilding early does **not** automatically extend the 7 days; see step 3 of the refresh below. |
| **Small device and App ID caps.** | Apple limits how many devices and new app identifiers a free account can register (the device cap is commonly reported as 3). If Xcode reports a device or App ID limit, the only fix is a paid account. Keep a single `WDA_BUNDLE_ID` for all phones and never change it casually; each new identifier counts against the weekly cap. |
| **The Xcode sign-in can lapse.** | Apple may require the owner to sign in again, including a two-factor code. A refresh fails until the owner does so in Xcode → Settings → Accounts. |
| **Nothing refreshes automatically.** | This repository does not include an automatic refresh job. Do not promise unattended operation on a free account. |

## Check when the current signature expires

Run from the project directory on the host:

```sh
app=$(ls -dt ~/Library/Developer/Xcode/DerivedData/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app | head -n 1)
security cms -D -i "$app/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - -
```

The result is printed in UTC (the trailing `Z`). Record it in the private `.local/installation.md`, and set a calendar reminder **one to two days before** it. A refresh is due every 5–6 days. The command prints only the date; do not paste the full decoded profile anywhere, because it contains the team and device identifiers.

## Weekly refresh procedure

Plan a few minutes when nobody is operating the phones. Phone control goes offline during the refresh; the website stays up. Active scroll runs stop.

**Before you start (owner):**

- The Mac is signed in to its normal user account.
- Xcode → Settings → Accounts shows the Apple ID without an error. Sign in again here if asked; never send the password or code to the assistant.
- Every phone is connected by USB and **unlocked**. The control app can only be launched on an unlocked phone. The dashboard's Unlock panel cannot help here, because it needs the control app already running.

**Then, from the project directory:**

1. Pause automatic startup if the login LaunchAgent from HOST_DEPLOYMENT.md section 7 is installed. Otherwise it restarts the controller in the middle of the build:

   ```sh
   launchctl bootout "gui/$(id -u)/com.phoneworkspace.host" 2>/dev/null || true
   ```

2. Stop only the phone controller. The dashboard, database, and tunnel keep running:

   ```sh
   node --env-file=.env --import tsx src/devices/stop-wda-service.ts
   ```

3. Move the cached control-app signature aside so Xcode issues a fresh 7-day one rather than reusing the old one. This only **moves** profiles whose identifier matches this workspace's `WDA_BUNDLE_ID` into `.local/retired-profiles`; nothing is deleted, and other apps' profiles are untouched:

   ```sh
   bash <<'SH'
   set -eu
   BUNDLE=$(sed -n 's/^WDA_BUNDLE_ID=//p' .env)
   [ -n "$BUNDLE" ] || { echo "WDA_BUNDLE_ID is not set in .env"; exit 1; }
   dest=.local/retired-profiles/$(date +%Y%m%d-%H%M%S)
   find "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles" -maxdepth 1 -name '*.mobileprovision' 2>/dev/null | while IFS= read -r f; do
     id=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)
     case "$id" in *".$BUNDLE.xctrunner")
       mkdir -p "$dest"; chmod 700 .local/retired-profiles "$dest"; mv "$f" "$dest/"; echo "Retired one cached control-app profile.";;
     esac
   done
   SH
   ```

   If the rebuild in step 4 fails, you can move the retired file back to the folder it came from (`~/Library/Developer/Xcode/UserData/Provisioning Profiles` on current Xcode).

4. Re-sign and rebuild for every registered phone:

   ```sh
   npm run wda:prepare -- --all
   ```

5. Run the expiry check above again. It must show a date about **7 days from now**. If it still shows the old date, Xcode reused the old signature. Do not restart phones or services until the old date has passed; then repeat steps 3–4 after it expires, when Xcode is guaranteed to issue a new one.

   *Status:* step 3 is the intended way to force an early renewal, but it has not yet been confirmed on the reference host. Confirm the new date on the first refresh and record the result in `.local/installation.md`.

6. Restart the phone controller. With every phone still unlocked:

   ```sh
   npm run local:start
   ```

   This restarts the controller, which reinstalls the newly signed app on each phone. The dashboard keeps running.

7. Resume automatic startup, only if you paused it in step 1:

   ```sh
   launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.phoneworkspace.host.plist"
   ```

8. Verify in the dashboard that **every** phone shows online with a live screen, and do one harmless action on each (Home or a single tap). If a phone shows **Untrusted Developer**, the owner trusts it under Settings → General → VPN & Device Management; this is normally needed only when the signing certificate changed.

## If the signature already expired

The symptoms are phones showing offline or an error after a restart or reconnect, and the controller log `.wda/wda-service.log` reporting an expired or invalid profile. The control app may also refuse to open on the phone.

Run the same refresh procedure. Step 3 is optional in this case, because Xcode issues a new signature once the old one has expired. Each phone stays offline until step 6 completes.

## Common refresh failures

| Message or symptom | Action |
| --- | --- |
| "No Account for Team", "session expired", or sign-in errors | Owner signs in again in Xcode → Settings → Accounts, then repeat step 4. |
| Device or App ID limit reached | Free-account cap. Remove a phone from the workspace, or move to a paid account. Do not invent a new bundle ID to get around it. |
| Phone stuck at "unlock required" after step 6 | Unlock the phone on site; the controller retries. |
| A phone's build fails because it is not connected | Reconnect and unlock it, wait for Xcode's device window to show it ready, then run `npm run wda:prepare -- --udid THAT_UDID`. |

## Moving to a paid account later

Have the owner join the Apple Developer Program with the same Apple ID, or add the organization's team in Xcode → Settings → Accounts. Update `XCODE_ORG_ID` in `.env` to the paid Team ID, keep or deliberately choose a `WDA_BUNDLE_ID` under that team, and run `npm run wda:prepare -- --all`. Then restart phone control as in steps 6–8. Paid signatures last about a year, so the weekly refresh is no longer needed; record the new expiry date and plan a yearly renewal instead.
