///|
fn main {
  @async.run_async_main(async fn() {
    let input = @stdio.stdin.read_all().text()
    let output = @kernel.evaluate_json(input)
    @stdio.stdout.write(output + "\n")
  })
}
