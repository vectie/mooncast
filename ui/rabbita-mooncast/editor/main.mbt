///|
#warnings("-alert_unstable")
fn main {
  let base = initial_model()
  let model = if standalone_player_route() {
    { ..base, workspace_lens: PlayerLens, }
  } else {
    base
  }
  let (dispatch, cell) = @rabbita.cell_with_emit(
    model~,
    update~,
    view~,
    subscriptions=editor_subscriptions,
  )
  @rabbita.new(cell)..with_init(dispatch(Bootstrap)).mount("app")
}
