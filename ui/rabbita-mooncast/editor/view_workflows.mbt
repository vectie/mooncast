///|
fn intake_input(
  dispatch : @rabbita.Emit[Msg],
  label_text : String,
  key : String,
  value : String,
) -> @rabbita.Html {
  @html.label <| [
    @html.span(label_text),
    @html.input(value~, on_input=dispatch.map(next => IntakeChanged(key, next))),
  ]
}

///|
fn media_intake_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let draft = model.intake
  @html.details(class="workflow-drawer") <| [
    @html.summary <| [
      @html.strong("Rights-cleared local media intake"),
      @html.span("Immutable bytes + rights + source evidence"),
    ],
    @html.form(class="workflow-grid", on_submit=dispatch(CreateMediaIntake)) <| [
      @html.label <| [
        @html.span("Role"),
        @html.select(
          on_change=dispatch.map(value => IntakeChanged("role", value)),
        ) <| ["voice", "music", "SFX", "subtitle", "image", "logo"].map(role => {
          @html.option(value=role, selected=draft.role == role, role)
        }),
      ],
      @html.label <| [
        @html.span("Local file selection"),
        @html.input(
          input_type=@html.File,
          accept="audio/*,image/*,.srt,.vtt,.txt",
          on_change=dispatch.map(value => IntakeChanged("file_name", value)),
        ),
      ],
      intake_input(dispatch, "Safe file name", "file_name", draft.file_name),
      intake_input(dispatch, "MIME type", "mime_type", draft.mime_type),
      intake_input(dispatch, "Size bytes", "size_bytes", draft.size_bytes),
      intake_input(dispatch, "SHA-256 (sha256:…)", "sha256", draft.sha256),
      intake_input(
        dispatch,
        "Duration seconds",
        "duration_seconds",
        draft.duration_seconds,
      ),
      intake_input(dispatch, "Rights owner", "owner", draft.owner),
      intake_input(dispatch, "Rights basis", "basis", draft.basis),
      intake_input(dispatch, "Territory", "territory", draft.territory),
      intake_input(
        dispatch,
        "Channels, comma separated",
        "channels",
        draft.channels,
      ),
      intake_input(dispatch, "Rights reference", "rights_ref", draft.rights_ref),
      intake_input(dispatch, "Source kind", "source_kind", draft.source_kind),
      intake_input(dispatch, "Source reference", "source_ref", draft.source_ref),
      @html.label(class="wide") <| [
        @html.span(
          "Local payload (UTF-8 subtitle/text or pre-hashed fixture bytes)",
        ),
        @html.textarea(
          value=draft.pasted_content,
          rows=5,
          on_input=dispatch.map(value => IntakeChanged("pasted_content", value)),
          "",
        ),
      ],
      @html.p(
        class="wide microcopy",
        "Rabbita freezes rights metadata before upload. Binary picker wiring remains constrained to library-provided Blob selection; no ad-hoc JavaScript bridge is installed.",
      ),
      @html.button(
        class="primary wide",
        type_="submit",
        disabled=model.busy || draft.file_name == "" || draft.sha256 == "",
        "Create intake and upload exact bytes",
      ),
    ],
  ]
}

