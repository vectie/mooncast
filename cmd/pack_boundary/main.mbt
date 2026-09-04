///|
async fn main {
  let args = @env.args()
  let root = if args.length() > 1 { args[1] } else { "." }
  let issues = @boundary.scan(root) catch {
    error => {
      @stdio.stderr.write("pack boundary scan failed closed: \{Repr(error)}\n")
      @sys.exit(1)
      return
    }
  }
  if issues.is_empty() {
    @stdio.stdout.write("pack boundary scan passed\n")
  } else {
    @stdio.stderr.write("pack boundary scan failed:\n")
    for issue in issues {
      @stdio.stderr.write("- \{issue}\n")
    }
    @sys.exit(1)
  }
}
