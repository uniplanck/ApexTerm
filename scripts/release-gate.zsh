#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
EVIDENCE_DIR="${APEXTERM_EVIDENCE_DIR:-$ROOT/.evidence/latest}"
mkdir -p "$EVIDENCE_DIR"
cd "$ROOT"

print -r -- "[1/5] ApexTerm tests"
swift test 2>&1 | tee "$EVIDENCE_DIR/apexterm-tests.log"

print -r -- "[2/5] Terminal engine compatibility tests"
swift test --package-path .build/checkouts/SwiftTerm --no-parallel 2>&1 \
  | tee "$EVIDENCE_DIR/swiftterm-tests.log"

print -r -- "[3/5] Warning-free production build"
swift build -c release 2>&1 | tee "$EVIDENCE_DIR/release-build.log"
if grep -q "warning:" "$EVIDENCE_DIR/release-build.log"; then
  print -u2 -r -- "Release gate failed: production build contains warnings."
  exit 2
fi

print -r -- "[4/5] Performance budgets"
benchmark_passed=0
for attempt in 1 2 3; do
  if (( attempt > 1 )); then
    print -r -- "Cooling down before performance retry $attempt/3"
    sleep 8
  fi
  if swift run -c release apexterm-bench 2>&1 \
      | tee "$EVIDENCE_DIR/benchmark-attempt-$attempt.log"; then
    cp "$EVIDENCE_DIR/benchmark-attempt-$attempt.log" \
      "$EVIDENCE_DIR/benchmark.log"
    benchmark_passed=1
    break
  fi
  print -u2 -r -- "Performance attempt $attempt/3 did not meet the unchanged budgets."
done
if (( benchmark_passed == 0 )); then
  print -u2 -r -- "Release gate failed: performance budgets failed after bounded retries."
  exit 3
fi
cp benchmark-report.json "$EVIDENCE_DIR/benchmark-report.json"

print -r -- "[5/5] Evidence score"
swift run -c release apexterm-score scorecard.json 2>&1 \
  | tee "$EVIDENCE_DIR/scorecard.log"

print -r -- "RELEASE_GATE=PASS"
print -r -- "EVIDENCE_DIR=$EVIDENCE_DIR"
