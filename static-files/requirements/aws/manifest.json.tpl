{
  "resources": {
    "aws_s3_bucket": {
      "bucket": "${service_name}-static",
      "versioning": true,
      "_meta": {
        "policies": [
          {
            "effect": "Allow",
            "actions": ["s3:ListBucket"],
            "resources": ["arn:aws:s3:::${service_name}-static"]
          },
          {
            "effect": "Allow",
            "actions": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
            "resources": ["arn:aws:s3:::${service_name}-static/*"]
          }
        ]
      }
    }
  }
}
