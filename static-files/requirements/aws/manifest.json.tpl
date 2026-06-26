{
  "resources": [
    {
      "name": "static-bucket",
      "type": "AWS::S3::Bucket",
      "config": {
        "BucketName": "${service_name}-static",
        "VersioningConfiguration": {
          "Status": "Enabled"
        }
      },
      "policies": [
        {
          "statements": [
            {
              "actions": ["s3:ListBucket"],
              "resources": ["arn:aws:s3:::${service_name}-static"]
            },
            {
              "actions": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
              "resources": ["arn:aws:s3:::${service_name}-static/*"]
            }
          ]
        }
      ]
    }
  ]
}
