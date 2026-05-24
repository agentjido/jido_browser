# Vendored BrowseyHttp

This directory contains a private vendored copy of
[BrowseyHttp](https://github.com/s3cur3/browsey_http), imported from upstream
commit `0324a26d3853aee39db54ad947a2f50769afda01`.

BrowseyHttp is MIT licensed. The upstream license is preserved in
[`LICENSE`](LICENSE), and the browser-impersonating curl assets are included
under `priv/vendor/browsey_http/curl` in this repository.

The vendored copy is used because BrowseyHttp is not currently published on Hex,
and Hex packages cannot depend on Git or path dependencies. If BrowseyHttp is
released on Hex, replace this vendored copy with the upstream Hex package at
<https://hex.pm/packages/browsey_http>.

Upstream references:

- Source repository: <https://github.com/s3cur3/browsey_http>
- Imported commit:
  <https://github.com/s3cur3/browsey_http/tree/0324a26d3853aee39db54ad947a2f50769afda01>
- Upstream license:
  <https://github.com/s3cur3/browsey_http/blob/0324a26d3853aee39db54ad947a2f50769afda01/LICENSE>

Local vendor patches:

- Modules are namespaced under `Jido.Browser.Vendor.BrowseyHttp` to avoid
  collisions with applications that may depend on upstream BrowseyHttp.
- Asset lookup points at the `:jido_browser` application priv directory.
- Process execution uses a local port-based shell runner instead of `erlexec`,
  because `erlexec` is retired and fails package audit checks.
- Curl wrapper command arguments are shell-quoted before execution.
