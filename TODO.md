# Dispatch — TODO

## Hook UI Display

### Try stdout output
- Currently using `/dev/tty` which conflicts with CC's TUI (shows in input field, weird formatting)
- stdout injects into Claude's context — CC displays it as part of Claude's response
- Only fires on confirmed shifts so context cost is low (~50-100 tokens per detection)
- Tradeoff: recommendations appear inside Claude's reply, not as a pre-response banner
- **Try:** output recommendations JSON or formatted text to stdout instead of /dev/tty and see how CC renders it

### Explore pending_notification file approach
- Hook writes shift data to `~/.claude/skill-router/pending_notification.json` on detection
- CLAUDE.md instruction tells Claude to check for the file at the start of each response, display it, then delete it
- Claude surfaces recommendations naturally in its reply
- Pros: works in CLI, TUI, and desktop CC — no /dev/tty needed
- Cons: becomes part of Claude's response, not a separate UI element; requires CLAUDE.md entry on every user's install
- **Explore:** what the CLAUDE.md instruction would look like, how to auto-add it via install.sh

## Anthropic Feature Request
- File a GitHub issue / feedback with Anthropic requesting a proper hook notification channel
- Current hook API gives hooks stdout (→ Claude context), stderr (→ suppressed), /dev/tty (→ raw terminal, broken in TUI/desktop)
- Request: structured hook response format e.g. `{"notify": "..."}` that CC renders in a designated UI area
- Or: a hook output channel that renders cleanly above Claude's response in all CC modes (CLI, TUI, desktop)
- Dispatch is a concrete example of a hook that needs to show UI to users

## Roadmap (from CLAUDE.md)
- [ ] End-to-end live session testing + screen recording for promotion
- [ ] `/dispatch status` command
- [ ] skills.sh distribution
