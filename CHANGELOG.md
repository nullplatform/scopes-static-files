# Changelog

## [0.3.0](https://github.com/nullplatform/scopes-static-files/compare/v0.2.0...v0.3.0) (2026-07-06)


### Features

* add aws requirements module for static scope IAM and S3 resources ([535a7a7](https://github.com/nullplatform/scopes-static-files/commit/535a7a7064b2679ce44e8449b2089890c1a9b198))
* assume-role support for the static-files scope + requirements module ([59fee78](https://github.com/nullplatform/scopes-static-files/commit/59fee787dd390ea55a6c3b56d08a0e3598f1eb1a))
* assume-role support for the static-files scope + requirements module ([c8c83a4](https://github.com/nullplatform/scopes-static-files/commit/c8c83a4dd5a3358783f2fbc7d9b3880871e1d6b6))
* Lambda@Edge function associations for CloudFront distribution ([#12](https://github.com/nullplatform/scopes-static-files/issues/12)) ([cde9811](https://github.com/nullplatform/scopes-static-files/commit/cde98110e589fd0df15ab8ff7a8e80a9e62d39ba))
* replace requirements/aws module with manifest.json.tpl ([c0b7c75](https://github.com/nullplatform/scopes-static-files/commit/c0b7c751aafc3941f593c0847980de844a93810f))
* replace requirements/aws tf files with manifest.json ([e89559d](https://github.com/nullplatform/scopes-static-files/commit/e89559d7c340365d86cfe6aaaa1754d6a0c35782))
* **requirements:** add IAM role with parameterized variables ([efcb82e](https://github.com/nullplatform/scopes-static-files/commit/efcb82e5d57c046df03ba286b762c3402754f373))
* **requirements:** add S3 bucket policy enforcing HTTPS-only access ([4d84118](https://github.com/nullplatform/scopes-static-files/commit/4d84118c2c2f613cc99328efebef585c2457a96a))
* **requirements:** add S3 bucket with read and write policies ([a8bcd69](https://github.com/nullplatform/scopes-static-files/commit/a8bcd69b6ef071bba9e446dc626bb6ce41b488d2))
* restore requirements/aws as a tofu module ([3fe9a5c](https://github.com/nullplatform/scopes-static-files/commit/3fe9a5c20b7b14482c5a1bfb19bc3b09a09f7a1b))
* update manifest to Cloud Control API schema ([dcd46c2](https://github.com/nullplatform/scopes-static-files/commit/dcd46c283d91736b43a8ef1d9851ac42c9c9ae74))
* update manifest to typed resource lists schema ([670a447](https://github.com/nullplatform/scopes-static-files/commit/670a447f63f5fc7abfadf706a6bdcb9cb6c24dcb))
* update manifest to typed resources with policies array ([5876043](https://github.com/nullplatform/scopes-static-files/commit/5876043c9c7a00383a39c9dc251fa0efcb3b17d3))


### Bug Fixes

* hide WAF WebACL Name on non-AWS even when aws_security stays 'waf' ([#11](https://github.com/nullplatform/scopes-static-files/issues/11)) ([18a07db](https://github.com/nullplatform/scopes-static-files/commit/18a07dbf98a12e644f10317a6386fb0bcf6e8780))
