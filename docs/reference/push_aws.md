# Sync a local directory to S3 via the AWS CLI

Thin wrapper over
[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md)
that shells out to the AWS CLI's `s3 sync`. Requires the `aws` CLI
installed and credentials configured (profile, `~/.aws`, or env vars).

## Usage

``` r
push_aws(
  local_dir,
  bucket,
  prefix = "",
  profile = NULL,
  region = NULL,
  delete = FALSE,
  dryrun = FALSE,
  error_ok = FALSE
)
```

## Arguments

- local_dir:

  Character. Local folder to upload.

- bucket:

  Character. Target S3 bucket name.

- prefix:

  Character. Optional key prefix (path inside the bucket).

- profile:

  Character. Optional AWS named profile.

- region:

  Character. Optional AWS region.

- delete:

  Logical. Remove S3 objects not present locally (mirror).

- dryrun:

  Logical. Show what would happen without uploading.

- error_ok:

  Logical. Return result even on failure (default FALSE).

## Value

An `orchrd_result` object.

## Examples

``` r
if (FALSE) { # \dontrun{
push_aws("dist/", bucket = "my-site", prefix = "static", profile = "prod")
} # }
```
