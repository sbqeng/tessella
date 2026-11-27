#!/usr/bin/env bash
# Run the Mosaic Market suite and write the reports Tessella reads.
#
#   ./run_suite.sh                  the whole suite
#   ./run_suite.sh tests/api        any pytest arguments, passed through
#
# Writes:
#   reports/allure-report/    generated Allure report, with history/trend carried across runs
#   reports/junit.xml         JUnit XML for CI
#   test-results/             a Playwright trace per UI test (flows for probing), screenshots
#   logs/app.log              the shop's request log, with tracebacks
set -uo pipefail
cd "$(dirname "$0")"

rm -rf reports/allure-results test-results
mkdir -p reports

pytest \
  --alluredir=reports/allure-results \
  --junitxml=reports/junit.xml \
  --tracing on --output test-results \
  "$@"
status=$?

# Carry history forward so Allure can chart flaky rate/trend across runs.
if [ -d reports/allure-report/history ]; then
  cp -r reports/allure-report/history reports/allure-results/
fi
allure generate reports/allure-results -o reports/allure-report --clean

echo
if [ "$status" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests failed."
  echo "Next: tessella triage    # reads reports/allure-report, see tessella.yaml"
fi
# The reports are what matter here, so the script itself does not fail.
exit 0
