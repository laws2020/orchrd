test_that("run_cmd returns an orchrd_result", {
  res <- run_cmd("git", args = "--version")
  expect_s3_class(res, "orchrd_result")
  expect_true(is.logical(res$ok))
})
