///|
/// Mooncast's client-facing Rabbita surface. It is mounted independently from
/// the production studio and editor, and receives only the client-safe portal
/// projection exposed by the pack server.
#warnings("-alert_unstable")
fn main {
  let url = Some(@url.parse(@dom.window().current_url())) catch { _ => None }
  let model = initial_model(url)
  let (emit, app) = @rabbita.cell_with_emit(
    model~,
    update~,
    view~,
    subscriptions~,
  )
  let startup = if token_from_url(model.url) == "" {
    @rabbita.none
  } else {
    load_projection(emit, model)
  }
  @rabbita.new(app)..with_init(startup).mount("app")
}
