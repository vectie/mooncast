///|
using @html {
  a,
  article,
  aside,
  button,
  div,
  form,
  h1,
  h2,
  h3,
  header,
  input,
  label,
  main_,
  nothing,
  p,
  section,
  small,
  span,
  strong,
  style_tag,
  textarea,
  video,
}

///|
let client_styles =
  #|:root{font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#e8edf7;background:#080b12;font-synthesis:none}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 16% 2%,color-mix(in srgb,var(--accent,#7c5cff) 18%,transparent),transparent 32rem),#080b12;color:#e8edf7}.client-shell{min-height:100vh;--accent:#7c5cff}.topbar{display:flex;justify-content:space-between;gap:2rem;align-items:center;padding:1.2rem clamp(1rem,4vw,4.5rem);border-bottom:1px solid #232938;background:#0a0e17dd;backdrop-filter:blur(18px);position:sticky;top:0;z-index:5}.eyebrow{margin:0 0:.35rem;color:var(--accent);font-size:.72rem;letter-spacing:.17em;font-weight:800}.brand{margin:0;font-size:1.3rem}.expiry{display:flex;flex-direction:column;text-align:right;font-size:.78rem;color:#8d98ad}.expiry strong{color:#e8edf7;margin-top:.25rem}.content{width:min(1400px,calc(100% - 2rem));margin:0 auto;padding:2.2rem 0 5rem}.summary{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(19rem,.7fr);gap:2rem;align-items:end;margin-bottom:1.5rem}.summary h2{font-size:clamp(2rem,5vw,4.4rem);line-height:.96;margin:.2rem 0 1rem;letter-spacing:-.055em}.summary-copy{color:#aab4c7;max-width:52rem;font-size:1.04rem}.binding-grid{display:grid;grid-template-columns:1fr 1fr;gap:.7rem}.binding{padding:.85rem 1rem;background:#111722;border:1px solid #262e3d;border-radius:12px}.binding span{display:block;color:#7f8a9f;font-size:.68rem;text-transform:uppercase;letter-spacing:.1em}.binding strong{display:block;margin-top:.32rem;font-size:.82rem;word-break:break-all}.review-grid{display:grid;grid-template-columns:minmax(0,1fr) 20rem;gap:1rem}.player-card,.panel{background:#0e131d;border:1px solid #252d3b;border-radius:18px;overflow:hidden}.player-card video{display:block;width:100%;aspect-ratio:16/9;background:#020306}.player-actions{display:flex;align-items:center;justify-content:space-between;padding:.85rem 1rem}.timecode{font-variant-numeric:tabular-nums;font-size:1.05rem;color:#dce5f6}.episodes{padding:1.1rem}.episodes h3,.panel h3{margin:.1rem 0 1rem}.episode{display:flex;justify-content:space-between;gap:1rem;padding:.8rem 0;border-top:1px solid #242c3a}.episode span{color:#8d98ad;font-size:.82rem}.panel{padding:1.3rem;margin-top:1rem}.panel-head{display:flex;align-items:flex-start;justify-content:space-between;gap:2rem;margin-bottom:1rem}.panel-head p{color:#929db0;max-width:44rem}.annotation-form{display:grid;grid-template-columns:12rem 16rem minmax(18rem,1fr) auto;gap:.75rem;align-items:end}.field{display:flex;flex-direction:column;gap:.42rem;color:#aeb8ca;font-size:.77rem}.field input,.field textarea{width:100%;border:1px solid #313a4d;border-radius:10px;background:#090d15;color:#f1f4fa;padding:.75rem;font:inherit;resize:vertical}.field input:focus,.field textarea:focus{outline:2px solid color-mix(in srgb,var(--accent) 50%,transparent);border-color:var(--accent)}button,.download{border:0;border-radius:10px;padding:.76rem 1rem;font-weight:750;cursor:pointer;background:var(--accent);color:#fff;text-decoration:none;text-align:center}button.secondary{background:#1b2331;color:#e7edf8;border:1px solid #354055}button:disabled{opacity:.45;cursor:not-allowed}.annotation-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:.8rem;margin-top:1rem}.annotation{background:#121925;border:1px solid #283244;border-radius:12px;padding:1rem}.annotation time{font-variant-numeric:tabular-nums;color:var(--accent);font-weight:800}.annotation p{margin:.65rem 0;color:#d7deeb}.annotation small{color:#8995aa}.decision-options{display:grid;grid-template-columns:repeat(3,1fr);gap:.7rem;margin:.85rem 0}.decision-choice{background:#151d2a;color:#b8c2d4;border:1px solid #303b4e}.decision-choice.selected{background:color-mix(in srgb,var(--accent) 20%,#121824);border-color:var(--accent);color:#fff}.decision-form{display:grid;grid-template-columns:16rem minmax(18rem,1fr);gap:.8rem}.confirm{grid-column:1/-1;display:flex;align-items:center;justify-content:flex-start;gap:.8rem;background:#111823;border:1px solid #2b3546;color:#dfe6f3}.confirm.on{border-color:var(--accent);background:color-mix(in srgb,var(--accent) 13%,#111823)}.decision-submit{grid-column:1/-1}.delivery-row{display:flex;justify-content:space-between;align-items:center;gap:1rem}.artifacts,.evidence-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:.8rem;margin-top:1rem}.artifact,.evidence{padding:1rem;background:#111823;border:1px solid #293345;border-radius:12px}.artifact span,.evidence span{display:block;color:#8d99ad;font-size:.78rem;margin-top:.35rem}.artifact code,.evidence code{display:block;margin-top:.55rem;color:#b7c2d5;font-size:.72rem;word-break:break-all}.boundary{display:flex;flex-wrap:wrap;gap:.55rem}.boundary span{padding:.45rem .65rem;border:1px solid #2e394b;border-radius:999px;color:#aeb8ca;font-size:.75rem}.receipt{border-left:3px solid var(--accent)}.status{position:sticky;bottom:1rem;margin:1rem auto 0;padding:.8rem 1rem;width:fit-content;max-width:100%;background:#171e2b;border:1px solid #303b4c;border-radius:999px;color:#cbd4e3;box-shadow:0 12px 40px #0008;text-align:center}.error{display:flex;align-items:flex-start;justify-content:space-between;gap:1rem;padding:1rem;background:#311820;border:1px solid #743348;border-radius:12px;color:#ffd7e1;margin-bottom:1rem}.state-card{max-width:680px;margin:12vh auto;padding:2rem;border:1px solid #2c3547;border-radius:18px;background:#101620;text-align:center}.state-card h2{font-size:2rem}.state-card p{color:#9ca7ba}.closed-note{padding:1rem;border-radius:12px;background:#231c16;border:1px solid #5a422a;color:#f1c99f;margin-bottom:1rem}@media(max-width:980px){.summary,.review-grid{grid-template-columns:1fr}.annotation-form{grid-template-columns:1fr 1fr}.annotation-form .field:nth-child(3){grid-column:1/-1}.episodes{order:2}.decision-form{grid-template-columns:1fr}}@media(max-width:620px){.topbar{align-items:flex-start}.summary h2{font-size:2.4rem}.binding-grid,.annotation-form,.decision-options{grid-template-columns:1fr}.annotation-form .field:nth-child(3){grid-column:auto}.panel{padding:1rem}.panel-head,.delivery-row{display:block}.download{display:block;margin-top:1rem}.status{border-radius:14px}}

