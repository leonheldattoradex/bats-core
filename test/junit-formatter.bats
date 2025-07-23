#!/usr/bin/env bats

load test_helper
fixtures junit-formatter

FLOAT_REGEX='[0-9]+(\.[0-9]+)?'
TIMESTAMP_REGEX='[0-9]+-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]'
MS_REGEX='( in [0-9]+ms)?'
ESCAPED_CHARS='&quot;&#39;&lt;&gt;&amp; \(0x1b\)'

@test "junit formatter with skipped test does not fail" {
  reentrant_run bats --formatter junit "$FIXTURE_ROOT/skipped.bats"
  echo "$output"
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == '<?xml version="1.0" encoding="UTF-8"?>' ]]
  [[ ${lines[1]} =~ \<testsuites\ time=\"${FLOAT_REGEX}\"\> ]]

  TESTSUITE_REGEX="<testsuite name=\"skipped.bats\" tests=\"2\" failures=\"0\" errors=\"0\" skipped=\"2\" time=\"$FLOAT_REGEX\" timestamp=\"$TIMESTAMP_REGEX\" hostname=\".*\">"
  echo "TESTSUITE_REGEX='$TESTSUITE_REGEX'"
  [[ "${lines[2]}" =~ $TESTSUITE_REGEX ]]

  TESTCASE_REGEX="<testcase classname=\"skipped.bats\" name=\"a skipped test( in [0-9]+ms)?\" time=\"$FLOAT_REGEX\">"
  [[ "${lines[3]}" =~ $TESTCASE_REGEX ]]

  [[ "${lines[4]}" == *"<skipped></skipped>"* ]]
  [[ "${lines[5]}" == *"</testcase>"* ]]

  TESTCASE_REGEX="<testcase classname=\"skipped.bats\" name=\"a skipped test with a reason( in [0-9]+ms)?\" time=\"$FLOAT_REGEX\">"
  [[ "${lines[6]}" =~ $TESTCASE_REGEX ]]
  [[ "${lines[7]}" == *"<skipped>a reason</skipped>"* ]]
  [[ "${lines[8]}" == *"</testcase>"* ]]

  [[ "${lines[9]}" == *"</testsuite>"* ]]
  [[ "${lines[10]}" == *"</testsuites>"* ]]
}

@test "junit formatter: escapes xml special chars" {
  TEST_FILE_NAME="xml-escape.bats"
  TEST_FILE_PATH="$FIXTURE_ROOT/$TEST_FILE_NAME"
  reentrant_run bats --formatter junit "$TEST_FILE_PATH"

  echo "$output"

  for i in "${!lines[@]}"; do echo "$i: ${lines[$i]}"; done

  [[ ${lines[0]} =~ \<\?xml\ version=\"1\.0\"\ encoding=\"UTF-8\"\?\> ]]
  [[ ${lines[2]} =~ \<testsuite\ name=\"$TEST_FILE_NAME\".*tests=\"3\".*failures=\"1\".*errors=\"0\".*skipped=\"1\".*time=\"${FLOAT_REGEX}\".*timestamp=\"${TIMESTAMP_REGEX}\".*\> ]]
  [[ ${lines[3]} =~ \<testcase.*name=\"Successful\ test\ with\ escape\ characters:\ ${ESCAPED_CHARS}${MS_REGEX}\".*/\> ]]
  [[ ${lines[4]} =~ \<testcase.*name=\"Failed\ test\ with\ escape\ characters:\ ${ESCAPED_CHARS}${MS_REGEX}\".*\> ]]
  [[ $output == *'<failure type="failure">'* ]]
  [[ $output == *"in test file "*"$TEST_FILE_NAME, line 6)"* ]]
  [[ ${lines[9]} =~ \<testcase.*name=\"Skipped\ test\ with\ escape\ characters:\ ${ESCAPED_CHARS}${MS_REGEX}\".*\> ]]
  [[ ${lines[10]} == *"skipped>&quot;&#39;&lt;&gt;&amp;</skipped>"* ]]
}

@test "junit formatter: test suites" {
  reentrant_run bats --formatter junit "$FIXTURE_ROOT/suite/"
  echo "$output"

  [[ "${lines[0]}" == '<?xml version="1.0" encoding="UTF-8"?>' ]]
  [[ "${lines[1]}" == *"<testsuites "* ]]
  [[ "${lines[2]}" == *"<testsuite name=\"file1.bats\""* ]]
  [[ "${lines[3]}" == *"<testcase "* ]]
  [[ "${lines[4]}" == *"</testsuite>"* ]]
  [[ "${lines[5]}" == *"<testsuite name=\"file2.bats\""* ]]
  [[ "${lines[6]}" == *"<testcase"* ]]
  [[ "${lines[7]}" == *"</testsuite>"* ]]
  [[ "${lines[8]}" == *"</testsuites>"* ]]
}

@test "junit formatter: test suites relative path" {
  cd "$FIXTURE_ROOT"
  reentrant_run bats --formatter junit "suite/"
  echo "$output"

  [[ "${lines[0]}" == '<?xml version="1.0" encoding="UTF-8"?>' ]]
  [[ "${lines[1]}" == *"<testsuites "* ]]
  [[ "${lines[2]}" == *"<testsuite name=\"file1.bats\""* ]]
  [[ "${lines[3]}" == *"<testcase "* ]]
  [[ "${lines[4]}" == *"</testsuite>"* ]]
  [[ "${lines[5]}" == *"<testsuite name=\"file2.bats\""* ]]
  [[ "${lines[6]}" == *"<testcase"* ]]
  [[ "${lines[7]}" == *"</testsuite>"* ]]
  [[ "${lines[8]}" == *"</testsuites>"* ]]
}

@test "junit formatter: files with the same name are distinguishable" {
  reentrant_run bats --formatter junit -r "$FIXTURE_ROOT/duplicate/"
  echo "$output"

  [[ "${lines[2]}" == *"<testsuite name=\"first/file1.bats\""* ]]
  [[ "${lines[5]}" == *"<testsuite name=\"second/file1.bats\""* ]]
}

@test "junit formatter as report formatter creates report.xml" {
  cd "$BATS_TEST_TMPDIR" # don't litter sources with output files
  reentrant_run bats --report-formatter junit "$FIXTURE_ROOT/suite/"
  echo "$output"
  [[ -e "report.xml" ]]
  run cat "report.xml"
  echo "$output"
  [[ "${lines[2]}" == *"<testsuite name=\"file1.bats\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\""* ]]
  [[ "${lines[5]}" == *"<testsuite name=\"file2.bats\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\""* ]]
}

@test "junit does not mark tests with FD 3 output as failed (issue #360)" {
  reentrant_run bats --formatter junit "$FIXTURE_ROOT/issue_360.bats"

  echo "$output"

  [[ "${lines[2]}" == '<testsuite name="issue_360.bats" '*'>' ]]
  [[ "${lines[3]}" == '    <testcase classname="issue_360.bats" '*'>' ]]
  # only the outputs on FD3 should be visible on a successful test
  [[ "${lines[4]}" == '        <system-out>setup FD3' ]]
  [[ "${lines[5]}" == 'hello Bilbo' ]]
  [[ "${lines[6]}" == 'teardown FD3</system-out>' ]]
  [[ "${lines[7]}" == '    </testcase>' ]]
  [[ "${lines[8]}" == '    <testcase classname="issue_360.bats" name="fail to say hello to Biblo" time="'*'">' ]]
  # a failed test should show FD3 output first ...
  [[ "${lines[9]}" == '        <system-out>setup FD3' ]]
  [[ "${lines[10]}" == 'hello Bilbo' ]]
  [[ "${lines[11]}" == 'teardown FD3</system-out>' ]]
  [[ "${lines[12]}" == '        <failure type="failure">(in test file '*'test/fixtures/junit-formatter/issue_360.bats, line 21)' ]]
  [[ "${lines[13]}" == '  `false&#39; failed' ]]
  # ... and then the stdout output
  [[ "${lines[14]}" == '# setup stdout' ]]
  [[ "${lines[15]}" == '# hello stdout' ]]
  [[ "${lines[16]}" == '# teardown stdout</failure>' ]]
  [[ "${lines[17]}" == '    </testcase>' ]]
  [[ "${lines[18]}" == '</testsuite>' ]]
}

@test "junit does not mark tests with FD 3 output in teardown_file as failed (issue #531)" {
  bats_require_minimum_version 1.5.0
  reentrant_run -0 bats --formatter junit "$FIXTURE_ROOT/issue_531.bats"

  [[ "${lines[2]}" == '<testsuite name="issue_531.bats" '*'>' ]]
  [[ "${lines[3]}" == '    <testcase classname="issue_531.bats" '*'>' ]]
  # only the outputs on FD3 should be visible on a successful test
  [[ "${lines[4]}" == '        <system-out>test fd3' ]]
  [[ "${lines[5]}" == 'teardown_file fd3</system-out>' ]]
  [[ "${lines[6]}" == '    </testcase>' ]]
  [[ "${lines[7]}" == '</testsuite>' ]]
}

@test "don't choke on setup_file errors" {
  bats_require_minimum_version 1.5.0
  local stderr='' # silence shellcheck
  reentrant_run -1 --separate-stderr bats --formatter junit "$FIXTURE_ROOT/../file_setup_teardown/setup_file_failed.bats"
  [ "${stderr}" == "" ]
}
