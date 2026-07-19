///|
using @rabbita {type Cmd, type Emit, type Html}

///|
/// A media-event subscription keeps the immutable model synchronized with the
/// native video element without polling or package-local JavaScript.
priv suberror ClientSubscription {
  ReviewMedia(Emit[Double])
}

///|
fn review_media_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is ReviewMedia(initial_tagger) else { return None }
  guard @dom.document().get_element_by_id("client-video").to_option()
    is Some(element) else {
    return None
  }
  guard element.to_html_video_element() is Some(video) else { return None }
  let mut tagger = initial_tagger
  let listener : @dom.Listener = _ => {
    scheduler.add(tagger(video.get_current_time()))
  }
  video
  ..add_event_listener("loadedmetadata", listener)
  ..add_event_listener("timeupdate", listener)
  ..add_event_listener("seeking", listener)
  ..add_event_listener("seeked", listener)
  ..add_event_listener("play", listener)
  ..add_event_listener("pause", listener)
  .add_event_listener("ended", listener)
  scheduler.add(tagger(video.get_current_time()))
  Some({
    unload: fn(_) {
      video
      ..remove_event_listener("loadedmetadata", listener)
      ..remove_event_listener("timeupdate", listener)
      ..remove_event_listener("seeking", listener)
      ..remove_event_listener("seeked", listener)
      ..remove_event_listener("play", listener)
      ..remove_event_listener("pause", listener)
      .remove_event_listener("ended", listener)
    },
    update_tagger: fn(next_payload) {
      guard next_payload is ReviewMedia(next_tagger) else { return }
      tagger = next_tagger
    },
  })
}

///|
fn review_media_subscription(emit : Emit[Double]) -> @sub.Sub {
  @sub.custom_sub(
    "mooncast.client.review-media",
    @sub.Local,
    ReviewMedia(emit),
    review_media_loader,
  )
}

///|
fn load_projection(emit : Emit[Msg], model : Model) -> Cmd {
  @http.get(api_base(model)).expect_json(result => {
    emit(ProjectionLoaded(result))
  })
}

