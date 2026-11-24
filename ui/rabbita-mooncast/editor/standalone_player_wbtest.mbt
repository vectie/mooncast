///|
test "standalone player is a separate lens and preserves a local file across projects" {
  let base = {
    ..initial_model(),
    player_file_url: "blob:local-video",
    player_file_name: "review.mp4",
  }
  let (_, player) = update(
    _ => @rabbita.none,
    SwitchWorkspaceLens(PlayerLens),
    base,
  )
  assert_eq(player.workspace_lens, PlayerLens)
  let other = activate_editor_project(player, "another-project")
  assert_eq(other.player_file_url, "blob:local-video")
  assert_eq(other.player_file_name, "review.mp4")
  let (_, editor) = update(
    _ => @rabbita.none,
    SwitchWorkspaceLens(EditorLens),
    player,
  )
  assert_eq(editor.workspace_lens, EditorLens)
  assert_eq(editor.player_file_name, "review.mp4")
  let player_markup = @rabbita.render_to_string(
    @rabbita.static_cell(view(_ => @rabbita.none, player)),
  )
  assert_true(player_markup.contains("/mooncast.svg"))
  assert_true(player_markup.contains("Open video or audio"))
  assert_false(player_markup.contains("Working in:"))
  assert_false(player_markup.contains("No editor projects yet"))
  assert_false(player_markup.contains("Publication blocked"))
  let editor_markup = @rabbita.render_to_string(
    @rabbita.static_cell(view(_ => @rabbita.none, editor)),
  )
  assert_true(editor_markup.contains("Working in:"))
  assert_true(editor_markup.contains("Publication blocked"))
  let first_edit = { ..editor, catalog_state: CatalogEmpty, workspace: None, }
  let first_markup = @rabbita.render_to_string(
    @rabbita.static_cell(view(_ => @rabbita.none, first_edit)),
  )
  assert_true(first_markup.contains("Create creative workspace"))
  assert_false(first_markup.contains("All QC"))
  assert_false(first_markup.contains("Apply clip settings"))
  assert_false(first_markup.contains("Working in:"))
}

///|
test "standalone player does not invent a render before one exists" {
  let base = initial_model()
  assert_eq(standalone_player_render_url(base), "")
  let rendered = {
    ..base,
    export_state: { ..base.export_state, download_url: "/renders/final.mp4", },
  }
  assert_eq(standalone_player_render_url(rendered), "/renders/final.mp4")
}
