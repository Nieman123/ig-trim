#!/usr/bin/env zsh

# ig-trim: Review who you follow but doesn’t follow you back
# - No args UX with defaults
# - Single-key controls (no Enter), robust TTY handling
# - Background tab opening (no focus steal)
# - Keeps whitelist and unfollow queue de-duplicated

set -u
setopt pipefail

# Defaults (override via env if desired)
followers_glob=${IG_FOLLOWERS_GLOB:-followers_*.html}
following_file=${IG_FOLLOWING_FILE:-following.html}
whitelist_file=${IG_WHITELIST_FILE:-.ig_whitelist.txt}
out_file=${IG_OUTPUT_FILE:-to_unfollow.txt}

LC_ALL=C

# Ensure whitelist exists and is unique early
touch -- "$whitelist_file" 2>/dev/null || :
if [[ -s "$whitelist_file" ]]; then
  # Normalize: lower-case and unique
  tmpw=$(mktemp -t igtrim-wl.XXXXXX)
  awk '{print tolower($0)}' -- "$whitelist_file" | sed '/^$/d' | sort -u >| "$tmpw" && mv "$tmpw" "$whitelist_file"
fi

# Open a dedicated TTY for prompts/keys, with fallback to stdio
if ! exec 3<>/dev/tty 2>/dev/null; then
  exec 3<&0 3>&1
fi

# Drain any pending CR/LF from TTY so prompts don’t get polluted
drain_tty() {
  local dump
  while IFS= read -t 0 -k 1 -u3 dump 2>/dev/null; do :; done
  sleep 0.02 2>/dev/null || :
  while IFS= read -t 0 -k 1 -u3 dump 2>/dev/null; do :; done
}

# Read single key (no Enter) from FD 3. Echo newline. Drain residuals.
# Returns: key in $reply (zsh builtin), lowercased except capital O preserved.
prompt_key() {
  local msg="$1" key
  print -n -u3 -- "$msg"
  local savein
  exec {savein}<&0
  exec 0<&3
  IFS= read -s -k 1 key || key=""
  exec 0<&$savein
  exec {savein}<&-
  print -u3 ""
  drain_tty
  if [[ -z "$key" ]]; then
    reply="s"
  elif [[ "$key" == "O" ]]; then
    reply="O"
  else
    reply="${key:l}"
  fi
}

confirm_quit() {
  local ans
  print -n -u3 -- "Quit? [y/N]: "
  local savein
  exec {savein}<&0
  exec 0<&3
  IFS= read -s -k 1 ans || ans=""
  exec 0<&$savein
  exec {savein}<&-
  print -u3 ""
  drain_tty
  [[ "${ans:l}" == "y" ]]
}

open_url() {
  local url="$1"
  if [[ -n "${BROWSER:-}" ]]; then
    open -g -a "$BROWSER" "$url" 2>/dev/null && return
  fi
  open -g -b org.mozilla.firefox "$url" 2>/dev/null || open -g "$url"
}

