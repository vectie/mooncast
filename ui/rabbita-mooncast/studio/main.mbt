///|
#warnings("-alert_unstable")
fn main {
  let (emit, cell) = @rabbita.cell_with_emit(
    model=initial_model(),
    update~,
    view=(dispatch, model) => render_app(dispatch, model),
    subscriptions=(emit, model) => {
      @sub.batch([
        cut_player_subscriptions(emit, model),
        delivery_player_subscriptions(emit, model),
      ])
    },
  )
  @rabbita.new(cell)..with_init(emit(Bootstrap)).mount("app")
}
