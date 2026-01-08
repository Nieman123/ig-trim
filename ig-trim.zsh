#!/usr/bin/env zsh

# Re-exec with zsh if invoked via another shell.
if [[ -z "${ZSH_VERSION:-}" ]]; then
  if command -v zsh >/dev/null 2>&1; then
    exec zsh "$0" "$@"
  fi
  echo "Error: zsh is required to run this script." >&2
  exit 1
fi

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
touch "$whitelist_file" 2>/dev/null || :
if [[ -s "$whitelist_file" ]]; then
  # Normalize: lower-case and unique (BSD awk: no "--")
  tmpw=$(mktemp -t igtrim-wl.XXXXXX)
  awk '{print tolower($0)}' "$whitelist_file" | sed '/^$/d' | sort -u >| "$tmpw" && mv "$tmpw" "$whitelist_file"
fi

# Open a dedicated TTY for prompts/keys, with fallback to stdio
if ! exec 3<>/dev/tty 2>/dev/null; then
  exec 3<&0 3>&1
fi

# Colors for TTY output on FD 3
if [[ -t 3 ]]; then
  R=$'\033[0m'     # reset
  BLD=$'\033[1m'   # bold
  DIM=$'\033[2m'   # dim
  RED=$'\033[31m'
  GRN=$'\033[32m'
  YLW=$'\033[33m'
  BLU=$'\033[34m'
  MAG=$'\033[35m'
  CYN=$'\033[36m'
else
  R="" BLD="" DIM="" RED="" GRN="" YLW="" BLU="" MAG="" CYN=""
fi

# Debug helper (enable with IG_DEBUG=1)
dbg() { [[ -n "${IG_DEBUG:-}" ]] && print -u3 -- "${DIM}$*${R}"; }

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
  local msg="$1" key=""
  print -n -u3 -- "$msg"
  local savein
  exec {savein}<&0
  exec 0<&3
  IFS= read -s -k 1 key || key=""
  exec 0<&$savein
  exec {savein}<&-
  print -u3 ""
  drain_tty
  if [[ -z "${key:-}" ]]; then
    reply="s"
  elif [[ "$key" == "O" ]]; then
    reply="O"
  else
    reply="${key:l}"
  fi
}

confirm_quit() {
  local ans=""
  print -n -u3 -- "${YLW}Quit?${R} [y/N]: "
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

# Persist a kept username immediately into the whitelist (lowercase, unique)
persist_keep_user() {
  local name="${1:l}"
  # Append then normalize + uniq
  print -- "$name" >>| "$whitelist_file"
  local tmpw
  tmpw=$(mktemp -t igtrim-wl.XXXXXX) || return
  awk '{print tolower($0)}' "$whitelist_file" | sed '/^$/d' | sort -u >| "$tmpw" && mv "$tmpw" "$whitelist_file"
}

# Extract usernames from given files; emits one lowercase username per line
_collect_usernames() {
  local -a files=()
  for f in "$@"; do [[ -r "$f" ]] && files+="$f"; done
  (( ${#files} )) || return 0

  {
    # title="username"
    grep -aEho 'title="[A-Za-z0-9._]+"' "$files[@]" 2>/dev/null | sed -E 's/.*title="([A-Za-z0-9._]+)".*/\1/'
    # href="/username/"
    grep -aEho 'href="/[A-Za-z0-9._]+/"' "$files[@]" 2>/dev/null | sed -E 's#.*href="/([A-Za-z0-9._]+)/".*#\1#'
    # Absolute URL https://www.instagram.com/_u/username or .../username
    grep -aEho 'https?://(www\.)?instagram\.com/[A-Za-z0-9._/?=-]+' "$files[@]" 2>/dev/null | \
      sed -E 's#https?://(www\.)?instagram\.com/##; s#^_u/##; s#[/?].*$##'
  } | awk '{print tolower($0)}' | \
      grep -avE '^(explore|accounts|about|privacy|terms|directory|stories|create|challenge|web|p|tv|reels|about|press|blog|legal|topics|changelog)$' | \
      sed '/^$/d' | sort -u
}

# Load source data
if [[ ! -r "$following_file" ]]; then
  print -u3 -- "${RED}following file not found:${R} $following_file"
  exec 3<&-
  exit 1
fi

typeset -a following_list followers_list
following_list=()
followers_list=()

while IFS= read -r u; do following_list+="$u"; done < <(_collect_usernames "$following_file")
dbg "following count: ${#following_list[@]}"

# Expand followers glob; OK if none
typeset -a followers_files
followers_files=($~followers_glob(N))
if (( ${#followers_files} )); then
  while IFS= read -r u; do followers_list+="$u"; done < <(_collect_usernames "${followers_files[@]}")
fi
dbg "followers count: ${#followers_list[@]} from ${#followers_files[@]} file(s)"

# Load whitelist
typeset -a persisted_whitelist
persisted_whitelist=()
if [[ -r "$whitelist_file" ]]; then
  while IFS= read -r u; do [[ -n "$u" ]] && persisted_whitelist+="$u"; done < "$whitelist_file"
fi
dbg "whitelist count: ${#persisted_whitelist[@]}"

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
dbg "candidates count: ${#candidates[@]}"

if (( ${#candidates} == 0 )); then
  print -u3 -- "${GRN}Nothing to review. You're all good!${R}"
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

print -u3 -- "${CYN}Reviewing ${#users} profiles${R}. Keys: ${CYN}o/O/k/u/s/q${R}"

# Main loop (zsh arrays are 1-based)
typeset -i idx=1 total=${#users}
while (( idx <= total )); do
  user=${users[idx]}
  url="https://www.instagram.com/${user}/"
  while true; do
    print -u3 -- "${DIM}[${idx}/${total}]${R} ${MAG}@${user}${R} -> ${CYN}o${R}:open&next ${CYN}O${R}:open&stay ${GRN}k${R}:keep ${YLW}u${R}:queue ${BLU}s${R}:skip ${YLW}q${R}:quit"
    prompt_key "${GRN}> ${R}"
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
        persist_keep_user "$user"
        print -u3 -- "${GRN}+ saved to whitelist${R}"
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
        print -u3 -- "${RED}Invalid key.${R} Use ${CYN}o/O${R}/${GRN}k${R}/${YLW}u${R}/${BLU}s${R}/${YLW}q${R}."
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
  awk '{print tolower($0)}' "$whitelist_file" "$sess_keep_tmp" | sed '/^$/d' | sort -u >| "$tmpw" && mv "$tmpw" "$whitelist_file"
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

# (dbg() moved near top with color support)

# Cleanup
rm -f -- "$users_tmp" "$sess_keep_tmp" "$sess_unf_tmp" 2>/dev/null || :

exit 0
