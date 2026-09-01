#' Sync a local directory to S3 via the AWS CLI
#'
#' Thin wrapper over \code{run_cmd()} that shells out to the AWS CLI's
#' \code{s3 sync}. Requires the \code{aws} CLI installed and credentials
#' configured (profile, \code{~/.aws}, or env vars).
#'
#' @param local_dir Character. Local folder to upload.
#' @param bucket    Character. Target S3 bucket name.
#' @param prefix    Character. Optional key prefix (path inside the bucket).
#' @param profile   Character. Optional AWS named profile.
#' @param region    Character. Optional AWS region.
#' @param delete    Logical. Remove S3 objects not present locally (mirror).
#' @param dryrun    Logical. Show what would happen without uploading.
#' @param error_ok  Logical. Return result even on failure (default FALSE).
#'
#' @return An \code{orchrd_result} object.
#' @export
#' @examples
#' \dontrun{
#' push_aws("dist/", bucket = "my-site", prefix = "static", profile = "prod")
#' }
push_aws <- function(
    local_dir,
    bucket,
    prefix   = "",
    profile  = NULL,
    region   = NULL,
    delete   = FALSE,
    dryrun   = FALSE,
    error_ok = FALSE
) {
  stopifnot(dir.exists(local_dir))

  dest <- paste0("s3://", bucket, if (nzchar(prefix)) paste0("/", prefix) else "")

  args <- c("s3", "sync", local_dir, dest)
  if (delete) args <- c(args, "--delete")
  if (dryrun) args <- c(args, "--dryrun")

  env <- character()
  if (!is.null(profile)) env <- c(env, AWS_PROFILE = profile)
  if (!is.null(region))  env <- c(env, AWS_DEFAULT_REGION = region)

  run_cmd(
    "aws",
    args     = args,
    env      = env,          # merged with current env by run_cmd (Fix #3)
    timeout  = Inf,          # large uploads must not be killed (Fix #4)
    error_ok = error_ok
  )
}