///|
fn review_view(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let comments = model.workspace
    .bind(value => value.review_comments)
    .unwrap_or([])
  let annotations = model.workspace
    .bind(value => value.continuity_qc_overlays)
    .unwrap_or([])
  let deliveries = model.workspace
    .bind(value => value.delivery_intents)
    .unwrap_or([])
  @html.details(class="workflow-drawer", open=true) <| [
    @html.summary <| [
      @html.strong("QC, review & delivery intent"),
      @html.span(
        "\{comments.length()} comments · \{annotations.length()} QC findings",
      ),
    ],
    @html.div(class="review-columns") <| [
      @html.section <| [
        @html.h3("Continuity / QC annotations"),
        @html.ul(
          class="evidence-list",
          if annotations.length() == 0 {
            [@html.li("No annotations")]
          } else {
            annotations.map(item => {
              @html.li(
                "\{item.kind} · \{item.start_tick.unwrap_or(item.range.map(value => value.start_tick).unwrap_or(0))}t–\{item.end_tick.unwrap_or(item.range.map(value => value.end_tick).unwrap_or(0))}t · \{item.annotation_id.unwrap_or("fixture")}",
              )
            })
          },
        ),
      ],
      @html.section <| [
        @html.h3("Frame-accurate review comments"),
        @html.ul(
          class="evidence-list",
          if comments.length() == 0 {
            [@html.li("No review comments")]
          } else {
            comments.map(item => {
              @html.li <| [
                @html.time(
                  "\{timecode(model, item.start_tick.unwrap_or(0))}–\{timecode(model, item.end_tick.unwrap_or(item.start_tick.unwrap_or(0) + frame_ticks(model)))}",
                ),
                @html.span(item.text.unwrap_or("Review marker")),
              ]
            })
          },
        ),
        @html.form(class="comment-form", on_submit=dispatch(PostReviewComment)) <| [
          @html.textarea(
            value=model.review_comment,
            rows=3,
            placeholder="Comment on the playhead range…",
            on_input=dispatch.map(value => ReviewCommentChanged(value)),
            "",
          ),
          @html.button(
            class="primary",
            type_="submit",
            disabled=model.busy || model.review_comment.trim().length() == 0,
            "Add at playhead",
          ),
        ],
      ],
      @html.section <| [
        @html.h3("Delivery intents"),
        @html.ul(class="evidence-list") <| deliveries.map(item => {
          @html.li(
            "\{item.orientation.unwrap_or(item.delivery_id)} · \{item.width.unwrap_or(0)}×\{item.height.unwrap_or(0)}",
          )
        }),
      ],
    ],
  ]
}

///|
fn production_handoff_view(
  dispatch : @rabbita.Emit[Msg],
  model : Model,
) -> @rabbita.Html {
  let state = model.export_state
  @html.section(class="handoff-bar") <| [
    @html.div(class="handoff-group") <| [
      @html.label <| [
        @html.span("G4 production project"),
        @html.input(
          value=model.production_project_id,
          placeholder="project-id",
          on_input=dispatch.map(value => ProductionProjectChanged(value)),
        ),
      ],
      @html.button(
        type_="button",
        disabled=model.busy || model.production_project_id == "",
        on_click=dispatch(ImportProduction),
        "Import / open G4",
      ),
    ],
    @html.div(class="handoff-group") <| [
      @html.label <| [
        @html.span("Output preset"),
        @html.select(
          on_change=dispatch.map(value => ExportChanged("preset", value)),
        ) <| [
          @html.option(
            value="horizontal-1080p",
            selected=state.output_preset == "horizontal-1080p",
            "Horizontal 1080p",
          ),
          @html.option(
            value="vertical-1080p",
            selected=state.output_preset == "vertical-1080p",
            "Vertical 1080×1920",
          ),
        ],
      ],
      @html.button(
        type_="button",
        disabled=model.busy || model.workspace is None,
        on_click=dispatch(ApplyOutputPreset),
        "Apply output",
      ),
    ],
    @html.div(class="handoff-group") <| [
      @html.label <| [
        @html.span("Export job / resume key"),
        @html.input(
          value=state.job_id,
          placeholder="production-master-1",
          on_input=dispatch.map(value => ExportChanged("job_id", value)),
        ),
      ],
      @html.button(
        class="primary",
        type_="button",
        disabled=model.busy || model.workspace is None,
        on_click=dispatch(StartExport),
        "Export / resume",
      ),
      @html.button(
        type_="button",
        disabled=state.job_id == "",
        on_click=dispatch(PollExport),
        "Receipt",
      ),
      if state.receipt_state == "failed" {
        @html.button(
          type_="button",
          disabled=model.busy,
          on_click=dispatch(RetryExport),
          "Retry export",
        )
      } else {
        @html.nothing
      },
      if state.download_url != "" {
        @html.a(href=state.download_url, target=@html.Blank, "Download")
      } else {
        @html.nothing
      },
      @html.small(
        "\{state.receipt_state} · canonical r\{state.canonical_revision} · timeline r\{state.timeline_revision} · full \{timecode(model, duration_ticks(model))}",
      ),
    ],
    @html.div(class="handoff-group authority") <| [
      @html.label <| [
        @html.span("Named actor"),
        @html.input(
          value=state.actor,
          on_input=dispatch.map(value => ExportChanged("actor", value)),
        ),
      ],
      @html.label <| [
        @html.span("Authority reference"),
        @html.input(
          value=state.authority_ref,
          on_input=dispatch.map(value => ExportChanged("authority_ref", value)),
        ),
      ],
      @html.button(
        type_="button",
        disabled=model.busy || state.job_id == "" || state.authority_ref == "",
        on_click=dispatch(PromoteMaster),
        "Promote master",
      ),
    ],
    @html.div(class="handoff-group moonflow") <| [
      @html.div(class="handoff-receipt") <| [
        @html.span("Final-deliverable handoff"),
        @html.strong(state.handoff_status),
        if state.handoff_record_id != "" {
          @html.small("Evidence \{state.handoff_record_id}")
        } else {
          @html.nothing
        },
        if state.handoff_request_id != "" {
          @html.small("Request \{state.handoff_request_id}")
        } else {
          @html.nothing
        },
      ],
      @html.button(
        type_="button",
        disabled=model.busy ||
          !state.promoted ||
          state.receipt_state != "succeeded",
        on_click=dispatch(PrepareDeliverableHandoff),
        "Prepare governed handoff",
      ),
      @html.small(
        if state.handed_off {
          "Opaque MoonFlow request recorded; external execution and publication remain blocked."
        } else {
          "Mooncast records only its immutable deliverable evidence and an opaque handoff request."
        },
      ),
    ],
  ]
}

