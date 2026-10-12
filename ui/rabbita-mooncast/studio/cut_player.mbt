///|
struct PromotedMasterPlayback {
  contract : String
  project_id : String
  master_id : String
  master_sha256 : String
  duration_seconds : Int
  job_id : String
  media_url : String
} derive(FromJson)

///|
struct CutPlayer {
  project_id : String
  project_generation : Int
  master_sha256 : String
  row_key : Int
  generation : Int
  projection : PromotedMasterPlayback?
  loading : Bool
  ready : Bool
  current_seconds : Double
  duration_seconds : Double
  error : String?
}

///|
fn cut_player_id(generation : Int) -> String {
  "promoted-master-cut-player-" + generation.to_string()
}

///|
fn current_cut_player(model : Model) -> CutPlayer? {
  guard model.cut_player is Some(player) &&
    model.tab == Delivery &&
    player.generation == model.cut_player_generation &&
    player.project_id == model.selected_project_id &&
    player.project_generation == model.project_generation &&
    model.project is Some(project) &&
    project.id == player.project_id &&
    project.master is Some(master) &&
    master.sha256 == player.master_sha256 &&
    delivery_cut_drafts(model).master_sha256 == master.sha256 &&
    delivery_cut_drafts(model).cuts.any(cut => cut.key == player.row_key) else {
    return None
  }
  Some(player)
}

///|
fn invalidate_cut_player(model : Model) -> Model {
  {
    ..model,
    cut_player: None,
    cut_player_generation: model.cut_player_generation + 1,
  }
}

///|
fn select_cut_player(
  emit : @rabbita.Emit[Msg],
  model : Model,
  key : Int,
) -> (@rabbita.Cmd, Model) {
  guard !model.busy &&
    model.tab == Delivery &&
    !model.project_pending.contains("Project") &&
    !model.project_load_errors.any(item => item.0 == "Project") &&
    model.project is Some(project) &&
    project.id == model.selected_project_id &&
    project.master is Some(master) &&
    master.media.duration_seconds > 0 &&
    delivery_cut_drafts(model).master_sha256 == master.sha256 &&
    delivery_cut_drafts(model).cuts.any(cut => cut.key == key) else {
    return (@rabbita.none, invalidate_cut_player(model))
  }
  let generation = model.cut_player_generation + 1
  (
    @http.get("/api/v2/projects/" + project.id + "/promoted-master/playback").expect_json(
      emit.map(result => LoadedCutPlayer(generation, result)),
    ),
    {
      ..model,
      cut_player_generation: generation,
      cut_player: Some({
        project_id: project.id,
        project_generation: model.project_generation,
        master_sha256: master.sha256,
        row_key: key,
        generation,
        projection: None,
        loading: true,
        ready: false,
        current_seconds: 0.0,
        duration_seconds: 0.0,
        error: None,
      }),
    },
  )
}

///|
fn receive_cut_player(
  model : Model,
  generation : Int,
  result : Result[PromotedMasterPlayback, Error],
) -> Model {
  guard current_cut_player(model) is Some(player) &&
    player.generation == generation &&
    player.loading else {
    return model
  }
  let master = model.project.unwrap().master.unwrap()
  match result {
    Ok(value) if value.contract == "mooncast.promoted-master-playback.v1" &&
      value.project_id == player.project_id &&
      value.master_id == master.master_id &&
      value.master_sha256 == player.master_sha256 &&
      value.duration_seconds == master.media.duration_seconds &&
      value.job_id != "" &&
      !value.job_id.contains("/") &&
      !value.job_id.contains("?") &&
      value.media_url ==
      "/api/editor/projects/" +
      player.project_id +
      "/exports/" +
      value.job_id +
      "/media?master_sha256=" +
      "sha256:" +
      player.master_sha256
      .strip_prefix("sha256:")
      .unwrap_or(player.master_sha256[:])
      .to_owned() =>
      {
        ..model,
        cut_player: Some({ ..player, loading: false, projection: Some(value), }),
      }
    _ =>
      {
        ..model,
        cut_player: Some({
          ..player,
          loading: false,
          ready: false,
          projection: None,
          error: Some(
            "The exact promoted master could not be verified. Retry, or repair its export in Cut Editor.",
          ),
        }),
      }
  }
}

///|
/// Marks round half up to the nearest millisecond. Manual decimal strings are
/// never normalized; only the explicitly marked boundary is replaced.
extern "js" fn cut_player_mark_text(seconds : Double) -> String =
  #| seconds => Number.isFinite(seconds) && seconds >= 0 && seconds <= 2147483.647 ? (Math.round(seconds * 1000) / 1000).toFixed(3) : ""

