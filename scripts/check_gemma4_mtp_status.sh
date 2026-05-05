#!/usr/bin/env zsh
# Gemma 4 MTP adoption watcher.
#
# Hard blockers checked:
#   1. mlx-swift-lm ChatSession gains a draft-model parameter
#      (low-level generate()/generateTokens() spec-decode already shipped in 3.31.3 via PR #173;
#       ChatSession integration tracked in issue #181).
#   2. mlx-community publishes MLX-format Gemma 4 MTP drafter weights.
#
# Informational signals (printed but not gating):
#   - Drafter weights on the google/ HF org in any format.
#
# Spec: docs/superpowers/specs/2026-05-05-gemma-4-mtp-watch.md
#
# Exit 0 when both hard blockers are green ("READY TO ADOPT"), exit 1 otherwise.

set -u
setopt PIPE_FAIL

print_section() {
  print "\n=== $1 ==="
}

# 1. mlx-swift-lm ChatSession spec-decode support.
#    Canonical signal is issue #181's state. When that closes, ChatSession
#    has draft-model support and we can integrate.
print_section "mlx-swift-lm ChatSession spec-decode (issue #181)"
chat_hit=""
issue_json="$(curl -fsSL 'https://api.github.com/repos/ml-explore/mlx-swift-lm/issues/181' 2>/dev/null || true)"
if [[ -z "$issue_json" ]]; then
  print "  could not fetch issue #181 (network or rate limit)"
else
  state="$(print -r -- "$issue_json" | grep -m1 '"state"' | sed 's/.*: "//;s/".*//')"
  print "  issue #181 state: ${state:-unknown}"
  if [[ "$state" == "closed" ]]; then
    chat_hit="closed"
  fi
fi

# 2. mlx-community Gemma 4 drafter weights.
print_section "mlx-community Gemma 4 drafter repos"
hf_hits=""
hf_json="$(curl -fsSL 'https://huggingface.co/api/models?author=mlx-community&search=gemma-4&limit=100' 2>/dev/null || true)"
if [[ -z "$hf_json" ]]; then
  print "  could not fetch HF model list (network or rate limit)"
else
  hf_hits="$(print -r -- "$hf_json" \
    | grep -oE '"id":"mlx-community/gemma-4[^"]*"' \
    | grep -iE 'mtp|draft|spec' || true)"
  if [[ -n "$hf_hits" ]]; then
    print "  HIT: drafter-style repos found on mlx-community:"
    print -r -- "$hf_hits" | sed 's/^/    /'
  else
    repo_count="$(print -r -- "$hf_json" | grep -oE '"id":"mlx-community/gemma-4[^"]*"' | wc -l | tr -d ' ')"
    print "  no drafter / mtp / spec repos found (scanned $repo_count gemma-4 repos)"
  fi
fi

# Informational: google/ HF org drafter publication.
print_section "google/ HF org Gemma 4 drafter repos (informational only)"
g_json="$(curl -fsSL 'https://huggingface.co/api/models?author=google&search=gemma-4&limit=100' 2>/dev/null || true)"
if [[ -n "$g_json" ]]; then
  g_hits="$(print -r -- "$g_json" \
    | grep -oE '"id":"google/gemma-4[^"]*"' \
    | grep -iE 'mtp|draft|spec' || true)"
  if [[ -n "$g_hits" ]]; then
    print "  google/ org has drafter-style repos (not yet in MLX format if mlx-community has none):"
    print -r -- "$g_hits" | sed 's/^/    /'
  else
    print "  no drafter / mtp / spec repos on google/ org yet"
  fi
fi

# Verdict.
print_section "Verdict"
if [[ -n "$chat_hit" && -n "$hf_hits" ]]; then
  print "  READY TO ADOPT"
  print "  Open docs/superpowers/specs/2026-05-05-gemma-4-mtp-watch.md and execute the integration sketch."
  exit 0
else
  print "  STILL BLOCKED"
  [[ -z "$chat_hit" ]] && print "    - waiting on: ChatSession spec-decode support (mlx-swift-lm issue #181)"
  [[ -z "$hf_hits" ]]  && print "    - waiting on: mlx-community Gemma 4 MTP drafter weights"
  exit 1
fi
