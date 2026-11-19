# =============================================================================
# Unit tests for network/cloudflare module
#
# Run: tofu test
# =============================================================================

mock_provider "cloudflare" {}

variables {
  network_cloudflare_zone_id = "023e105f4ecef8ad9ca31a8372d0c353"
  network_domain             = "example.com"
  network_subdomain          = "app"

  # This comes from the distribution module (e.g., cloudfront)
  distribution_target_domain = "d1234567890.cloudfront.net"
}

# =============================================================================
# Test: Full domain is computed correctly with subdomain
# =============================================================================
run "full_domain_with_subdomain" {
  command = plan

  assert {
    condition     = local.network_full_domain == "app.example.com"
    error_message = "Full domain should be 'app.example.com', got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: Full domain is computed correctly without subdomain (apex)
# =============================================================================
run "full_domain_apex" {
  command = plan

  variables {
    network_subdomain = ""
  }

  assert {
    condition     = local.network_full_domain == "example.com"
    error_message = "Full domain should be 'example.com' for apex, got '${local.network_full_domain}'"
  }
}

# =============================================================================
# Test: network_domain is exposed for the distribution layer (ACM lookup)
# =============================================================================
run "exposes_network_domain" {
  command = plan

  assert {
    condition     = local.network_domain == "example.com"
    error_message = "network_domain should be 'example.com', got '${local.network_domain}'"
  }
}

# =============================================================================
# Test: Record configuration
# =============================================================================
run "record_configuration" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.main.zone_id == "023e105f4ecef8ad9ca31a8372d0c353"
    error_message = "Record should use the configured zone ID"
  }

  assert {
    condition     = cloudflare_dns_record.main.name == "app.example.com"
    error_message = "Record name should be the full domain"
  }

  assert {
    condition     = cloudflare_dns_record.main.type == "CNAME"
    error_message = "Record type should be CNAME"
  }

  assert {
    condition     = cloudflare_dns_record.main.content == "d1234567890.cloudfront.net"
    error_message = "Record should point at the distribution's hostname"
  }
}

# =============================================================================
# Test: The record is a CNAME at the apex too (Cloudflare flattens it)
# =============================================================================
run "apex_record_is_cname" {
  command = plan

  variables {
    network_subdomain = ""
  }

  assert {
    condition     = cloudflare_dns_record.main.name == "example.com"
    error_message = "Apex record name should be the zone's domain"
  }

  assert {
    condition     = cloudflare_dns_record.main.type == "CNAME"
    error_message = "Apex record should still be a CNAME"
  }
}

# =============================================================================
# Test: Not proxied by default, with the default TTL
# =============================================================================
run "dns_only_by_default" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.main.proxied == false
    error_message = "Record should be DNS-only by default"
  }

  assert {
    condition     = cloudflare_dns_record.main.ttl == 300
    error_message = "DNS-only record should use the default TTL of 300"
  }
}

# =============================================================================
# Test: Custom TTL on a DNS-only record
# =============================================================================
run "custom_ttl" {
  command = plan

  variables {
    network_cloudflare_ttl = 60
  }

  assert {
    condition     = cloudflare_dns_record.main.ttl == 60
    error_message = "DNS-only record should use the configured TTL"
  }
}

# =============================================================================
# Test: A proxied record forces the automatic TTL
# =============================================================================
run "proxied_forces_automatic_ttl" {
  command = plan

  variables {
    network_cloudflare_proxied = true
    network_cloudflare_ttl     = 60
  }

  assert {
    condition     = cloudflare_dns_record.main.proxied == true
    error_message = "Record should be proxied when requested"
  }

  assert {
    condition     = cloudflare_dns_record.main.ttl == 1
    error_message = "A proxied record must use ttl = 1 (automatic)"
  }
}

# =============================================================================
# Test: Outputs
# =============================================================================
run "outputs_are_correct" {
  command = plan

  assert {
    condition     = output.network_full_domain == "app.example.com"
    error_message = "network_full_domain output should be 'app.example.com'"
  }

  assert {
    condition     = output.network_fqdn == "app.example.com"
    error_message = "network_fqdn output should be 'app.example.com'"
  }

  assert {
    condition     = output.network_website_url == "https://app.example.com"
    error_message = "network_website_url output should be 'https://app.example.com'"
  }
}

# =============================================================================
# Test: Input validation
# =============================================================================
run "rejects_a_zone_name_as_zone_id" {
  command = plan

  variables {
    network_cloudflare_zone_id = "example.com"
  }

  expect_failures = [var.network_cloudflare_zone_id]
}

run "rejects_a_domain_that_is_not_a_hostname" {
  command = plan

  variables {
    network_domain = "example.com/zones"
  }

  expect_failures = [var.network_domain]
}
