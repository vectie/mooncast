///|
#warnings("-alert_unstable")
fn main {
  let model = initial_model()
  let (dispatch, cell) = @rabbita.cell_with_emit(
    model~,
    update~,
    view~,
    subscriptions=editor_subscriptions,
  )
  @rabbita.new(cell)..with_init(dispatch(Bootstrap)).mount("app")
}
