# Summary

<!-- What does this change, and why? -->

## Device / component

<!-- Feberis, geotag, galaxy-s10 scripts, flash scripts, CI, docs... -->

## Testing

<!-- Which checks did you run? Paste relevant results. -->

- [ ] Feberis `python3 -m unittest discover` + native C++ tests
- [ ] `python3 -m unittest discover -s tests` and `-s galaxy-s10-nethunter/tests`
- [ ] `shellcheck -S warning` on changed scripts
- [ ] `pio run` (if firmware changed)
- [ ] markdownlint (if docs changed)

## Checklist

- [ ] No secrets, credentials, or captured data in the diff
- [ ] Commit messages are imperative with no AI attribution trailers
- [ ] No submodule pin bumped to an unpushed or unverified commit
- [ ] `flipper/Momentum-Firmware` is untouched (upstream AI policy)
- [ ] Change is for authorized security testing only