///|
extern "js" fn cut_player_finite(value : Double) -> Bool = "value => Number.isFinite(value)"

///|
fn receive_cut_player_event(
  model : Model,
  generation : Int,
  kind : String,
  seconds : Double,
  duration : Double,
) -> Model {
  guard current_cut_player(model) is Some(player) &&
    player.generation == generation &&
    !player.loading &&
    player.projection is Some(projection) else {
    return model
  }
  if kind == "error" || kind == "unavailable" {
    return {
      ..model,
      cut_player: Some({
        ..player,
        ready: false,
        error: Some(
          "Master playback or metadata is unavailable. Retry the same promoted master; manual ranges remain editable.",
        ),
      }),
    }
  }
  if kind == "play-error" {
    return {
      ..model,
      cut_player: Some({
        ..player,
        error: Some(
          "Range playback was interrupted. Choose Preview selected range to try again, or Retry master playback.",
        ),
      }),
    }
  }
  // Errors are sticky until an explicit retry obtains a fresh verified binding.
  if !cut_player_finite(duration) ||
    duration <= 0.0 ||
    !cut_player_finite(seconds) ||
    seconds < 0.0 ||
    seconds > duration ||
    (!player.ready && player.error is Some(_)) {
    return model
  }
  if kind == "metadata" || kind == "time" {
    return {
      ..model,
      cut_player: Some({
        ..player,
        ready: true,
        current_seconds: seconds,
        duration_seconds: duration,
      }),
    }
  }
  if (kind == "mark-start" || kind == "mark-end") && player.ready && !model.busy {
    let text = cut_player_mark_text(seconds)
    guard delivery_cut_milliseconds(text) is Some(ms) &&
      ms.to_double() / 1000.0 <= projection.duration_seconds.to_double() else {
      return model
    }
    let field = if kind == "mark-start" { "start" } else { "end" }
    return save_delivery_cut_drafts(
      edit_delivery_cuts(model, EditDeliveryCut(player.row_key, field, text)),
    )
  }
  model
}

///|
fn cut_player_range(
  model : Model,
  player : CutPlayer,
) -> Result[(Int, Int), String] {
  guard player.ready && player.projection is Some(projection) else {
    return Err(
      "Wait for playable master metadata before marking or previewing.",
    )
  }
  guard delivery_cut_drafts(model).cuts
    .iter()
    .find_first(cut => cut.key == player.row_key)
    is Some(cut) else {
    return Err("Select a named cut first.")
  }
  match delivery_cut_range(cut.start, cut.end, projection.duration_seconds) {
    Ok((start, finish)) if finish.to_double() / 1000.0 <=
      player.duration_seconds => Ok((start, finish))
    Ok(_) =>
      Err("Cut end exceeds the playable master duration. Review the range.")
    Err(message) => Err(message)
  }
}

///|
fn cut_player_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  generation : Int,
  action : String,
) -> @rabbita.Cmd {
  guard current_cut_player(model) is Some(player) &&
    player.generation == generation &&
    player.ready &&
    !model.busy else {
    return @rabbita.none
  }
  let range = if action == "preview" {
    match cut_player_range(model, player) {
      Ok(value) => value
      Err(_) => return @rabbita.none
    }
  } else {
    (0, 0)
  }
  @cmd.custom_cmd(
    scheduler => {
      cut_player_dom_command(
        cut_player_id(generation),
        action,
        range.0,
        range.1,
        (kind, seconds, duration) => {
          scheduler.add(
            emit(CutPlayerEvent(generation, kind, seconds, duration)),
          )
        },
      )
    },
    kind=@cmd.after_render,
  )
}

///|
priv suberror CutPlayerSubscription {
  WatchCutPlayer(Int, @rabbita.Emit[Msg])
}

///|
fn cut_player_subscriptions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @sub.Sub {
  guard current_cut_player(model) is Some(player) &&
    player.projection is Some(_) else {
    return @sub.none
  }
  @sub.custom_sub(
    cut_player_id(player.generation),
    Local,
    WatchCutPlayer(player.generation, emit),
    @sub.SubLoader((payload, scheduler) => {
      guard payload is WatchCutPlayer(generation, emit) else { return None }
      let cleanup = cut_player_dom_watch(cut_player_id(generation), (
        kind,
        seconds,
        duration,
      ) => {
        scheduler.add(emit(CutPlayerEvent(generation, kind, seconds, duration)))
      })
      Some({ unload: _ => cleanup(), update_tagger: _ => (), })
    }),
  )
}