///|
fn error_view(emit : Emit[Msg], error : @api.ApiErrorBody?) -> Html {
  match error {
    None => nothing
    Some(value) =>
      div(class="error") <| [
        div([strong(value.code), p(value.message)]),
        button(
          class="secondary",
          type_="button",
          on_click=emit(ClearError),
          "Dismiss",
        ),
      ]
  }
}

///|
fn state_view(emit : Emit[Msg], availability : PortalAvailability) -> Html {
  let (title, body, retry) = match availability {
    Loading =>
      (
        "Opening private review", "Checking the portal and its exact build binding…",
        false,
      )
    Expired =>
      (
        "This review link expired", "Ask the Mooncast team for a new portal bound to the current review master.",
        false,
      )
    Revoked =>
      (
        "This review link was revoked", "The link no longer grants access to client-safe review evidence.",
        false,
      )
    Closed(reason) => ("This exact-build review is closed", reason, false)
    Unavailable =>
      (
        "Review unavailable", "The portal could not be opened. Check the link or try again.",
        true,
      )
    Active => ("Review active", "", false)
  }
  section(class="state-card") <| [
    p(class="eyebrow", "MOONCAST CLIENT REVIEW"),
    h2(title),
    p(body),
    if retry {
      button(type_="button", on_click=emit(Reload), "Try again")
    } else {
      nothing
    },
  ]
}

///|
fn binding_card(label : String, value : String) -> Html {
  div(class="binding") <| [
    span(label),
    strong(value),
  ]
}

///|
fn episode_view(value : ClientEpisodeSummary) -> Html {
  div(class="episode") <| [
    strong(value.title),
    span("\{value.scene_count} scenes"),
  ]
}

///|
fn annotation_view(value : ClientAnnotation) -> Html {
  article(class="annotation") <| [
    @html.time(format_timecode(value.timecode_seconds)),
    p(value.body),
    small("\{value.author} · \{format_local_datetime(value.created_at)}"),
  ]
}

///|
fn decision_label(value : String) -> String {
  match value {
    "accept" => "Approved"
    "request-revision" => "Changes requested"
    "reject" => "Rejected"
    other => other
  }
}