///|
fn update(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    UrlChanged(url) => {
      let previous_token = token_from_url(model.url)
      let next_token = token_from_url(Some(url))
      let next = {
        ..model,
        url: Some(url),
        projection: if next_token == previous_token {
          model.projection
        } else {
          None
        },
        availability: Loading,
        busy: false,
        playhead_seconds: 0.0,
        status_message: "Opening secure client review…",
        api_error: None,
      }
      if next_token == "" {
        (
          @rabbita.none,
          {
            ..next,
            availability: Unavailable,
            status_message: "This client review URL does not contain a portal token.",
            api_error: Some(
              error_body(
                "portal_token_missing", "Open the complete client review link.",
              ),
            ),
          },
        )
      } else {
        (
          @http.get(api_base(next)).expect_json(result => {
            emit(ProjectionLoaded(result))
          }),
          next,
        )
      }
    }
    Reload =>
      if token_from_url(model.url) == "" {
        (
          @rabbita.none,
          {
            ..model,
            availability: Unavailable,
            status_message: "This client review URL does not contain a portal token.",
            api_error: Some(
              error_body(
                "portal_token_missing", "Open the complete client review link.",
              ),
            ),
          },
        )
      } else {
        (
          load_projection(emit, model),
          {
            ..model,
            availability: Loading,
            busy: false,
            status_message: "Refreshing the exact-build review…",
            api_error: None,
          },
        )
      }
    ProjectionLoaded(Ok(value)) =>
      (
        @rabbita.none,
        {
          ..model,
          projection: Some(value),
          availability: availability_from_projection(value),
          busy: false,
          status_message: "Secure review loaded. Publishing and provider operations are unavailable here.",
          api_error: None,
        },
      )
    ProjectionLoaded(Err(error)) => {
      let message = "\{error}"
      (
        @rabbita.none,
        {
          ..model,
          availability: unavailable_from_error(message),
          busy: false,
          status_message: "The review portal could not be opened.",
          api_error: Some(error_body("client_portal_unavailable", message)),
        },
      )
    }
    MediaTimeChanged(value) =>
      (@rabbita.none, { ..model, playhead_seconds: Double::max(0.0, value) })
    CaptureTimecode => {
      let value = review_video_time().unwrap_or(model.playhead_seconds)
      (
        @rabbita.none,
        {
          ..model,
          playhead_seconds: value,
          annotation: {
            ..model.annotation,
            timecode: format_seconds_input(value),
          },
          status_message: "Captured \{format_timecode(value)} from the review master.",
        },
      )
    }
    AnnotationTimecodeChanged(value) =>
      (
        @rabbita.none,
        { ..model, annotation: { ..model.annotation, timecode: value } },
      )
    AnnotationAuthorChanged(value) =>
      (
        @rabbita.none,
        { ..model, annotation: { ..model.annotation, author: value } },
      )
    AnnotationBodyChanged(value) =>
      (
        @rabbita.none,
        { ..model, annotation: { ..model.annotation, body: value } },
      )
    SubmitAnnotation =>
      match active_projection(model) {
        None =>
          (
            @rabbita.none,
            {
              ..model,
              api_error: Some(
                error_body(
                  "portal_not_active", "Annotations require an active review portal.",
                ),
              ),
            },
          )
        Some(value) => {
          let author = model.annotation.author.trim().to_owned()
          let body = model.annotation.body.trim().to_owned()
          let seconds = parse_timecode(model.annotation.timecode)
          if author == "" || body == "" {
            (
              @rabbita.none,
              {
                ..model,
                api_error: Some(
                  error_body(
                    "annotation_incomplete", "Add your name and a precise review note.",
                  ),
                ),
              },
            )
          } else {
            match seconds {
              None =>
                (
                  @rabbita.none,
                  {
                    ..model,
                    api_error: Some(
                      error_body(
                        "invalid_timecode", "Timecode must be a number of seconds.",
                      ),
                    ),
                  },
                )
              Some(timecode_seconds) if timecode_seconds < 0.0 ||
                timecode_seconds > value.project.target_duration_seconds =>
                (
                  @rabbita.none,
                  {
                    ..model,
                    api_error: Some(
                      error_body(
                        "timecode_out_of_range", "Timecode must fall inside the review master.",
                      ),
                    ),
                  },
                )
              Some(timecode_seconds) => {
                let payload : AnnotationRequest = {
                  expected_master_sha256: value.binding.master_sha256,
                  expected_build_digest: value.binding.build_digest,
                  timecode_seconds,
                  author,
                  body,
                }
                (
                  @http.post("\{api_base(model)}/annotations")
                  .with_json(payload)
                  .expect_json(result => emit(AnnotationSaved(result))),
                  {
                    ..model,
                    busy: true,
                    status_message: "Recording an immutable timecode annotation…",
                    api_error: None,
                  },
                )
              }
            }
          }
        }
      }
    AnnotationSaved(Ok(receipt)) => {
      let projection = match model.projection {
        Some(value) =>
          Some({ ..value, annotations: [..value.annotations, receipt] })
        None => None
      }
      (
        @rabbita.none,
        {
          ..model,
          projection,
          busy: false,
          annotation: { ..model.annotation, body: "" },
          status_message: "Annotation recorded against the exact master and build digest.",
          api_error: None,
        },
      )
    }
    AnnotationSaved(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          busy: false,
          status_message: "The annotation was not recorded.",
          api_error: Some(error_body("annotation_failed", "\{error}")),
        },
      )
    DecisionActorChanged(value) =>
      (@rabbita.none, { ..model, decision: { ..model.decision, actor: value } })
    DecisionNoteChanged(value) =>
      (@rabbita.none, { ..model, decision: { ..model.decision, note: value } })
    SelectDecision(value) =>
      (
        @rabbita.none,
        {
          ..model,
          decision: {
            ..model.decision,
            decision: value,
            human_confirmed: false,
          },
          api_error: None,
        },
      )
    ToggleDecisionConfirmation =>
      (
        @rabbita.none,
        {
          ..model,
          decision: {
            ..model.decision,
            human_confirmed: !model.decision.human_confirmed,
          },
        },
      )
    SubmitDecision =>
      match active_projection(model) {
        None =>
          (
            @rabbita.none,
            {
              ..model,
              api_error: Some(
                error_body(
                  "portal_not_active", "Decisions require an active review portal.",
                ),
              ),
            },
          )
        Some(value) => {
          let actor = model.decision.actor.trim().to_owned()
          let note = model.decision.note.trim().to_owned()
          let requires_note = model.decision.decision != "accept"
          if actor == "" {
            (
              @rabbita.none,
              {
                ..model,
                api_error: Some(
                  error_body(
                    "decision_actor_required", "Enter the authorized decision maker's name.",
                  ),
                ),
              },
            )
          } else if requires_note && note == "" {
            (
              @rabbita.none,
              {
                ..model,
                api_error: Some(
                  error_body(
                    "decision_note_required", "Change requests and rejections require a decision note.",
                  ),
                ),
              },
            )
          } else if !model.decision.human_confirmed {
            (
              @rabbita.none,
              {
                ..model,
                api_error: Some(
                  error_body(
                    "human_confirmation_required", "Confirm that you are authorized to make this client decision.",
                  ),
                ),
              },
            )
          } else {
            let payload : DecisionRequest = {
              expected_master_sha256: value.binding.master_sha256,
              expected_build_digest: value.binding.build_digest,
              human_confirmed: true,
              actor,
              decision: model.decision.decision,
              note,
            }
            (
              @http.post("\{api_base(model)}/decision")
              .with_json(payload)
              .expect_json(result => {
                emit(DecisionSaved(model.decision.decision, result))
              }),
              {
                ..model,
                busy: true,
                status_message: "Recording the exact-build milestone decision…",
                api_error: None,
              },
            )
          }
        }
      }
    DecisionSaved(decision, Ok(receipt)) => {
      let projection = match model.projection {
        Some(value) =>
          Some({ ..value, decisions: [..value.decisions, receipt] })
        None => None
      }
      if decision == "accept" {
        (
          load_projection(emit, { ..model, projection, }),
          {
            ..model,
            projection,
            busy: true,
            status_message: "Approval recorded, reconciled into canonical G5, and unlocking the accepted delivery package…",
            api_error: None,
          },
        )
      } else {
        let closure = if decision == "reject" {
          "Rejected. This exact-build portal is closed and the governance receipt is retained."
        } else {
          "Changes requested. This exact-build portal is closed and the governance receipt is retained."
        }
        (
          @rabbita.none,
          {
            ..model,
            projection,
            availability: Closed(closure),
            busy: false,
            status_message: closure,
            api_error: None,
          },
        )
      }
    }
    DecisionSaved(_, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          busy: false,
          status_message: "The client decision was not recorded.",
          api_error: Some(error_body("decision_failed", "\{error}")),
        },
      )
    ClearError => (@rabbita.none, { ..model, api_error: None })
  }
}

///|
fn subscriptions(emit : Emit[Msg], model : Model) -> @sub.Sub {
  let subscriptions = [@sub.on_url_changed(emit.map(url => UrlChanged(url)))]
  if model.availability == Active {
    subscriptions.push(
      review_media_subscription(emit.map(value => MediaTimeChanged(value))),
    )
  }
  @sub.batch(subscriptions)
}
