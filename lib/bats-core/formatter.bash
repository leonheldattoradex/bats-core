#!/usr/bin/env bash


# reads (extended) bats tap streams from stdin and calls callback functions for each line
#
# Segmenting functions
# ====================
# bats_tap_stream_plan <number of tests>                                      -> when the test plan is encountered
# bats_tap_stream_suite <file name>                                           -> when a new file is begun WARNING: extended only
# bats_tap_stream_begin <test index> <test name>                              -> when a new test is begun WARNING: extended only
#
# Test result functions
# =====================
# If timing was enabled, BATS_FORMATTER_TEST_DURATION will be set to their duration in milliseconds
# bats_tap_stream_ok <test index> <test name>                                 -> when a test was successful
# bats_tap_stream_not_ok <test index> <test name>                             -> when a test has failed. If the failure was due to a timeout,
#                                                                                BATS_FORMATTER_TEST_TIMEOUT is set to the timeout duration in seconds
# bats_tap_stream_skipped <test index> <test name> <skip reason>              -> when a test was skipped
#
# Context functions
# =================
# bats_tap_stream_comment <comment text without leading '# '> <scope>         -> when a comment line was encountered,
#                                                                                scope tells the last encountered of plan, begin, ok, not_ok, skipped, suite
# bats_tap_stream_unknown <full line> <scope>                                 -> when a line is encountered that does not match the previous entries,
#                                                                                scope @see bats_tap_stream_comment
# forwards all input as is, when there is no TAP test plan header
function bats_parse_internal_extended_tap() {
  local header_pattern='[0-9]+\.\.[0-9]+'
  IFS= read -r header


  if [[ "$header" =~ $header_pattern ]]; then
    bats_tap_stream_plan "${header:3}"
  else
    # If the first line isn't a TAP plan, print it and pass the rest through
    printf '%s\n' "$header"
    exec cat
  fi


  ok_line_regexpr="ok ([0-9]+) (.*)"
  skip_line_regexpr="ok ([0-9]+) (.*) # skip( (.*))?$"
  timeout_line_regexpr="not ok ([0-9]+) (.*) # timeout after ([0-9]+)s$"
  not_ok_line_regexpr="not ok ([0-9]+) (.*)"


  timing_expr="in ([0-9]+)ms$" # Used to detect and extract timing
  local test_name begin_index last_begin_index try_index ok_index not_ok_index index scope
  begin_index=0
  last_begin_index=-1
  try_index=0
  index=0
  scope=plan
  while IFS= read -r line; do
    unset BATS_FORMATTER_TEST_DURATION BATS_FORMATTER_TEST_TIMEOUT
    local current_test_name # This will hold the name *before* timing/comments are stripped
    local current_comment=""
    local current_timing_duration=""

    case "$line" in
      'begin '*) # this might only be called in extended tap output
        scope=begin
        begin_index=${line#begin }
        begin_index=${begin_index%% *}
        if [[ $begin_index == "$last_begin_index" ]]; then
          ((++try_index))
        else
          try_index=0
        fi
        test_name="${line#begin "$begin_index" }"
        bats_tap_stream_begin "$begin_index" "$test_name"
        ;;
      'ok '*)
        ((++index))
        if [[ "$line" =~ $ok_line_regexpr ]]; then
          ok_index="${BASH_REMATCH[1]}"
          current_test_name="${BASH_REMATCH[2]}" # This includes name, potential timing, and potential comment

          if [[ "$current_test_name" =~ $timing_expr ]]; then
            current_timing_duration="${BASH_REMATCH[1]}"
            # Remove timing from the current_test_name for further processing
            current_test_name="${current_test_name% in "${current_timing_duration}"ms}"
            BATS_FORMATTER_TEST_DURATION="$current_timing_duration"
          fi

          if [[ "$current_test_name" == *" # "* ]]; then
            test_name="${current_test_name%% # *}"
            current_comment="${current_test_name#* # }"
          else
            test_name="$current_test_name"
          fi

          if [[ "$line" =~ $skip_line_regexpr ]]; then
            scope=skipped
            local skip_reason="${BASH_REMATCH[4]}"
            bats_tap_stream_skipped "$ok_index" "$test_name" "$skip_reason"
          else
            scope=ok
            bats_tap_stream_ok "$ok_index" "$test_name"
          fi

          # If there's a general comment (not a skip reason), pass it
          if [[ -n "$current_comment" && ! "$line" =~ $skip_line_regexpr ]]; then
            bats_tap_stream_comment "$current_comment" "ok"
          fi
        else
          printf "ERROR: could not match ok line: %s" "$line" >&2
          exit 1
        fi
        ;;
      'not ok '*)
        ((++index))
        scope=not_ok
        if [[ "$line" =~ $not_ok_line_regexpr ]]; then
          not_ok_index="${BASH_REMATCH[1]}"
          current_test_name="${BASH_REMATCH[2]}" # This includes name, potential timing, and potential comment

          if [[ "$current_test_name" =~ $timing_expr ]]; then
            current_timing_duration="${BASH_REMATCH[1]}"
            # Remove timing from the current_test_name for further processing
            current_test_name="${current_test_name% in "${current_timing_duration}"ms}"
            # shellcheck disable=SC2034
            BATS_FORMATTER_TEST_DURATION="$current_timing_duration"
          fi

          if [[ "$line" =~ $timeout_line_regexpr ]]; then
            # The timeout message itself acts as the "comment" for this type of failure
            # shellcheck disable=SC2034 # used in bats_tap_stream_not_ok
            BATS_FORMATTER_TEST_TIMEOUT="${BASH_REMATCH[3]}"
            test_name="${current_test_name}" # In timeout case, current_test_name is already stripped of timing, and the "comment" is handled by BATS_FORMATTER_TEST_TIMEOUT
            current_comment="" # No general comment needed, specific timeout is the reason
          elif [[ "$current_test_name" == *" # "* ]]; then
            test_name="${current_test_name%% # *}"
            current_comment="${current_test_name#* # }"
          else
            test_name="$current_test_name"
          fi

          bats_tap_stream_not_ok "$not_ok_index" "$test_name"

          if [[ -n "$current_comment" ]]; then
            bats_tap_stream_comment "$current_comment" "not_ok"
          fi
        else
          printf "ERROR: could not match not ok line: %s" "$line" >&2
          exit 1
        fi
        ;;
      '# '*)
        bats_tap_stream_comment "${line:2}" "$scope"
        ;;
      '#')
        bats_tap_stream_comment "" "$scope"
        ;;
      'suite '*)
        scope=suite
        # pass on the
        bats_tap_stream_suite "${line:6}"
        ;;
      *)
        bats_tap_stream_unknown "$line" "$scope"
        ;;
    esac
  done
}

normalize_base_path() { # <target variable> <base path>
  # the relative path root to use for reporting filenames
  # this is mainly intended for suite mode, where this will be the suite root folder
  local base_path="$2"
  # use the containing directory when --base-path is a file
  if [[ ! -d "$base_path" ]]; then
    base_path="$(dirname "$base_path")"
  fi
  # get the absolute path
  base_path="$(cd "$base_path" && pwd)"
  # ensure the path ends with / to strip that later on
  if [[ "${base_path}" != *"/" ]]; then
    base_path="$base_path/"
  fi
  printf -v "$1" "%s" "$base_path"
}
