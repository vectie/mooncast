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
