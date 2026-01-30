# Dialyzer false positives
# 
# The Web adapter's pattern matches are correct, but dialyzer over-constrains
# the return type because it tracks through Application.get_env which can
# return nil at compile time but will have actual config at runtime.
[
  # Web adapter - dialyzer incorrectly infers only error return from run_web_command
  {"lib/jido_browser/adapters/web.ex", :pattern_match}
]
