{
  "resources": [
    {
      "aws_s3_bucket": {
        "name": "${service_name}-static",
        "versioning": true,
        "policies": [
          {
            "bucket_actions": ["s3:ListBucket"],
            "object_actions": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      }
    }
  ]
}
