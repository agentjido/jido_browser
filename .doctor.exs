%Doctor.Config{
  ignore_modules: [~r/^Jido\.Browser\.Vendor\.BrowseyHttp(?:\.|$)/],
  ignore_paths: [
    ~r|^test/support/|,
    ~r|^vendor/browsey_http/|
  ]
}
