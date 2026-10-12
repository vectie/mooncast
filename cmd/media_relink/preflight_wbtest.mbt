///|
async test "output preflight rejects dangling symlinks and every occupied kind" {
  let root = @fs.tmpdir(prefix="mooncast-relink-output")
  let dangling = root + "/dangling.json"
  @fs.symlink(target="missing-target", dangling)
  assert_false(@fs.exists(dangling))
  assert_true((try? require_absent_output(dangling)) is Err(_))
  assert_true(@fs.kind(dangling, follow_symlink=false) is SymLink)
  let directory = root + "/directory.json"
  @fs.mkdir(directory)
  assert_true((try? require_absent_output(directory)) is Err(_))
  let regular = root + "/regular.json"
  @fs.write_file(regular, b"keep", create_mode=CreateNew)
  assert_true((try? require_absent_output(regular)) is Err(_))
  assert_true((try? write_new(regular, "replacement")) is Err(_))
  assert_eq(@fs.read_file(regular).text(), "keep")
  let available = root + "/new.json"
  require_absent_output(available)
  write_new(available, "new")
  assert_eq(@fs.read_file(available).text(), "new")
}

///|
async test "preflight of dangling second output leaves first absent" {
  let root = @fs.tmpdir(prefix="mooncast-relink-pair")
  let first = root + "/pair.project.json"
  let second = root + "/pair.relink.json"
  @fs.symlink(target="missing-target", second)
  let result = try? ({
    for path in [first, second] {
      require_absent_output(path)
    }
    write_new(first, "project")
    write_new(second, "receipt")
  })
  assert_true(result is Err(_))
  assert_false(@fs.exists(first))
  assert_true(@fs.kind(second, follow_symlink=false) is SymLink)
  assert_false(@fs.exists(root + "/missing-target"))
}
