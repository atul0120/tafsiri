# Tafsiri Live — free, hands-free Kiswahili ↔ English for iPhone

Tap **Start** once. Tafsiri keeps listening, even with the screen locked and the phone in your
pocket. Whenever someone near you speaks Kiswahili, it translates it into English, shows it on
screen, and reads it into your AirPods (or the speaker). When you want to answer, it can speak
your English back in Kiswahili.

- **Free:** listening needs no account, key or subscription. Replies use Microsoft's free tier.
- **Private and offline:** OpenAI's Whisper speech model runs on the iPhone itself (via the
  open-source WhisperKit library). After the one-time model download, nothing you hear leaves the
  phone and listening works without internet.

## Replying in Kiswahili (optional)

When you want to answer, tap **Reply in Kiswahili** and speak English. On the pause, Tafsiri
writes down your English on the phone, translates it to Kiswahili and speaks it on the phone's
loudspeaker in a Kenyan voice (Zuri or Rafiki), even if you wear AirPods. ⌨ lets you type a reply.

Turn on **Settings → Auto-reply** for fully hands-free two-way talk: any English the phone hears is
spoken back in Kiswahili, no taps. Leave it off where other people nearby speak English.

Replies need Microsoft's free tiers (listening does not):
1. Sign up at **portal.azure.com** (free account; it may ask for a card to verify identity).
2. Create a resource → **Translator** → Pricing tier **Free F0** → region e.g. *South Africa North*.
3. Create a resource → **Speech** → Pricing tier **Free F0** → same region.
4. In each resource open **Keys and Endpoint**; copy **Key 1** and **Location/Region**.
5. In Tafsiri → Settings → *Free Microsoft keys*, paste them.

Free allowances: 2 million characters a month of translation and 0.5 million characters of
natural voice, which is thousands of replies. When they run out the service stops until next
month; the free tier doesn't charge you. Without the Speech key, replies are shown on screen in
Kiswahili for the other person to read.

## What you need

- A Mac with **Xcode 16 or later** (free). You only need the Mac to install; you can borrow one.
- An iPhone on **iOS 17+**. iPhone 13 or newer is recommended; iPhone 15 Pro or newer is fastest.
- About **1 GB free** on the iPhone for the speech model.
- Your normal **Apple ID**. That's free, but apps installed this way stop opening after
  **7 days**; plug in and press Run again to renew. (A paid Apple Developer account, US$99/yr,
  makes it last a year.)

## Install without a Mac (Windows PC, free)

GitHub builds the app for you on its Macs; Sideloadly puts it on your iPhone.

**A. Build the app on GitHub (about 15 minutes, once)**
1. Create a free account at github.com.
2. Click **+ → New repository**, name it `tafsiri`, choose **Public** (public repos get free Mac
   build time), tick *Add a README*, click **Create**.
3. Click **Add file → Upload files**. Drag in everything from this folder, including the hidden
   `.github` folder and the `Tafsiri` folder. (In Windows File Explorer: View → Show → Hidden
   items, so you can see `.github`.) Click **Commit changes**.
4. Open the **Actions** tab. The "Build iPhone app" job starts by itself; if not, click it →
   **Run workflow**. Wait for the green tick (about 10–15 minutes).
5. Click the finished run → under **Artifacts** download **Tafsiri-ipa**. Unzip it to get
   `Tafsiri.ipa`.
   If it shows a red ✗ instead, download **build-log** and send the errors to Claude.

**B. Install on your iPhone with Sideloadly (about 10 minutes)**
1. On the PC install **Apple Devices** (or iTunes) from the Microsoft Store, and **Sideloadly**
   from sideloadly.io.
2. Connect the iPhone by cable, unlock it, tap **Trust**.
3. Open Sideloadly, drag in `Tafsiri.ipa`, enter your Apple ID email, click **Start**, then enter
   your Apple ID password and any 2-factor code when asked. (Sideloadly sends it only to Apple,
   to sign the app. If you prefer, use a second, spare Apple ID.)
4. On the iPhone: Settings → Privacy & Security → **Developer Mode** → On (it restarts), and
   Settings → General → **VPN & Device Management** → trust your Apple ID.
5. Open Tafsiri on Wi-Fi and let it download the speech model.

**Every 7 days** the free signature expires: connect to the PC and click Start in Sideloadly again
(your settings stay). Sideloadly can also refresh it automatically over Wi-Fi when the PC is on.

## Install with a Mac (about 20 minutes)

1. Copy this folder to the Mac.
2. In Terminal, inside the folder:
   ```
   brew install xcodegen      # one time (needs Homebrew from brew.sh)
   xcodegen
   open Tafsiri.xcodeproj
   ```
   Xcode then downloads WhisperKit automatically (wait for "Package resolution" to finish).
3. Click **Tafsiri** in the left sidebar → **Signing & Capabilities** → *Team*: add and choose your
   Apple ID. If the bundle ID is rejected, change `com.example.tafsiri` to e.g. `com.atul.tafsiri`.
4. Connect the iPhone by cable, unlock it, choose it at the top of Xcode, press **Run ▶**.
5. On the iPhone, first time only:
   - Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).
   - Settings → General → VPN & Device Management → trust your Apple ID.
6. Open Tafsiri on **Wi-Fi** and let it download the speech model (about 626 MB, once).
7. Tap **Start**, allow the microphone. Done.

## Using it

- **Start / Stop** is the only control. The dot turns orange when it hears speech.
- Put the phone in your pocket or on the table; wear AirPods to hear translations privately.
  With AirPods it keeps listening while it talks; on the speaker it pauses briefly so it doesn't
  hear itself.
- Tap any translation to hear it again.
- **Settings:**
  - *Everyone around me speaks Kiswahili*: skips language detection. Better for short phrases
    like "Sawa" or "Ndiyo".
  - *Show the Kiswahili words too*: displays the original. Slower per sentence.
  - *Translate after a … s pause*: lower it for quicker replies, raise it if sentences get cut.
  - *Speech model*: "Fast" if your iPhone is older and translations lag.

## Honest limits

- Each sentence appears **1–4 seconds after the speaker pauses**, depending on your iPhone.
- Whisper's Kiswahili → English is good for everyday speech but not perfect. Heavy Sheng, noisy
  places, or several people talking at once reduce accuracy.
- Very short phrases may be detected as the wrong language; use the setting above.
- Replies need an internet connection (listening doesn't).
- If replies play in your AirPods instead of the speaker, turn AirPods' Bluetooth off for the
  conversation, or keep the phone speaker setting on.

## Files

| File | Job |
|---|---|
| `UtteranceRecorder.swift` | Non-stop mic capture; detects speech and pauses; adapts to background noise |
| `Interpreter.swift` | Whisper on the phone: detects the language and translates to English in one pass |
| `ListenEngine.swift` | The hands-free loop; Reply and auto-reply; handles calls and interruptions |
| `Speaker.swift` | English with the iPhone's voice; Kiswahili with the Microsoft Kenyan voice |
| `ReplyService.swift` | English → Kiswahili translation and voice (Microsoft free tiers) |
| `ContentView.swift`, `SettingsView.swift` | Screens |

If Xcode shows errors on the first build, copy them and send them to Claude.
