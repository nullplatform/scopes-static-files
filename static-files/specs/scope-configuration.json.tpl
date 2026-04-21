{
  "name": "Static Files",
  "description": "Configuration for static files scopes (SPAs, static websites, front-end bundles)",
  "category": "scope-configurations",
  "icon": "mdi:folder-upload-outline",
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": [
      "cloud_provider"
    ],
    "if": {
      "properties": { "cloud_provider": { "const": "aws" } },
      "required": ["cloud_provider"]
    },
    "then": {
      "properties": {
        "provider": {
          "required": ["aws_region", "aws_state_bucket"]
        }
      }
    },
    "else": {
      "if": {
        "properties": { "cloud_provider": { "const": "azure" } },
        "required": ["cloud_provider"]
      },
      "then": {
        "properties": {
          "provider": {
            "required": ["azure_subscription_id", "azure_resource_group", "azure_state_storage_account", "azure_state_container"]
          }
        }
      }
    },
    "properties": {
      "cloud_provider": {
        "type": "string",
        "title": "Cloud Provider",
        "description": "Select the cloud provider for this scope configuration",
        "oneOf": [
          { "const": "aws", "title": "Amazon Web Services" },
          { "const": "azure", "title": "Microsoft Azure" }
        ],
        "default": "aws"
      },

      "provider": {
        "type": "object",
        "title": "Provider Configuration",
        "properties": {
          "aws_region": {
            "type": "string",
            "title": "AWS Region",
            "description": "AWS region where resources will be deployed",
            "oneOf": [
              { "const": "us-east-1", "title": "US East (N. Virginia)" },
              { "const": "us-east-2", "title": "US East (Ohio)" },
              { "const": "us-west-1", "title": "US West (N. California)" },
              { "const": "us-west-2", "title": "US West (Oregon)" },
              { "const": "ca-central-1", "title": "Canada (Central)" },
              { "const": "sa-east-1", "title": "South America (São Paulo)" },
              { "const": "eu-west-1", "title": "Europe (Ireland)" },
              { "const": "eu-west-2", "title": "Europe (London)" },
              { "const": "eu-west-3", "title": "Europe (Paris)" },
              { "const": "eu-central-1", "title": "Europe (Frankfurt)" },
              { "const": "eu-central-2", "title": "Europe (Zurich)" },
              { "const": "eu-north-1", "title": "Europe (Stockholm)" },
              { "const": "eu-south-1", "title": "Europe (Milan)" },
              { "const": "eu-south-2", "title": "Europe (Spain)" },
              { "const": "ap-east-1", "title": "Asia Pacific (Hong Kong)" },
              { "const": "ap-south-1", "title": "Asia Pacific (Mumbai)" },
              { "const": "ap-south-2", "title": "Asia Pacific (Hyderabad)" },
              { "const": "ap-southeast-1", "title": "Asia Pacific (Singapore)" },
              { "const": "ap-southeast-2", "title": "Asia Pacific (Sydney)" },
              { "const": "ap-southeast-3", "title": "Asia Pacific (Jakarta)" },
              { "const": "ap-northeast-1", "title": "Asia Pacific (Tokyo)" },
              { "const": "ap-northeast-2", "title": "Asia Pacific (Seoul)" },
              { "const": "ap-northeast-3", "title": "Asia Pacific (Osaka)" },
              { "const": "me-south-1", "title": "Middle East (Bahrain)" },
              { "const": "me-central-1", "title": "Middle East (UAE)" },
              { "const": "af-south-1", "title": "Africa (Cape Town)" },
              { "const": "il-central-1", "title": "Israel (Tel Aviv)" }
            ]
          },
          "aws_state_bucket": {
            "type": "string",
            "title": "S3 State Bucket",
            "description": "S3 bucket name for storing OpenTofu state (also used for S3-native state locking)"
          },
          "azure_subscription_id": {
            "type": "string",
            "title": "Subscription ID",
            "description": "Azure subscription ID where resources will be deployed"
          },
          "azure_resource_group": {
            "type": "string",
            "title": "Resource Group",
            "description": "Azure resource group for scope resources"
          },
          "azure_state_storage_account": {
            "type": "string",
            "title": "Storage Account",
            "description": "Azure Storage account name for OpenTofu state"
          },
          "azure_state_container": {
            "type": "string",
            "title": "State Container",
            "description": "Blob container name for OpenTofu state files"
          }
        },
        "description": "Cloud provider settings, credentials, and state backend"
      },

      "distribution": {
        "type": "object",
        "title": "Distribution Layer",
        "properties": {
          "aws_distribution": {
            "type": "string",
            "title": "AWS Distribution",
            "description": "CDN distribution for serving static files",
            "default": "cloudfront",
            "oneOf": [
              { "const": "cloudfront", "title": "Amazon CloudFront" }
            ]
          },
          "azure_distribution": {
            "type": "string",
            "title": "Azure Distribution",
            "description": "CDN distribution for serving static files",
            "default": "blob_cdn",
            "oneOf": [
              { "const": "blob_cdn", "title": "Azure CDN (Blob Storage)" }
            ]
          }
        },
        "description": "CDN distribution settings"
      },

      "network": {
        "type": "object",
        "title": "Network Configuration",
        "properties": {
          "aws_network": {
            "type": "string",
            "title": "AWS DNS Provider",
            "description": "DNS provider for managing records",
            "default": "route53",
            "oneOf": [
              { "const": "route53", "title": "Amazon Route 53" }
            ]
          },
          "aws_hosted_public_zone_id": {
            "type": "string",
            "title": "Route 53 Hosted Zone ID",
            "description": "Public hosted zone ID for DNS records (e.g., Z1234567890ABC)"
          },
          "azure_network": {
            "type": "string",
            "title": "Azure DNS Provider",
            "description": "DNS provider for managing records",
            "default": "azure_dns",
            "oneOf": [
              { "const": "azure_dns", "title": "Azure DNS" }
            ]
          },
          "azure_dns_zone_name": {
            "type": "string",
            "title": "DNS Zone Name",
            "description": "Azure DNS zone name (e.g., example.com)"
          },
          "azure_dns_zone_resource_group": {
            "type": "string",
            "title": "DNS Zone Resource Group",
            "description": "Resource group containing the Azure DNS zone"
          }
        },
        "description": "DNS and network settings"
      }
    },

    "uiSchema": {
      "type": "VerticalLayout",
      "elements": [
        {
          "type": "Categorization",
          "elements": [
            {
              "type": "Category",
              "label": "Cloud Provider",
              "elements": [
                {
                  "type": "Control",
                  "scope": "#/properties/cloud_provider",
                  "options": {
                    "format": "radio-cards"
                  }
                }
              ]
            },
            {
              "type": "Category",
              "label": "Provider",
              "elements": [
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Label",
                  "text": "> **ℹ️ Agent Credentials (IRSA)**\n\nThe nullplatform agent must run with an IAM role attached to its Kubernetes service account (IRSA). The role needs permissions for:\n\n- **S3** — state backend read/write, asset bucket policy management, and state locking\n- **Route 53** — record management on `arn:aws:route53:::hostedzone/*` (GetHostedZone, ChangeResourceRecordSets, ListResourceRecordSets), zone listing on `*` (**ListHostedZones, ListHostedZonesByName** — these two don't support resource-level permissions), and **GetChange on `arn:aws:route53:::change/*`** (required for propagation polling — without it, deployments fail *after* creating the record)\n- **CloudFront** — distribution lifecycle and cache invalidation\n- **ACM** — certificate lookup (ListCertificates, DescribeCertificate, **GetCertificate**, **ListTagsForCertificate** — the AWS Terraform provider refreshes tags on every plan/apply even when the module doesn't declare them)\n- **STS** — caller identity (GetCallerIdentity)\n\nSee `static-files/docs/agent-iam-policy-aws-example.json` in the scope repo for a ready-to-use policy. Configure this in your agent Helm installation via the serviceAccount annotations.",
                  "options": {
                    "format": "markdown"
                  }
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/aws_region"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/aws_state_bucket"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Label",
                  "text": "> **ℹ️ Agent Credentials**\n\nThe nullplatform agent must run with Azure credentials configured. Use one of:\n\n- **Workload Identity** — attach an Azure managed identity to the agent's Kubernetes service account\n- **Service Principal** — set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID as environment variables in the agent Helm installation\n\nThe identity needs the following permissions:\n\n- **Storage Blob Data Contributor** — state backend\n- **DNS Zone Contributor** — DNS record management\n- **CDN Profile Contributor + CDN Endpoint Contributor** — CDN lifecycle\n- **Reader** on the assets storage account",
                  "options": {
                    "format": "markdown"
                  }
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/azure_subscription_id"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/azure_resource_group"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/azure_state_storage_account"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/provider/properties/azure_state_container"
                }
              ]
            },
            {
              "type": "Category",
              "label": "Distribution",
              "elements": [
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/distribution/properties/aws_distribution",
                  "options": {
                    "format": "radio-cards"
                  }
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/distribution/properties/azure_distribution",
                  "options": {
                    "format": "radio-cards"
                  }
                }
              ]
            },
            {
              "type": "Category",
              "label": "Network",
              "elements": [
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/network/properties/aws_network",
                  "options": {
                    "format": "radio-cards"
                  }
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "aws" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/network/properties/aws_hosted_public_zone_id"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/network/properties/azure_network",
                  "options": {
                    "format": "radio-cards"
                  }
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/network/properties/azure_dns_zone_name"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/network/properties/azure_dns_zone_resource_group"
                }
              ]
            }
          ]
        }
      ]
    }
  }
}
