# 🎛️ ig-trim — Triage Who You Follow On Instagram

## ✨ What this does
- 🔍 Compares your **following** vs. **followers** from Instagram’s data export.
- 👀 Shows each account you follow that doesn’t follow you back.
- 🎹 Lets you act with **single-key shortcuts** (no Enter required):

  | Key | Action |
  |-----|--------|
  | `o` | Open profile in browser **and move to next** |
  | `O` | Open profile **but stay** on the same user |
  | `k` | Keep (adds to whitelist so they won’t show next time) |
  | `u` | Queue for unfollow (adds to `to_unfollow.txt`) |
  | `s` | Skip |
  | `q` | Quit (asks to confirm with `y`) |

---

## 📂 Outputs
- 📝 **.ig_whitelist.txt** → running “keep” list (lowercased, sorted, deduped).
- ❌ **to_unfollow.txt** → lines like `@username https://www.instagram.com/username/` (deduped).

---

## 💻 Requirements
- macOS with the default **zsh** shell.
- A web browser (Firefox, Chrome, Safari, etc.).
- Your Instagram data export (HTML format).

---

## 📥 Step 1 — Download your Instagram data
Instagram now routes exports through **Accounts Center**.

1. On your phone or desktop browser, open Instagram:  
   **Settings and privacy → Accounts Center → Your information and permissions → Download your information**.
2. Choose your Instagram account if asked.
3. Pick **Some of your information**, then select **Followers and following**.  
   📅 Use **All Time** for the date range.  
   📤 Delivery method: **Download to device**.  
   📄 Format: **HTML** (⚠️ not JSON).
4. Submit and wait for the email (takes minutes to hours).
5. Download the ZIP from the link you receive.

Inside the ZIP you’ll find:
```
instagram-<your_username>-connections/followers_and_following/
  ├─ following.html
  ├─ followers_1.html
  ├─ followers_2.html
  └─ ...
```

---

## 📂 Step 2 — Prepare a folder for ig-trim
1. Create a folder (e.g. `~/Desktop/ig-trim`).
2. Copy into it:
   - `following.html`
   - all `followers_*.html` files
3. Optionally, drop in an existing `.ig_whitelist.txt`.  
   (If not present, the script creates one.)
4. Save `ig-trim.zsh` into the same folder.

---

## ▶️ Step 3 — Run the script
```bash
cd ~/Desktop/ig-trim        # go to your folder
chmod +x ig-trim.zsh        # first time only
./ig-trim.zsh               # run it
```

---

## 👁️ What you’ll see
- A count of accounts you follow that don’t follow you back.
- For each account:
  ```
  [3/120] @someuser -> o:open&next O:open&stay k:keep u:queue s:skip q:quit
  ```
- Press a single key to act (no Enter).

---

## 🌐 Browser opening behavior
- Profiles open in the **background** so your terminal stays focused.
- Want a specific browser?  
  Set the `BROWSER` env variable:
  ```bash
  BROWSER="Firefox" ./ig-trim.zsh
  ```
- Otherwise, it tries Firefox by bundle ID, then falls back to your system default.

---

## 📦 After you finish
- ✅ **.ig_whitelist.txt** → updated with any `k` choices.
- ❌ **to_unfollow.txt** → updated with any `u` choices.

Re-run anytime; whitelisted accounts are skipped automatically.

---

## 💡 Tips & FAQ
- **Where do I find the files?**  
  In the downloaded ZIP under `followers_and_following/`.

- **Browser still steals focus?**  
  macOS might bring it forward *once* if it wasn’t already running. After that, tabs open in the background.

- **Keys need Enter?**  
  Make sure you’re running `./ig-trim.zsh` (latest version). If Hyper/VS Code is glitchy, try macOS Terminal.

- **Whitelist editing?**  
  Yep. One username per line, no `@`. Script cleans and dedupes automatically.

- **Only have `following.html`?**  
  Re-request your export and choose **Followers and following**.

- **Data safety?**  
  Everything runs **locally**. No uploads.

---

## ⚙️ Advanced options (optional)
Override default filenames via env vars:

```bash
IG_FOLLOWERS_GLOB='followers_2024_*.html' ./ig-trim.zsh
IG_WHITELIST_FILE='my_keep_list.txt' ./ig-trim.zsh
IG_OUTPUT_FILE='my_unfollows.txt' ./ig-trim.zsh
```

Defaults:
- `followers_*.html`
- `following.html`
- `.ig_whitelist.txt`
- `to_unfollow.txt`

---

## 🛠 Troubleshooting
- **Nothing to review?**  
  Ensure both `following.html` and all `followers_*.html` are present, from an **HTML** export.

- **Invalid key messages?**  
  Probably running an old script. Restart with the included `ig-trim.zsh`.

- **Permission denied?**  
  Run `chmod +x ig-trim.zsh` once.

---

## 🗂 Unfollow workflow suggestion
- Process `to_unfollow.txt` at your own pace.  
- Open in your editor, click links, unfollow in Instagram.  
- Keep it as a journal or clear lines as you go.

---

## ⚠️ Known limitations
- Relies on Instagram’s current export HTML. If they change it, parsing may break.
- Tested only on macOS + zsh.

---

## 📜 License
Personal use. No warranty. Use at your own risk.
