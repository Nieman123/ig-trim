# IG Trim — Follow/Unfollow Helper for Instagram (macOS)

A small Bash script that compares your **followers** vs **following** from an Instagram data export, then walks you through the accounts you follow who don’t follow you back. You can:

- open each profile in your browser
- whitelist accounts you’re fine keeping (artists, brands, friends who live under rocks)
- mark accounts for unfollow
- save a persistent whitelist so future runs skip approved accounts
- export a clean `to_unfollow.txt` with clickable profile links

> ⚠️ This does **not** auto-unfollow for you. It keeps your account safe and avoids Instagram’s anti-automation rules. You’ll click profiles and unfollow manually.

---

## Contents
- [What you’ll need](#what-youll-need)
- [Export your Instagram data (followers & following)](#export-your-instagram-data-followers--following)
- [Download this tool](#download-this-tool)
- [Run it](#run-it)
- [What the script does](#what-the-script-does)
- [Command options](#command-options)
- [Example session](#example-session)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Privacy](#privacy)
- [Contributing](#contributing)
- [License](#license)

---

## What you’ll need
- macOS (tested on recent versions)
- Terminal
- The HTML files from Instagram’s export:
  - `followers_1.html` (you may have more than one if Instagram splits it)
  - `following.html`

Built-in tools used: `grep`, `sed`, `awk`, `sort`, `comm`, `open` (all standard on macOS).

---

## Export your Instagram data (followers & following)

1. Open Instagram (mobile app or web) and go to **Accounts Center**.
2. Navigate to **Your information and permissions** → **Download your information**.
3. Choose your Instagram profile.
4. Pick **Some of your information** and select:
   - **Followers**
   - **Following**
5. Format: **HTML**
6. Date range: **All time** (or whatever you want)
7. Submit the request and wait for the download link from Meta.
8. Download and unzip. Inside you’ll find something like:
   - `followers_1.html` (possibly `followers_2.html`, etc.)
   - `following.html`

> Tip: Put these HTML files in a folder together with the script.

---

## Download this tool

```bash
# Using git (recommended)
git clone https://github.com/<your-username>/ig-trim.git
cd ig-trim

# Make the script executable
chmod +x ig-trim.sh