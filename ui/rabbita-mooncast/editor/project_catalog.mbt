///|
/// Catalog recovery is a read, not permission to open or install a project.
/// Only the documented initial bootstrap keeps its automatic open behavior.
fn load_project_catalog(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
  auto_open~ : Bool,
) -> (@rabbita.Cmd, Model) {
  guard model.catalog_state != CatalogLoading else {
    return (@rabbita.none, model)
  }
  let generation = model.catalog_generation + 1
  (
    @http.get("/api/editor/projects").expect_json(result => {
      dispatch(ProjectsLoaded(generation, result))
    }),
    {
      ..model,
      catalog_state: CatalogLoading,
      catalog_generation: generation,
      catalog_auto_open: auto_open,
      loading: true,
      status: "Loading editor projects…",
      error: "",
      retry: None,
    },
  )
}
