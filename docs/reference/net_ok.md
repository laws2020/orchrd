# Check network reachability

Pings `host` and returns `TRUE` if it responds within `timeout` seconds.
Fails open on probe error.

## Usage

``` r
net_ok(host = "8.8.8.8", timeout = 3)
```

## Arguments

- host:

  Character. Hostname or IP to ping. Default `"8.8.8.8"` (Google DNS -
  quick, reliable).

- timeout:

  Numeric. Seconds to wait. Default `3`.

## Value

Logical scalar.
