#!/bin/zsh
# Instagram follower/following triage (zsh, no-args, stable I/O)

emulate -L zsh
# Don't use -e here; it can exit on benign nonzero statuses in loops
# set -e
# Safer defaults:
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
print "Controls: [o]pen  [k]eep (whitelist)  [u]nfollow  [s]kip  [q]uit\n"

# Open dedicated FDs:
#  - 3: real TTY for user input
#  - 4: the list of users to process
# 3: TTY read+write for prompts, 4: read-only list of users
if ! exec 3<>/dev/tty; then
  die "Couldn't open /dev/tty. Run from Terminal (not a headless runner)."
fi
if ! exec 4<"$tmpdir/nonfollowers.txt"; then
  die "Couldn't open list of users."
fi

session_whitelist="$tmpdir/session_whitelist.txt"
session_unfollow="$tmpdir/session_unfollow.txt"
: > "$session_whitelist"
: > "$session_unfollow"

prompt_choice() {
  local msg="$1" choice=""
  print -n -u3 -- "$msg"
  IFS= read -r -u3 choice || true
  choice="$(printf "%s" "$choice" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$choice" ]] && print "s" || print "$choice"
}

open_url() {
  local url="$1"

  # If user set $BROWSER, try that first (e.g., "Firefox", "Google Chrome")
  if [[ -n "${BROWSER:-}" ]]; then
    open -a "$BROWSER" "$url" 2>/dev/null && return
  fi

  # Prefer Firefox if present, otherwise fall back to system default
  open -b org.mozilla.firefox "$url" 2>/dev/null || open "$url"
}

i=0
# Read users from FD 4 (not via redirection), so stdin stays free
while IFS= read -r -u4 user; do
  (( i++ ))
  url="https://www.instagram.com/${user}"
  print "[$i/$count] @$user  ->  $url"
  while true; do
    choice="$(prompt_choice "(o/k/u/s/q): ")"
    case "$choice" in
      o)
        open_url "$url" || print "  ! couldn't open browser"
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
        print "Quitting early. Saving progress..."
        break 2
        ;;
      *)
        print "Invalid choice. Use o/k/u/s/q."
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