///|
fn artifact_view(value : DeliveryArtifact) -> Html {
  div(class="artifact") <| [
    strong(value.name),
    span("\{value.kind} · \{human_bytes(value.size_bytes)}"),
    @html.code(value.sha256),
  ]
}

///|
fn evidence_view(label : String, value : String) -> Html {
  div(class="evidence") <| [
    strong(label),
    @html.code(value),
  ]
}

///|
fn receipt_view(value : ClientDecisionReceipt) -> Html {
  div(class="evidence receipt") <| [
    strong(decision_label(value.decision)),
    span(
      "Revision \{value.project_revision} · \{format_local_datetime(value.decided_at)}",
    ),
    @html.code("Receipt \{value.governance_receipt_digest}"),
    @html.code("Evidence \{value.digest}"),
  ]
}

///|
fn decision_button(
  emit : Emit[Msg],
  selected : String,
  value : String,
  label : String,
) -> Html {
  let class_name = if selected == value {
    "decision-choice selected"
  } else {
    "decision-choice"
  }
  button(
    class=class_name,
    type_="button",
    on_click=emit(SelectDecision(value)),
    label,
  )
}

///|
fn annotation_panel(
  emit : Emit[Msg],
  model : Model,
  value : ClientProjection,
) -> Html {
  section(class="panel") <| [
    div(class="panel-head") <| [
      div([p(class="eyebrow", "TIMECODE REVIEW"), h3("Leave precise notes")]),
      p("Each note is bound to this master SHA-256 and build digest."),
    ],
    form(class="annotation-form", on_submit=emit(SubmitAnnotation)) <| [
      label(class="field") <| [
        span("Timecode in seconds"),
        input(
          input_type=@html.Number,
          value=model.annotation.timecode,
          min=0,
          step=1,
          on_input=emit.map(value => AnnotationTimecodeChanged(value)),
        ),
      ],
      label(class="field") <| [
        span("Your name"),
        input(
          value=model.annotation.author,
          maxlength=160,
          required=true,
          on_input=emit.map(value => AnnotationAuthorChanged(value)),
        ),
      ],
      label(class="field") <| [
        span("Annotation"),
        textarea(
          value=model.annotation.body,
          rows=3,
          maxlength=2000,
          required=true,
          on_input=emit.map(value => AnnotationBodyChanged(value)),
          nothing,
        ),
      ],
      button(disabled=model.busy, type_="submit", "Add annotation"),
    ],
    div(
      class="annotation-list",
      if value.annotations.is_empty() {
        [
          p(
            "No annotations yet. Play the master and capture a timecode to begin.",
          ),
        ]
      } else {
        value.annotations.map(annotation_view)
      },
    ),
  ]
}

///|
fn decision_panel(
  emit : Emit[Msg],
  model : Model,
  value : ClientProjection,
) -> Html {
  if !value.decisions.is_empty() || value.delivery.accepted {
    nothing
  } else {
    section(class="panel") <| [
      div(class="panel-head") <| [
        div([
          p(class="eyebrow", "MILESTONE DECISION"),
          h3("Decide this exact customer build"),
        ]),
        p(
          "\{value.revision_policy.remaining} of \{value.revision_policy.maximum} contracted revision rounds remain.",
        ),
      ],
      div(class="decision-options") <| [
        decision_button(
          emit,
          model.decision.decision,
          "accept",
          "Approve delivery",
        ),
        decision_button(
          emit,
          model.decision.decision,
          "request-revision",
          "Request changes",
        ),
        decision_button(emit, model.decision.decision, "reject", "Reject build"),
      ],
      form(class="decision-form", on_submit=emit(SubmitDecision)) <| [
        label(class="field") <| [
          span("Authorized decision maker"),
          input(
            value=model.decision.actor,
            maxlength=128,
            required=true,
            on_input=emit.map(value => DecisionActorChanged(value)),
          ),
        ],
        label(class="field") <| [
          span(
            if model.decision.decision == "accept" {
              "Decision note (optional)"
            } else {
              "Decision note (required)"
            },
          ),
          textarea(
            value=model.decision.note,
            rows=3,
            maxlength=1000,
            required=model.decision.decision != "accept",
            on_input=emit.map(value => DecisionNoteChanged(value)),
            nothing,
          ),
        ],
        button(
          class=if model.decision.human_confirmed {
            "confirm on"
          } else {
            "confirm"
          },
          type_="button",
          on_click=emit(ToggleDecisionConfirmation),
          if model.decision.human_confirmed {
            "✓ I confirm I am authorized to make this decision"
          } else {
            "Confirm your decision authority"
          },
        ),
        button(
          class="decision-submit",
          disabled=model.busy,
          type_="submit",
          "Record immutable decision",
        ),
      ],
    ]
  }
}

