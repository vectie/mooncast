///|
#warnings("-alert_unstable")
fn main {
  let (emit, cell) = @rabbita.cell_with_emit(
    model=initial_model(),
    update~,
    view=(dispatch, model) => render_app(dispatch, model),
    subscriptions=fn(_, _) { @sub.none },
  )
  @rabbita.new(cell)..with_init(emit(Bootstrap)).mount("app")
}
