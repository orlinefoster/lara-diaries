#!/usr/bin/env bats

# ==============================================================================
# Tests for wizard-core.sh functions
# ==============================================================================
# These tests validate the individual helper functions extracted from
# wizard-core.sh. Each test sources the script in a subshell (bats does this
# per test by default) so changes to global state don't leak between tests.

setup() {
    # Ensure we're in the project root
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    MODULE="$PROJECT_ROOT/modules/wizard-core.sh"

    # Source the module — must exist
    if [[ ! -f "$MODULE" ]]; then
        echo "ERROR: wizard-core.sh not found at $MODULE" >&2
        exit 1
    fi

    # Silence output during tests
    export DRY_RUN="false"
}

# ──────────────────────────────────────────────────────────────────────
# component_status
# ──────────────────────────────────────────────────────────────────────

@test "component_status: reports installed (return 0) when already=true" {
    source "$MODULE"
    run component_status "TestComp" "true"
    [ "$status" -eq 0 ]
}

@test "component_status: reports needs-install (return 1) when already=false" {
    source "$MODULE"
    run component_status "TestComp" "false"
    [ "$status" -eq 1 ]
}

@test "component_status: reports optional (return 1) when optional flag set" {
    source "$MODULE"
    run component_status "TestComp" "false" "true"
    [ "$status" -eq 1 ]
}

@test "component_status: dry-run mode returns 2" {
    source "$MODULE"
    export DRY_RUN="true"
    run component_status "TestComp" "false"
    [ "$status" -eq 2 ]
}

@test "component_status: dry-run with optional returns 2" {
    source "$MODULE"
    export DRY_RUN="true"
    run component_status "TestComp" "false" "true"
    [ "$status" -eq 2 ]
}

@test "component_status: dry-run with already-installed returns 0" {
    source "$MODULE"
    export DRY_RUN="true"
    run component_status "TestComp" "true"
    [ "$status" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────
# validate_json
# ──────────────────────────────────────────────────────────────────────

@test "validate_json: accepts valid JSON with python3" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    run validate_json '{"name": "test", "value": 42}'
    [ "$status" -eq 0 ]
}

@test "validate_json: rejects invalid JSON with python3" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    run validate_json '{invalid json}'
    [ "$status" -ne 0 ]
}

@test "validate_json: accepts empty object" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    run validate_json '{}'
    [ "$status" -eq 0 ]
}

@test "validate_json: rejects empty string" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    run validate_json ''
    [ "$status" -ne 0 ]
}

@test "validate_json: accepts valid JSON with jq" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available"
    fi
    # Override: ensure jq is used (simulate no python3)
    source "$MODULE"
    run validate_json '{"hello": "world"}'
    [ "$status" -eq 0 ]
}

@test "validate_json: returns error when neither python3 nor jq available" {
    # Temporarily hide python3 and jq from PATH
    local OLD_PATH="$PATH"
    export PATH=""
    source "$MODULE"
    run validate_json '{}'
    [ "$status" -eq 1 ]
    export PATH="$OLD_PATH"
}

# ──────────────────────────────────────────────────────────────────────
# get_json_val (requires JSON_PARSER + JSON_DATA globals)
# ──────────────────────────────────────────────────────────────────────

@test "get_json_val: extracts string value with python3" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    export JSON_PARSER="python3"
    export JSON_DATA='{"name": "Lara", "version": 1}'
    run get_json_val "name" "default"
    [ "$status" -eq 0 ]
    [[ "$output" == "Lara" ]]
}

@test "get_json_val: extracts numeric value with python3" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    export JSON_PARSER="python3"
    export JSON_DATA='{"version": 42}'
    run get_json_val "version" "0"
    [ "$status" -eq 0 ]
    [[ "$output" == "42" ]]
}

@test "get_json_val: returns default for missing key with python3" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    export JSON_PARSER="python3"
    export JSON_DATA='{"name": "Lara"}'
    run get_json_val "missing" "fallback"
    [ "$status" -eq 0 ]
    [[ "$output" == "fallback" ]]
}

@test "get_json_val: extracts value with jq" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available"
    fi
    source "$MODULE"
    export JSON_PARSER="jq"
    export JSON_DATA='{"name": "Lara"}'
    run get_json_val "name" "default"
    [ "$status" -eq 0 ]
    [[ "$output" == "Lara" ]]
}

@test "get_json_val: returns default for missing key with jq" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available"
    fi
    source "$MODULE"
    export JSON_PARSER="jq"
    export JSON_DATA='{"name": "Lara"}'
    run get_json_val "missing" "fallback"
    [ "$status" -eq 0 ]
    [[ "$output" == "fallback" ]]
}

@test "get_json_val: nested key extraction" {
    if ! command -v python3 &>/dev/null; then
        skip "python3 not available"
    fi
    source "$MODULE"
    export JSON_PARSER="python3"
    export JSON_DATA='{"user": {"name": "Lara"}}'
    run python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d['user']['name'])" <<< "$JSON_DATA"
    [ "$status" -eq 0 ]
    [[ "$output" == "Lara" ]]
}
