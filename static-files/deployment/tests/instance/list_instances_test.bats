#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/list_instances
#
# A static scope has no pods: what runs is the CloudFront distribution, so that
# is the single instance it reports. The platform reads this list to show the
# scope's instances and to decide whether a blue/green deployment is healthy
# enough to switch traffic.
#
# Run tests:
#   bats tests/instance/list_instances_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/instance/list_instances"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export DISTRIBUTION_APP_NAME="automation-development-tools-7"

  MOCK_DISTRIBUTIONS='{
    "DistributionList": {
      "Items": [
        {
          "Id": "EOTHERDIST",
          "Comment": "Distribution for another-app-scope-1",
          "Status": "Deployed",
          "DomainName": "other.cloudfront.net",
          "LastModifiedTime": "2026-01-01T00:00:00Z",
          "Aliases": {"Items": ["other.example.com"]},
          "Origins": {"Items": [{"DomainName": "other-bucket.s3.amazonaws.com", "OriginPath": "/other"}]}
        },
        {
          "Id": "E1U76N37VGSGUN",
          "Comment": "Distribution for automation-development-tools-7",
          "Status": "Deployed",
          "DomainName": "d3t5px5huef9pb.cloudfront.net",
          "LastModifiedTime": "2026-09-13T21:00:00Z",
          "Aliases": {"Items": ["static.example.com"]},
          "Origins": {"Items": [{"DomainName": "assets.s3.amazonaws.com", "OriginPath": "/frontends/1/2"}]}
        }
      ]
    }
  }'
  export MOCK_DISTRIBUTIONS

  aws() {
    if [[ "$*" == *"cloudfront list-distributions"* ]]; then
      echo "$MOCK_DISTRIBUTIONS"
    fi
  }
  export -f aws
}

run_list_instances() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: The distribution is reported as the scope's instance
# =============================================================================
@test "Should report the scope's distribution as a single instance" {
  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$status" "0"
  assert_equal "$(echo "$output" | jq -r '.results | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.results[0].id')" "E1U76N37VGSGUN"
}

@test "Should report a deployed distribution as running" {
  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$(echo "$output" | jq -r '.results[0].state')" "Running"
}

@test "Should report a distribution still propagating as pending" {
  export MOCK_DISTRIBUTIONS=$(echo "$MOCK_DISTRIBUTIONS" | jq '.DistributionList.Items[1].Status = "InProgress"')

  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$(echo "$output" | jq -r '.results[0].state')" "Pending"
}

@test "Should carry the domain, aliases and origin as details" {
  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$(echo "$output" | jq -r '.results[0].details.domain')" "d3t5px5huef9pb.cloudfront.net"
  assert_equal "$(echo "$output" | jq -r '.results[0].details.aliases[0]')" "static.example.com"
  assert_equal "$(echo "$output" | jq -r '.results[0].details.origin')" "assets.s3.amazonaws.com/frontends/1/2"
}

@test "Should carry the last modification as the launch time" {
  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$(echo "$output" | jq -r '.results[0].launch_time')" "2026-09-13T21:00:00Z"
}

# =============================================================================
# Test: Nothing to report
# =============================================================================
@test "Should report an empty list when the scope has no distribution yet" {
  export MOCK_DISTRIBUTIONS='{"DistributionList": {"Items": []}}'

  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$status" "0"
  assert_equal "$(echo "$output" | jq -r '.results | length')" "0"
}

@test "Should fail when the app name is missing" {
  unset DISTRIBUTION_APP_NAME

  run bash -c "unset DISTRIBUTION_APP_NAME; source '$SCRIPT_PATH'"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Application name is not available"
  assert_contains "$output" "🔧 How to fix:"
}
