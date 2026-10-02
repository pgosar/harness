# Pre-presentation self-review checklist

Run through this before presenting any diff to Pranay.

## Pre-mortem (did I do this before starting?)
- [ ] What could go wrong here? What would failure look like?
- [ ] What environment values am I assuming? (verified, not from memory)
- [ ] If modes/flags exist: did I audit all settings that should follow them?

## Correctness
- [ ] Did I trace the full pipeline, not just the symptom layer?
- [ ] Did I read the producer AND the consumer together for generated values?
- [ ] Did I search for hooks/autocommands/plugins that bridge layers?
- [ ] For regressions: did I bisect to find the exact breaking change?

## Verification
- [ ] Did I run the repo's linters/tests on the changed files?
- [ ] Did I verify the change works (not just "looks right")? Show evidence.
- [ ] For visual changes: screenshot showing actual rendered result?
- [ ] For generated files: confirmed they landed where consumers read them?
- [ ] Did I run `~/workspace/harness/verify.sh`?

## Diff quality
- [ ] One logical change per commit?
- [ ] Commit message follows conventional commits?
- [ ] Decision rationale recorded for non-obvious choices?
- [ ] Would this make sense reviewing commit-by-commit?

## Adversarial review
- [ ] Did I re-read the diff as if someone else wrote it?
- [ ] Did I spawn a specialist review subagent with only the diff?
- [ ] Hunt specifically for my known failure modes (below).

## Failure modes (my known ones)
- [ ] Am I debugging state when I should be debugging flow?
- [ ] Am I piling a fix on top instead of rewinding? (2 failures = rewind)
- [ ] Am I claiming "verified" from a value check instead of behavioral proof?
- [ ] Did I assume an environment value instead of detecting it?
- [ ] Have I been debugging >30 min without progress? (time-box hit → switch approach)
- [ ] Is there a minimal repro? (if not, create one before fixing)

## Task lifecycle
- [ ] Did I use `task start` with goal and verifier?
- [ ] Did I record failures with `task fail`?
- [ ] Did I `task decide` based on evidence?

## Verification levels (all that apply)
- [ ] Static: linters pass (luacheck, stylua, shellcheck, py_compile)
- [ ] Behavioral: exercised the changed code path
  - Neovim Lua: `nvim --headless -c "qa!"` starts cleanly
  - Shell: ran with test inputs (not just bash -n)
  - Python: imported the module (not just py_compile)
  - Generated configs: verified consumer reads them
- [ ] Visual: screenshot shows actual rendered result
- [ ] Lint-clean is NOT sufficient — behavioral evidence required