///|
fn editor_footer(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.footer(class="status-footer") <| [
    @html.div(class="status-strip") <| [
      status_tag(
        if model.loading || model.busy {
          "hold"
        } else {
          "pass"
        },
        if model.loading || model.busy {
          "Busy"
        } else {
          "Idle"
        },
      ),
      status_tag(
        if model.workspace is Some(_) {
          "pass"
        } else {
          "hold"
        },
        if model.workspace is Some(_) {
          "Server canonical"
        } else {
          "Awaiting project"
        },
      ),
      status_tag(
        if model.conflict == "" {
          "pass"
        } else {
          "hold"
        },
        if model.conflict == "" {
          "No conflict"
        } else {
          "Conflict"
        },
      ),
      @html.span(model.status),
    ],
    if model.conflict != "" {
      @html.div(class="alert conflict") <| [
        @html.strong("Conflict"),
        @html.span(model.conflict),
      ]
    } else {
      @html.nothing
    },
    if model.error != "" {
      @html.div(class="alert error") <| [
        @html.strong("Error"),
        @html.span(model.error),
        @html.button(
          type_="button",
          hidden=model.retry is None,
          on_click=dispatch(RetryPending),
          "Retry operation",
        ),
        @html.button(type_="button", on_click=dispatch(ClearError), "Dismiss"),
      ]
    } else {
      @html.nothing
    },
    @html.p(
      class="blocked-note",
      "Deterministic local preview. Publication blocked—this workspace has no publisher or provider authority.",
    ),
    @html.details(class="shortcuts") <| [
      @html.summary("Keyboard shortcuts"),
      @html.p(
        "Space play/pause · ←/→ frame step · S split · Delete remove · ⌘/Ctrl Z undo · ⌘/Ctrl Shift Z redo. Selection and playback are ephemeral; edits are canonical server commands.",
      ),
    ],
  ]
}
