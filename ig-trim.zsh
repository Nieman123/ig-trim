#!/bin/zsh
# Instagram follower/following triage (zsh, no-args, single-key, open-and-advance)

emulate -L zsh
set -u
setopt pipefail

# Defaults
WHITELIST_FILE=".ig_whitelist.txt"
TO_UNFOLLOW_OUT="to_unfollow.txt"
FOLLOWING_FILE="following.html"

# Gather followers files
setopt NULL_GLOB
FOLLOWER_FILES=(followers_*.html)
unsetopt NULL_GLOB

die() { print -u2 "Error: $*"; exit 1; }

# Validate files
(( ${#FOLLOWER_FILES[@]} > 0 )) || die "Couldn't find any followers_*.html in the current folder."
[[ -f "$FOLLOWING_FILE" ]] || die "Couldn't find $FOLLOWING_FILE in the current folder."

# Extract usernames from IG export HTML
extract_usernames() {
  local file="$1"
  grep -oE 'https?://(www\.)?instagram\.com/[^" ?#]+' "$file" \
  | sed -E 's#https?://(www\.)?instagram\.com/##; s#/$##' \
  | awk -F'/' '{print $1}' \
  | grep -E '^[A-Za-z0-9._]+' \
  | grep -vE '^(accounts|explore|reels|p|tv|about|press|blog|legal|privacy|directory|topics|changelog)$' \
  | LC_ALL=C sort -u
}

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir" 2>/dev/null || true; }
trap cleanup EXIT

followers_all="$tmpdir/followers.txt"
: > "$followers_all"
for f in "${FOLLOWER_FILES[@]}"; do
  extract_usernames "$f" >> "$followers_all"
done
LC_ALL=C sort -u "$followers_all" -o "$followers_all"

following_all="$tmpdir/following.txt"
extract_usernames "$FOLLOWING_FILE" > "$following_all"
LC_ALL=C sort -u "$following_all" -o "$following_all"

# Ensure whitelist exists but don't clobber it
touch "$WHITELIST_FILE"
LC_ALL=C sort -u "$WHITELIST_FILE" -o "$WHITELIST_FILE"

# Compute following-not-followers, then minus whitelist
LC_ALL=C comm -23 "$following_all" "$followers_all" > "$tmpdir/following_not_followers.txt"
LC_ALL=C comm -23 "$tmpdir/following_not_followers.txt" "$WHITELIST_FILE" > "$tmpdir/nonfollowers.txt"

count=$(wc -l < "$tmpdir/nonfollowers.txt" | tr -d '[:space:]')
print "Found $count accounts you follow that don't follow back (excluding whitelist).\n"
print "Controls: [o]=open & next  [O]=open & stay  [k]=keep  [u]=unfollow  [s]=skip  [q]=quit\n"

# Open dedicated FDs:
#  - 3: real TTY for prompts (read+write)
#  - 4: the list of users to process (read-only)
if ! exec 3<>/dev/tty; then
  die "Couldn't open /dev/tty. Run from Terminal or iTerm (not a headless runner)."
fi
if ! exec 4<"$tmpdir/nonfollowers.txt"; then
  die "Couldn't open list of users."
fi

session_whitelist="$tmpdir/session_whitelist.txt"
session_unfollow="$tmpdir/session_unfollow.txt"
: > "$session_whitelist"
: > "$session_unfollow"

# Single-key prompt from TTY (no Enter). Returns lowercase char except 'O' kept as uppercase.
prompt_key() {
  local msg="$1" key=""
  # print prompt
  print -n -u3 -- "$msg"
  # read exactly one keypress
  if ! IFS= read -k 1 -u3 key; then
    # if read fails, default to skip
    print "s"
    return
  fi
  # echo the key so user sees it
  print -u3 ""
  # keep uppercase O special; everything else lowercased
  if [[ "$key" == "O" ]]; then
    print "O"
  else
    print "${key:l}"
  fi
}

confirm_quit() {
  local key
  print -u3 "Quit? [y/N]: "
  if IFS= read -k 1 -u3 key; then
    print -u3 ""
    [[ "${key:l}" == "y" ]] && return 0
  fi
  return 1
}

open_url() {
  local url="$1"
  # Honor $BROWSER first (e.g., "Firefox", "Google Chrome")
  if [[ -n "${BROWSER:-}" ]]; then
    open -a "$BROWSER" "$url" 2>/dev/null && return
  fi
  # Prefer Firefox’s bundle id; fallback to default
  open -b org.mozilla.firefox "$url" 2>/dev/null || open "$url"
}

i=0
# Read users from FD 4 (not via redirection), so stdin stays free
while IFS= read -r -u4 user; do
  (( i++ ))
  url="https://www.instagram.com/${user}"
  print "[$i/$count] @$user  ->  $url"
  while true; do
    key="$(prompt_key "(o/O/k/u/s/q): ")"
    case "$key" in
      o)  # open and advance
        open_url "$url" || print "  ! couldn't open browser"
        # advance by breaking inner loop
        break
        ;;
      O)  # open and stay on this user
        open_url "$url" || print "  ! couldn't open browser"
        # stay in inner loop
        ;;
      k)
        print "$user" >> "$session_whitelist"
        print "  + whitelisted @$user"
        break
        ;;
      u)
        printf "%s %s\n" "$user" "$url" >> "$session_unfollow"
        print "  + queued to unfollow @$user"
        break
        ;;
      s)
        print "  ~ skipped @$user"
        break
        ;;
      q)
        if confirm_quit; then
          print "Quitting early. Saving progress..."
          # close FDs so cleanup still runs
          exec 3<&-
          exec 4<&-
          # do outputs below after breaking out
          goto_finish=1
          break 2
        fi
        ;;
      *)
        print "Invalid key. Use o/O/k/u/s/q."
        ;;
    esac
  done
  print
done

# Close FDs
exec 3<&-
exec 4<&-

# Merge whitelist updates
if [[ -s "$session_whitelist" ]]; then
  cat "$session_whitelist" >> "$WHITELIST_FILE"
  LC_ALL=C sort -u "$WHITELIST_FILE" -o "$WHITELIST_FILE"
fi

# Write to_unfollow with unique usernames and links
if [[ -s "$session_unfollow" ]]; then
  awk '!seen[$1]++' "$session_unfollow" > "$tmpdir/unfollow_unique.txt"
  awk '{printf("@%s %s\n", $1, $2)}' "$tmpdir/unfollow_unique.txt" > "$TO_UNFOLLOW_OUT"
fi

print "Done."
print "Whitelist saved to: $WHITELIST_FILE"
if [[ -s "$TO_UNFOLLOW_OUT" ]]; then
  print "To-unfollow list saved to: $TO_UNFOLLOW_OUT"
else
  print "No accounts marked for unfollow this run."
fi