///|
fn delivery_panel(model : Model, value : ClientProjection) -> Html {
  section(class="panel") <| [
    div(class="delivery-row") <| [
      div([
        p(class="eyebrow", "DELIVERY"),
        h3("Accepted package"),
        p(
          if value.delivery.accepted {
            "This exact build is accepted. The immutable delivery package is ready."
          } else {
            "The immutable delivery package unlocks only after this exact build is approved."
          },
        ),
      ]),
      match (value.delivery.download_url, value.delivery.archive_name) {
        (Some(path), Some(name)) if value.delivery.accepted =>
          a(
            class="download",
            href=resolve_url(model, path),
            download=name,
            escape=true,
            "Download accepted package",
          )
        _ => nothing
      },
    ],
    div(class="artifacts") <| value.delivery.artifacts.map(artifact_view),
  ]
}

///|
fn evidence_panel(value : ClientProjection) -> Html {
  section(class="panel") <| [
    div(class="panel-head") <| [
      div([
        p(class="eyebrow", "EVIDENCE & RECEIPTS"),
        h3("Exact-build audit trail"),
      ]),
      div(class="boundary") <| [
        span(
          if value.provider_data_included {
            "Provider data included"
          } else {
            "No provider data"
          },
        ),
        span(
          if value.publication_authority {
            "Publication authorized"
          } else {
            "No publication authority"
          },
        ),
      ],
    ],
    div(class="evidence-grid") <| [
      evidence_view("Master SHA-256", value.binding.master_sha256),
      evidence_view("Build digest", value.binding.build_digest),
      evidence_view("Delivery digest", value.binding.delivery_digest),
      evidence_view("Build ID", value.binding.build_id),
      ..value.decisions.map(receipt_view),
      ..value.annotations.map(item => {
        evidence_view("Annotation \{item.annotation_id}", item.digest)
      }),
      ..value.delivery.artifacts.map(item => {
        evidence_view("Artifact \{item.name}", item.sha256)
      }),
    ],
  ]
}

///|
fn active_view(
  emit : Emit[Msg],
  model : Model,
  value : ClientProjection,
) -> Html {
  let closed_notice = match model.availability {
    Closed(reason) => div(class="closed-note", reason)
    _ => nothing
  }
  div([
    closed_notice,
    section(class="summary") <| [
      div([
        p(class="eyebrow", "EPISODE MASTER"),
        h2(value.project.title),
        p(class="summary-copy", value.project.objective),
      ]),
      div(class="binding-grid") <| [
        binding_card("Master", short_digest(value.binding.master_sha256)),
        binding_card("Build", short_digest(value.binding.build_digest)),
        binding_card(
          "Duration",
          format_timecode(value.project.target_duration_seconds),
        ),
        binding_card("Publication", "Not authorized here"),
      ],
    ],
    section(class="review-grid") <| [
      div(class="player-card") <| [
        video(
          id="client-video",
          src=resolve_url(model, value.review_master_url),
          controls=true,
          preload="metadata",
          nothing,
        ),
        div(class="player-actions") <| [
          button(
            class="secondary",
            type_="button",
            on_click=emit(CaptureTimecode),
            "Use current timecode",
          ),
          span(class="timecode", format_timecode(model.playhead_seconds)),
        ],
      ],
      aside(class="panel episodes") <| [
        h3("Episode structure"),
        div(
          if value.project.episodes.is_empty() {
            [p("No episode summary available.")]
          } else {
            value.project.episodes.map(episode_view)
          },
        ),
      ],
    ],
    if model.availability == Active {
      annotation_panel(emit, model, value)
    } else {
      nothing
    },
    if model.availability == Active {
      decision_panel(emit, model, value)
    } else {
      nothing
    },
    delivery_panel(model, value),
    evidence_panel(value),
    p(class="status", model.status_message),
  ])
}

///|
fn view(emit : Emit[Msg], model : Model) -> Html {
  let accent = match model.projection {
    Some(value) => value.brand.accent
    None => "#7c5cff"
  }
  div(class="client-shell", style=["--accent: \{accent}"]) <| [
    style_tag(client_styles),
    header(class="topbar") <| [
      div([
        p(class="eyebrow", "PRIVATE CLIENT REVIEW"),
        h1(
          class="brand",
          match model.projection {
            Some(value) => value.brand.name
            None => "Mooncast Delivery"
          },
        ),
      ]),
      div(class="expiry") <| [
        span("Secure link expires"),
        strong(
          match model.projection {
            Some(value) => format_local_datetime(value.portal.expires_at)
            None => "Checking…"
          },
        ),
      ],
    ],
    main_(class="content") <| [
      error_view(emit, model.api_error),
      match model.projection {
        Some(value) => active_view(emit, model, value)
        None => state_view(emit, model.availability)
      },
    ],
  ]
}
