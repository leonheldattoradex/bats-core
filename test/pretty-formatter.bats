#!/usr/bin/env bats

setup() {
  load test_helper
  fixtures bats
}

@test "Timing printout shows milliseconds" {
  run filter_control_sequences bats-format-pretty -T <<HERE
1..1
suite /test/path
begin 1 test
ok 1 test in 123ms
begin 2 test2
not ok 2 test2 in 234ms
begin 3 test3
ok 3 test3 in 345ms # skip
HERE
  echo "$output"
  [[ "${lines[1]}" == *'test [123]'* ]]
  [[ "${lines[2]}" == *'test2 [234]'* ]]

  [[ "${lines[3]}" == *'test3 in 345ms (skipped) []'* ]]
}

@test "pretty formatter summary is colorized red on failure" {
  bats_require_minimum_version 1.5.0
  reentrant_run -1 bats --pretty "$FIXTURE_ROOT/failing.bats"

  [ "${lines[4]}" == $'\033[0m\033[31;1m' ] # TODO: avoid checking for the leading reset too
  [ "${lines[5]}" == '1 test, 1 failure' ]
  [ "${lines[6]}" == $'\033[0m' ]
}

@test "pretty formatter summary is colorized green on success" {
  bats_require_minimum_version 1.5.0
  reentrant_run -0 bats --pretty "$FIXTURE_ROOT/passing.bats"

  [ "${lines[2]}" == $'\033[0m\033[32;1m' ] # TODO: avoid checking for the leading reset too
  [ "${lines[3]}" == '1 test, 0 failures' ]
  [ "${lines[4]}" == $'\033[0m' ]
}

@test "Mixing timing and timeout" {
  run bats-format-pretty -T <<HERE
1..2
suite /test/path
begin 1 test timing=1, timeout=0
ok 1 test timing=1, timeout=0 in 123ms
begin 2 test timing=1, timeout=1
not ok 2 test timing=1, timeout=1 in 456ms # timeout after 0s
HERE

  [[ "${lines[1]}" == *"✓"* ]]
  [[ "${lines[1]}" == *"test timing=1, timeout=0"* ]]
  [[ "${lines[1]}" == *"[123]"* ]]

  [[ "${lines[2]}" == *"✗"* ]]
  [[ "${lines[2]}" == *"test timing=1, timeout=1"* ]]
  [[ "${lines[2]}" == *"[ (timeout: 0s)]"* ]]
  
  [[ "${lines[4]}" == *"2 tests, 0 failures, 1 timed out in"* ]]

  run bats-format-pretty <<HERE
1..1
suite /test/path
begin 1 test timing=0, timeout=1
not ok 1 test timing=0, timeout=1 # timeout after 0s
# timeout text
HERE

  [[ "${lines[1]}" == *"✗"* ]]
  [[ "${lines[1]}" == *"test timing=0, timeout=1"* ]]
  [[ "${lines[1]}" == *"[timeout: 0s]"* ]]
  [[ "${lines[2]}" == *"timeout text"* ]]
  [[ "${lines[4]}" == *"1 test, 0 failures, 1 timed out"* ]]
}