# Extract usernames from given files; emits one lowercase username per line
_collect_usernames() {
  local -a files=()
  for f in "$@"; do [[ -r "$f" ]] && files+="$f"; done
  (( ${#files} )) || return 0

  {
    # Common: title="username"
    grep -aEho 'title="[A-Za-z0-9._]+"' -- "$files[@]" 2>/dev/null | \
      sed -E 's/.*title="([A-Za-z0-9._]+)".*/\1/'
    # Fallback: href="/username/" (single-segment)
    grep -aEho 'href="/[A-Za-z0-9._]+/"' -- "$files[@]" 2>/dev/null | \
      sed -E 's#.*href="/([A-Za-z0-9._]+)/".*#\1#'
  } | \
  awk '{print tolower($0)}' | \
  grep -avE '^(explore|accounts|about|privacy|terms|directory|stories|create|challenge|web|p)$' | \
  sed '/^$/d' | sort -u
}

# Load source data
if [[ ! -r "$following_file" ]]; then
  print -u3 -- "following file not found: $following_file"
  exec 3<&-
  exit 1
fi

typeset -a following_list followers_list
following_list=()
followers_list=()

while IFS= read -r u; do following_list+="$u"; done < <(_collect_usernames "$following_file")

# Expand followers glob; OK if none
typeset -a followers_files
followers_files=($~followers_glob(N))
if (( ${#followers_files} )); then
  while IFS= read -r u; do followers_list+="$u"; done < <(_collect_usernames "${followers_files[@]}")
fi

# Load whitelist
typeset -a persisted_whitelist
persisted_whitelist=()
if [[ -r "$whitelist_file" ]]; then
  while IFS= read -r u; do [[ -n "$u" ]] && persisted_whitelist+="$u"; done < "$whitelist_file"
fi

# Build sets
typeset -A set_following set_followers set_whitelist
set_following=()
set_followers=()
set_whitelist=()
for u in "$following_list[@]"; do set_following[$u]=1; done
for u in "$followers_list[@]"; do set_followers[$u]=1; done
for u in "$persisted_whitelist[@]"; do set_whitelist[$u]=1; done

# Compute candidates: following - followers - whitelist (preserve following order)
typeset -a candidates
candidates=()
for u in "$following_list[@]"; do
  [[ -n ${set_followers[$u]:-} ]] && continue
  [[ -n ${set_whitelist[$u]:-} ]] && continue
  candidates+="$u"
done

if (( ${#candidates} == 0 )); then
  print -u3 -- "Nothing to review. You're all good!"
  exec 3<&-
  exit 0
fi

# Temp files for session state
users_tmp=$(mktemp -t igtrim-users.XXXXXX)
sess_keep_tmp=$(mktemp -t igtrim-keep.XXXXXX)
sess_unf_tmp=$(mktemp -t igtrim-unf.XXXXXX)

# Save candidate list and expose on FD 4 (read-only)
printf "%s\n" "${candidates[@]}" >| "$users_tmp"
exec 4<"$users_tmp"

# Load users into memory (we keep FD 4 open as requested)
typeset -a users
users=()
while IFS= read -r -u4 u; do users+="$u"; done

print -u3 -- "Reviewing ${#users} profiles. Keys: o/O/k/u/s/q"

# Main loop
typeset -i idx=0 total=${#users}
while (( idx < total )); do
  user=${users[idx]}
  url="https://www.instagram.com/${user}/"
  while true; do
    print -u3 -- "[$((idx+1))/$total] @${user} -> o:open&next O:open&stay k:keep u:queue s:skip q:quit"
    prompt_key "> "
    key="$reply"
    case "$key" in
      $'\r'|$'\n'|$'\t')
        # Ignore stray whitespace keys silently
        ;;
      o)
        open_url "$url"
        (( idx++ ))
        break
        ;;
      O)
        open_url "$url"
        # stay on same user
        ;;
      k)
        print -- "$user" >>| "$sess_keep_tmp"
        (( idx++ ))
        break
        ;;
      u)
        print -- "@${user} ${url}" >>| "$sess_unf_tmp"
        (( idx++ ))
        break
        ;;
      s)
        (( idx++ ))
        break
        ;;
      q)
        if confirm_quit; then
          break 2  # exit both loops
        fi
        ;;
      *)
        print -u3 -- "Invalid key. Use o/O/k/u/s/q."
        ;;
    esac
  done
done

# Close interactive FDs before writing outputs
exec 3<&-
exec 4<&-

# Merge session keep into persistent whitelist (lowercase, unique)
if [[ -s "$sess_keep_tmp" ]]; then
  tmpw=$(mktemp -t igtrim-wl.XXXXXX)
  awk '{print tolower($0)}' -- "$whitelist_file" "$sess_keep_tmp" | sed '/^$/d' | sort -u >| "$tmpw" && mv "$tmpw" "$whitelist_file"
fi

# Merge session unfollow into queue, de-duping by username token
if [[ -s "$sess_unf_tmp" ]]; then
  tmpu=$(mktemp -t igtrim-unf.XXXXXX)
  if [[ -s "$out_file" ]]; then
    awk '!seen[$1]++' "$out_file" "$sess_unf_tmp" >| "$tmpu"
  else
    awk '!seen[$1]++' "$sess_unf_tmp" >| "$tmpu"
  fi
  mv "$tmpu" "$out_file"
fi

# Cleanup
rm -f -- "$users_tmp" "$sess_keep_tmp" "$sess_unf_tmp" 2>/dev/null || :

exit 0
