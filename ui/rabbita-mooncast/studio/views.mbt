///|
using @html {
  a,
  article,
  aside,
  button,
  code,
  div,
  h1,
  h2,
  h3,
  header,
  input,
  label,
  li,
  main_,
  nav,
  p,
  section,
  small,
  span,
  strong,
  textarea,
  ul,
}

///|
type Dispatch[A] = @rabbita.Emit[A]

///|
fn tab_label(tab : StudioTab) -> String {
  match tab {
    Overview => "Overview"
    NeedsStrategy => "Needs / Strategy"
    Creative => "Creative"
    AssetFactory => "Asset Factory"
    StoryboardAnimatic => "Storyboard / Animatic"
    Routing => "Routing"
    ShotBoard => "Shot board"
    Delivery => "Delivery"
    Commercial => "Commercial"
  }
}

///|
fn tab_button(
  dispatch : Dispatch[Msg],
  selected : StudioTab,
  tab : StudioTab,
) -> @rabbita.Html {
  button(
    class=if selected == tab {
      "studio-nav-item active"
    } else {
      "studio-nav-item"
    },
    on_click=dispatch(SelectTab(tab)),
    tab_label(tab),
  )
}

///|
fn status_tone(status : String) -> String {
  match status {
    "passed" | "approved" | "completed" | "accepted" => "good"
    "failed" | "rejected" | "attention-required" | "cancelled" => "bad"
    "running" | "building" => "active"
    _ => "pending"
  }
}

///|
fn status_chip(status : String) -> @rabbita.Html {
  span(class="status-chip " + status_tone(status), status)
}

///|
fn metric(label_ : String, value : String, note : String) -> @rabbita.Html {
  article(class="metric-card", [small(label_), strong(value), p(note)])
}

///|
fn form_field(
  label_ : String,
  value_ : String,
  placeholder_ : String,
  change : @rabbita.Emit[String],
) -> @rabbita.Html {
  label(class="field", [
    span(label_),
    input(value=value_, placeholder=placeholder_, on_input=change),
  ])
}

///|
fn text_field(
  label_ : String,
  value_ : String,
  placeholder_ : String,
  rows_ : Int,
  change : @rabbita.Emit[String],
) -> @rabbita.Html {
  label(class="field", [
    span(label_),
    textarea(
      rows=rows_,
      value=value_,
      placeholder=placeholder_,
      on_input=change,
      "",
    ),
  ])
}

///|
fn render_header(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  header(class="studio-header", [
    div(class="brand", [
      span(class="brand-mark", "M"),
      div([strong("Mooncast"), small("AIGC production operating system")]),
    ]),
    nav(class="studio-tabs", [
      tab_button(dispatch, model.tab, Overview),
      tab_button(dispatch, model.tab, NeedsStrategy),
      tab_button(dispatch, model.tab, Creative),
      tab_button(dispatch, model.tab, AssetFactory),
      tab_button(dispatch, model.tab, StoryboardAnimatic),
      tab_button(dispatch, model.tab, Routing),
      tab_button(dispatch, model.tab, ShotBoard),
      tab_button(dispatch, model.tab, Delivery),
      tab_button(dispatch, model.tab, Commercial),
    ]),
    div(class="header-actions", [
      button(
        class="secondary",
        disabled=model.selected_project_id == "" || model.loading,
        on_click=dispatch(RefreshProject),
        "Refresh exact revision",
      ),
      a(class="primary-link", href="/editor", "Open cut editor"),
    ]),
  ])
}

///|
fn render_project_rail(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  aside(class="project-rail", [
    div(class="rail-heading", [
      div([small("Production ledger"), h2("Projects")]),
      span(class="count", "\{model.projects.length()}"),
    ]),
    div(
      class="project-list",
      if model.projects.is_empty() {
        [p(class="empty", "No project recorded yet.")]
      } else {
        model.projects.map(item => {
          button(
            class=if item.project_id == model.selected_project_id {
              "project-item selected"
            } else {
              "project-item"
            },
            on_click=dispatch(SelectProject(item.project_id)),
            [
              strong(item.title),
              span([code(item.project_id), status_chip(item.stage)]),
              small(
                "Revision \{item.revision} · next \{item.next_gate.unwrap_or("complete")}",
              ),
            ],
          )
        })
      },
    ),
    div(class="rail-safety", [
      strong("Authority boundary"),
      p(
        "This studio records plans and named reviews. It never grants publication authority, sends payments, or calls a provider implicitly.",
      ),
    ]),
  ])
}

///|
fn selected_intake(model : Model) -> ImportedIntakeProjection? {
  match model.needs_intake {
    None => None
    Some(workspace) => {
      let matches = workspace.intakes.filter(value => {
        value.packet.packet_id == model.selected_intake_id
      })
      if matches.is_empty() {
        None
      } else {
        let mut latest = matches[0]
        for candidate in matches {
          if candidate.packet.packet_version > latest.packet.packet_version {
            latest = candidate
          }
        }
        Some(latest)
      }
    }
  }
}

///|
fn intake_approved(model : Model, intake : ImportedIntakeProjection) -> Bool {
  match model.needs_intake {
    None => false
    Some(workspace) => {
      let decisions = workspace.decisions.filter(value => {
        value.packet_id == intake.packet.packet_id &&
        value.packet_version == intake.packet.packet_version &&
        value.provenance_digest == intake.validation.provenance_digest
      })
      if decisions.is_empty() {
        false
      } else {
        let mut latest = decisions[0]
        for candidate in decisions {
          if candidate.decided_at > latest.decided_at ||
            (candidate.decided_at == latest.decided_at &&
            candidate.decision_digest > latest.decision_digest) {
            latest = candidate
          }
        }
        latest.decision == "approve"
      }
    }
  }
}

///|
fn evidence_card(value : MoonWikiEvidenceProjection) -> @rabbita.Html {
  article(class="artifact-card", [
    div(class="artifact-card-head", [
      strong(value.source_id),
      status_chip("v" + value.source_version),
    ]),
    code(value.source_digest),
    small(value.provenance_ref),
  ])
}

///|
fn render_needs_strategy(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let imported = match model.needs_intake {
    Some(value) => value.intakes
    None => []
  }
  div(class="surface-stack", [
    section(class="panel", [
      div(class="panel-heading", [
        div([
          small("MOONWIKI EVIDENCE PORT"),
          h2("Understand the whole need before production"),
        ]),
        p(
          "Import a MoonWiki-owned evidence packet. Mooncast validates and binds exact source identities; it does not copy MoonWiki authority or run an agent.",
        ),
      ]),
      text_field(
        "MoonWiki export packet",
        model.intake_packet_draft,
        "Paste moonwiki.mooncast-needs-export.v1 JSON",
        18,
        fn(value) { dispatch(SetIntakePacketDraft(value)) },
      ),
      div(class="form-actions", [
        button(
          class="primary",
          disabled=model.busy,
          on_click=dispatch(ImportNeedsPacket),
          "Import immutable packet",
        ),
        small(
          "Import performs no provider, publication, payment, MoonFlow, or MoonBook effect.",
        ),
      ]),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("VERSIONED INTAKE LEDGER"), h2("Imported needs")]),
        p("Each version has a deterministic provenance digest and independent human decision."),
      ]),
      div(
        class="artifact-tabs",
        if imported.is_empty() {
          [p(class="empty", "No MoonWiki needs packet imported yet.")]
        } else {
          imported.map(value => {
            button(
              class=if value.packet.packet_id == model.selected_intake_id {
                "artifact-tab active"
              } else {
                "artifact-tab"
              },
              on_click=dispatch(SelectIntake(value.packet.packet_id)),
              value.packet.packet_id + " · v" + value.packet.packet_version.to_string(),
            )
          })
        },
      ),
    ]),
    match selected_intake(model) {
      None => @html.nothing
      Some(intake) => {
        let packet = intake.packet
        let approved = intake_approved(model, intake)
        section(class="panel", [
          div(class="panel-heading", [
            div([
              small("EXACT PACKET " + packet.packet_id),
              h2(packet.creative_strategy.project_title),
            ]),
            div(class="chips", [
              status_chip(if intake.validation.complete { "complete" } else { "attention-required" }),
              status_chip(if approved { "approved" } else { "pending" }),
              status_chip("immutable"),
            ]),
          ]),
          div(class="metrics", [
            metric(
              "Payable problem",
              packet.client_need.customer,
              packet.client_need.payable_problem,
            ),
            metric(
              "Production boundary",
              "\{packet.contract_boundary.target_duration_seconds / 60} min · CNY \{packet.contract_boundary.budget_ceiling_cny}",
              "\{packet.contract_boundary.revision_limit} revision rounds · \{packet.contract_boundary.contract_ref}",
            ),
            metric(
              "Audience / channel",
              packet.client_need.audience,
              packet.client_need.channels.join(" · "),
            ),
            metric(
              "Rights / data",
              packet.constraints.rights_owner,
              packet.constraints.confidentiality_class + " · " + packet.constraints.permitted_data_class,
            ),
          ]),
          article(class="artifact-card", [
            strong("Creative proposition"),
            p(packet.creative_strategy.narrative_proposition),
            small(
              packet.creative_strategy.tone +
              " · metrics: " +
              packet.creative_strategy.success_metrics.join("; "),
            ),
          ]),
          div(class="artifact-grid", packet.evidence_refs.map(evidence_card)),
          article(class="artifact-card", [
            strong("Deterministic provenance"),
            code(intake.validation.provenance_digest),
            small("Exported " + packet.exported_at + " · imported " + intake.imported_at),
          ]),
          if intake.validation.errors.is_empty() &&
            intake.validation.unresolved_questions.is_empty() {
            p(class="callout good", "All required needs, rights, contract, strategy, evidence, and intent bindings are complete.")
          } else {
            div(class="callout bad", [
              strong("Resolve before approval"),
              ul([
                ..intake.validation.errors.map(value => li(value)),
                ..intake.validation.unresolved_questions.map(value => li("Open question: " + value)),
              ]),
            ])
          },
          div(class="form-actions", [
            button(
              class="primary",
              disabled=model.busy ||
                !model.operator.human_confirmed ||
                !intake.validation.complete,
              on_click=dispatch(DecideNeedsIntake("approve")),
              "Approve exact needs / strategy",
            ),
            button(
              class="danger",
              disabled=model.busy || !model.operator.human_confirmed,
              on_click=dispatch(DecideNeedsIntake("reject")),
              "Reject packet",
            ),
          ]),
          div(class="form-grid", [
            form_field(
              "Project id",
              model.intake_seed_project_id,
              "brand-episode-001",
              fn(value) { dispatch(SetIntakeSeedProjectId(value)) },
            ),
            button(
              class="primary",
              disabled=model.busy || !approved,
              on_click=dispatch(SeedProjectFromIntake),
              "Create intake-bound project",
            ),
          ]),
          p(class="boundary-note", "The created brief, bible, and script copy the three exact MoonWiki intent records. No synthetic moonwiki:* ref is created."),
        ])
      }
    },
  ])
}

///|
fn render_operator_bar(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  section(class="operator-bar", [
    div(class="operator-title", [
      small("Named human authority"),
      strong("Every decision binds the displayed revision and digest"),
    ]),
    form_field("Actor", model.operator.actor, "named reviewer", fn(value) {
      dispatch(SetOperatorField("actor", value))
    }),
    form_field("Role", model.operator.role, "creative-director", fn(value) {
      dispatch(SetOperatorField("role", value))
    }),
    form_field("Decision time", model.operator.recorded_at, "ISO-8601", fn(
      value,
    ) {
      dispatch(SetOperatorField("recorded_at", value))
    }),
    button(
      class=if model.operator.human_confirmed {
        "confirmation confirmed"
      } else {
        "confirmation"
      },
      on_click=dispatch(SetHumanConfirmed(!model.operator.human_confirmed)),
      if model.operator.human_confirmed {
        "Human confirmation recorded"
      } else {
        "Confirm deliberate action"
      },
    ),
  ])
}

///|
fn gate_sequence() -> Array[String] {
  ["G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7"]
}

///|
fn gate_controlled_here(gate : String) -> Bool {
  gate == "G0" || gate == "G1" || gate == "G2" || gate == "G3"
}

///|
fn gate_passed(project : ProjectProjection, gate : String) -> Bool {
  match project.gates.get(gate) {
    Some(value) => value.status == "passed"
    None => false
  }
}

///|
fn render_gate_rail(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  div(
    class="gate-rail",
    gate_sequence().map(gate => {
      let value = project.gates
        .get(gate)
        .unwrap_or({ name: gate, status: "pending", receipt: None })
      article(class="gate-card " + status_tone(value.status), [
        div([strong(gate), status_chip(value.status)]),
        p(value.name),
        if value.status == "passed" {
          small("Immutable receipt recorded")
        } else if gate_controlled_here(gate) {
          button(
            class="secondary compact",
            disabled=model.busy ||
              !model.operator.human_confirmed ||
              next_gate(project) != Some(gate),
            on_click=dispatch(AdvanceGate(gate)),
            "Record evidence gate",
          )
        } else {
          small("Controlled in the dedicated downstream workspace")
        },
      ])
    }),
  )
}

///|
fn render_create_project(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let form = model.create
  section(class="panel create-project", [
    div(class="panel-heading", [
      div([small("G0 qualified scenario"), h2("Start a saleable episode")]),
      p(
        "A complete 3–8 minute production graph and seven version-one creative drafts will be created. No draft is approved automatically.",
      ),
    ]),
    div(class="form-grid", [
      form_field("Project id", form.project_id, "brand-episode-001", fn(value) {
        dispatch(SetCreateField("project_id", value))
      }),
      form_field("Title", form.title, "Episode title", fn(value) {
        dispatch(SetCreateField("title", value))
      }),
      text_field(
        "Payable objective",
        form.objective,
        "What accepted outcome does the customer buy?",
        4,
        fn(value) { dispatch(SetCreateField("objective", value)) },
      ),
      form_field("Audience", form.audience, "Specific audience", fn(value) {
        dispatch(SetCreateField("audience", value))
      }),
      form_field("Channels", form.channels, "review-only, douyin", fn(value) {
        dispatch(SetCreateField("channels", value))
      }),
      form_field("Rights owner", form.rights_owner, "Contract party", fn(
        value,
      ) {
        dispatch(SetCreateField("rights_owner", value))
      }),
      form_field("Duration seconds", form.duration_seconds, "180–480", fn(
        value,
      ) {
        dispatch(SetCreateField("duration", value))
      }),
      form_field("Maximum budget CNY", form.maximum_budget_cny, "20000", fn(
        value,
      ) {
        dispatch(SetCreateField("budget", value))
      }),
    ]),
    div(class="form-actions", [
      button(
        class=if form.rights_confirmed {
          "confirmation confirmed"
        } else {
          "confirmation"
        },
        on_click=dispatch(SetRightsConfirmed(!form.rights_confirmed)),
        if form.rights_confirmed {
          "Rights owner confirmed"
        } else {
          "Rights remain pending"
        },
      ),
      button(
        class="primary",
        disabled=model.busy,
        on_click=dispatch(CreateProject),
        "Create governed project",
      ),
    ]),
  ])
}

///|
fn render_overview(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection?,
) -> @rabbita.Html {
  match project {
    None => render_create_project(dispatch, model)
    Some(project) =>
      div(class="surface-stack", [
        section(class="hero panel", [
          div([
            small("\{project.contract} · revision \{project.revision}"),
            h1(project.title),
            p(class="lead", project.objective),
            div(class="chips", [
              status_chip(project.stage),
              status_chip(next_gate(project).unwrap_or("complete")),
            ]),
          ]),
          div(class="hero-facts", [
            strong("\{project.target_duration_seconds / 60} min"),
            span(project.audience),
            small(project.channels.join(" · ")),
          ]),
        ]),
        div(class="metrics", [
          metric(
            "Budget",
            "\{project.budget.currency} \{project.budget.maximum}",
            "Reserved \{project.budget.reserved} · spent \{project.budget.spent}",
          ),
          metric(
            "Production graph",
            "\{project.episodes.length()} episode · \{project.shots.length()} shots",
            "project → episode → scene → shot → asset",
          ),
          metric(
            "Provider cost",
            "CNY \{project.economics.provider_cost_cny}",
            "No provider cost is inferred or hidden",
          ),
          metric(
            "Release authority", "Not granted", "Publishing always requires a separate G6 authorization",
          ),
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("Evidence sequence"), h2("G0–G7 production gates")]),
            p("A later gate never compensates for a failed earlier gate."),
          ]),
          render_gate_rail(dispatch, model, project),
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("Canonical production graph"), h2("Episodes and scenes")]),
            p(
              "The graph supports 3–8 minute episodes now and longer productions without redesign.",
            ),
          ]),
          div(
            class="episode-grid",
            project.episodes.map(episode => {
              article(class="episode-card", [
                div([small(episode.id), h3(episode.title)]),
                ul(
                  episode.scenes.map(scene => {
                    li([
                      strong(scene.title),
                      span("\{scene.shot_ids.length()} shots"),
                    ])
                  }),
                ),
              ])
            }),
          ),
        ]),
      ])
  }
}

///|
fn artifact_kinds() -> Array[(String, String)] {
  [
    ("brief", "Brief"),
    ("rights-ledger", "Rights"),
    ("ip-bible", "IP bible"),
    ("script", "Script"),
    ("claims-ledger", "Claims"),
    ("storyboard", "Storyboard"),
    ("animatic", "Animatic"),
  ]
}

///|
fn render_creative(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection?,
) -> @rabbita.Html {
  match project {
    None => render_create_project(dispatch, model)
    Some(project) => {
      let artifact = artifact_for(project, model.selected_artifact_kind)
      div(class="creative-layout", [
        aside(class="artifact-rail panel", [
          div(class="panel-heading", [
            div([small("G0–G2"), h2("Creative evidence")]),
          ]),
          div(
            class="artifact-list",
            artifact_kinds().map(item => {
              let projection = artifact_for(project, item.0)
              button(
                class=if item.0 == model.selected_artifact_kind {
                  "artifact-item selected"
                } else {
                  "artifact-item"
                },
                on_click=dispatch(SelectArtifact(item.0)),
                [
                  strong(item.1),
                  status_chip(
                    projection.map(value => value.status).unwrap_or("missing"),
                  ),
                ],
              )
            }),
          ),
        ]),
        section(class="panel artifact-workbench", [
          match artifact {
            None =>
              div(class="empty-large", [
                h2("Artifact not created"),
                p("Create or refresh the project before review."),
              ])
            Some(value) =>
              div([
                div(class="panel-heading", [
                  div([
                    small("\{value.artifact_type} · version \{value.version}"),
                    h2("Review exact creative artifact"),
                  ]),
                  status_chip(value.status),
                ]),
                div(class="digest-row", [
                  span("Artifact digest"),
                  code(value.digest),
                ]),
                text_field(
                  "Versioned artifact JSON",
                  model.artifact_draft,
                  "Exact artifact content",
                  18,
                  fn(text) { dispatch(SetArtifactDraft(text)) },
                ),
                text_field(
                  "Decision note",
                  model.operator.note,
                  "Why this exact version passes or fails",
                  3,
                  fn(text) { dispatch(SetOperatorField("note", text)) },
                ),
                div(class="review-actions", [
                  button(
                    class="secondary",
                    disabled=model.busy,
                    on_click=dispatch(ReviseArtifact),
                    "Save new immutable version",
                  ),
                  button(
                    class="danger",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(DecideArtifact("rejected")),
                    "Reject exact version",
                  ),
                  button(
                    class="primary",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(DecideArtifact("approved")),
                    "Approve exact version",
                  ),
                ]),
                p(
                  class="boundary-note",
                  "Approval is immutable and digest-bound. A later revision requires a new decision.",
                ),
              ])
          },
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("After approved source assets"), h2("Lip-sync · translation · upscale")]),
            p(
              "Run first-class postprocess jobs with exact source versions, rights, prompt, provider/model, retry and cost evidence; import immutable outputs into a shot, the Cut Editor, or a delivery build.",
            ),
          ]),
          div(class="metrics", [
            metric(
              "Tasks",
              "\{model.postprocess_workspace.map(value => value.tasks.length()).unwrap_or(0)}",
              "Versioned provider routes",
            ),
            metric(
              "Outputs",
              "\{model.postprocess_workspace.map(value => value.outputs.length()).unwrap_or(0)}",
              "Immutable provenance",
            ),
            metric(
              "Imports",
              "\{model.postprocess_workspace.map(value => value.bindings.length()).unwrap_or(0)}",
              "Shot · editor · delivery",
            ),
            metric(
              "Actual cost",
              "CNY \{model.postprocess_workspace.map(value => value.total_cost_cny).unwrap_or(0.0)}",
              "Recorded provider spend",
            ),
          ]),
          text_field(
            "Postprocess task JSON",
            model.postprocess_task_draft,
            "Choose lip-sync, translation, or upscale and its exact bindings",
            16,
            fn(value) { dispatch(SetPostprocessTaskDraft(value)) },
          ),
          div(class="form-actions", [
            button(
              class="secondary",
              disabled=model.busy || !model.operator.human_confirmed,
              on_click=dispatch(RecordPostprocessTask),
              "Record exact task",
            ),
            button(
              class="primary",
              disabled=model.busy || !model.operator.human_confirmed ||
                model.postprocess_workspace.map(value => value.tasks.is_empty()).unwrap_or(true),
              on_click=dispatch(RunPostprocessTask),
              "Authorize / resume provider job",
            ),
          ]),
        ]),
      ])
    }
  }
}

///|
fn render_route(route : RouteProjection) -> @rabbita.Html {
  article(class="route-card", [
    div(class="route-heading", [
      div([small(route.route_id), h3(route.provider + " / " + route.model)]),
      status_chip(route.capability),
    ]),
    p(
      "\{route.asset_ids.length()} assets · data class \{route.permitted_data_class}",
    ),
    div(class="route-metrics", [
      span([small("Ceiling"), strong("CNY \{route.cost_ceiling_cny}")]),
      span([small("Retries"), strong("\{route.retry_policy.maximum_attempts}")]),
      span([small("Model version"), strong(route.model_version)]),
    ]),
    if route.fallback.is_empty() {
      small("No fallback route")
    } else {
      small("Fallback: " + route.fallback.join(", "))
    },
  ])
}

///|
fn render_routed_execution(
  dispatch : Dispatch[Msg],
  model : Model,
  execution : RoutedExecutionSummary,
) -> @rabbita.Html {
  article(class="execution-card", [
    div(class="route-heading", [
      div([small(execution.execution_id), h3("Multi-shot execution")]),
      status_chip(execution.state),
    ]),
    div(class="digest-row", [span("Binding"), code(execution.record_digest)]),
    div(class="form-actions", [
      button(
        class="primary",
        disabled=model.busy || !model.operator.human_confirmed,
        on_click=dispatch(RunAllPendingShots(execution.execution_id)),
        "Production coordinator: run pending shots",
      ),
    ]),
    p(
      class="boundary-note",
      "Preflights the complete exact shot/job binding, then executes and canonically adopts each pending output in sequence. It cannot publish or move money.",
    ),
    div(
      class="shot-job-list",
      execution.shots.map(binding => {
        div(class="shot-job", [
          div([
            strong(binding.shot_id),
            small(binding.route_id + " · CNY \{binding.cost_ceiling_cny}"),
          ]),
          div(class="inline-actions", [
            button(
              class="secondary compact",
              disabled=model.busy,
              on_click=dispatch(
                RunRoutedShot(
                  execution.execution_id,
                  binding.shot_id,
                  "execute",
                ),
              ),
              "Execute",
            ),
            button(
              class="secondary compact",
              disabled=model.busy,
              on_click=dispatch(
                RunRoutedShot(execution.execution_id, binding.shot_id, "resume"),
              ),
              "Resume",
            ),
            button(
              class="danger compact",
              disabled=model.busy,
              on_click=dispatch(
                RunRoutedShot(execution.execution_id, binding.shot_id, "cancel"),
              ),
              "Cancel",
            ),
          ]),
        ])
      }),
    ),
  ])
}

///|
fn render_routing(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection?,
) -> @rabbita.Html {
  match project {
    None => render_create_project(dispatch, model)
    Some(project) =>
      div(class="surface-stack", [
        section(class="panel", [
          div(class="panel-heading", [
            div([
              small("G3 planning authority"),
              h2("Record a bounded model-routing plan"),
            ]),
            p(
              "One explicit route currently covers every planned video shot; revisions remain digest-bound and may add specialized routes later.",
            ),
          ]),
          div(class="form-grid", [
            form_field(
              "Route id",
              model.routing_form.route_id,
              "primary-video-route",
              fn(value) { dispatch(SetRoutingField("route_id", value)) },
            ),
            form_field(
              "Provider",
              model.routing_form.provider,
              "approved provider adapter",
              fn(value) { dispatch(SetRoutingField("provider", value)) },
            ),
            form_field(
              "Model",
              model.routing_form.model,
              "approved video model",
              fn(value) { dispatch(SetRoutingField("model", value)) },
            ),
            form_field(
              "Pinned model version",
              model.routing_form.model_version,
              "exact version",
              fn(value) { dispatch(SetRoutingField("model_version", value)) },
            ),
            form_field(
              "Permitted data class",
              model.routing_form.permitted_data_class,
              "contract-cleared-production-assets",
              fn(value) { dispatch(SetRoutingField("data_class", value)) },
            ),
            form_field(
              "Per-shot route cost ceiling CNY",
              model.routing_form.cost_ceiling_cny,
              "6000",
              fn(value) { dispatch(SetRoutingField("cost", value)) },
            ),
            form_field(
              "Plan cost ceiling CNY",
              model.routing_form.total_cost_ceiling_cny,
              "6000",
              fn(value) { dispatch(SetRoutingField("total", value)) },
            ),
            form_field("Retry limit", model.routing_form.retry_limit, "1–5", fn(
              value,
            ) {
              dispatch(SetRoutingField("retry", value))
            }),
            form_field(
              "Fallback route ids",
              model.routing_form.fallback_route_ids,
              "comma-separated",
              fn(value) { dispatch(SetRoutingField("fallback", value)) },
            ),
          ]),
          div(class="form-actions", [
            button(
              class="secondary",
              disabled=model.busy || !model.operator.human_confirmed,
              on_click=dispatch(RecordRoutingPlan),
              if project.model_routing_plan is Some(_) {
                "Record routing revision"
              } else {
                "Record routing plan"
              },
            ),
            button(
              class="secondary",
              disabled=model.busy ||
                !model.operator.human_confirmed ||
                project.model_routing_plan is None,
              on_click=dispatch(DecideRouting("producer", "approve")),
              "Producer approval",
            ),
            button(
              class="primary",
              disabled=model.busy ||
                !model.operator.human_confirmed ||
                project.model_routing_plan is None,
              on_click=dispatch(DecideRouting("finance", "approve")),
              "Independent finance approval",
            ),
          ]),
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("G3 model router"), h2("Exact provider plan")]),
            button(
              class="primary",
              disabled=model.busy ||
                project.model_routing_plan is None ||
                !gate_passed(project, "G3") ||
                !model.operator.human_confirmed,
              on_click=dispatch(CreateRoutedExecution),
              "Create bounded multi-shot run",
            ),
          ]),
          match project.model_routing_plan {
            None =>
              div(class="empty-large", [
                h3("No approved routing plan"),
                p(
                  "Text, image, video, voice, music, lip-sync, translation and storage must be routed explicitly with cost and data constraints.",
                ),
              ])
            Some(plan) =>
              div([
                if gate_passed(project, "G3") {
                  p(class="boundary-note", "G3 production authorization is recorded for this exact routing plan.")
                } else {
                  p(class="boundary-note", "Before execution, approve the exact rendered animatic and both routing decisions, then record G3 from the evidence-gate rail.")
                },
                div(class="metrics", [
                  metric("Plan version", "\{plan.version}", plan.digest),
                  metric(
                    "Estimated",
                    "CNY \{plan.content.estimated_total_cny}",
                    "Before expensive generation",
                  ),
                  metric(
                    "Hard ceiling",
                    "CNY \{plan.content.total_ceiling_cny}",
                    "Execution stops at this boundary",
                  ),
                ]),
                div(class="route-grid", plan.content.routes.map(render_route)),
              ])
          },
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("Provider execution"), h2("Shot-bound jobs")]),
            p("Network and publication authorities remain separate."),
          ]),
          if model.routed.is_empty() {
            div(class="empty", "No routed execution created.")
          } else {
            div(
              class="execution-grid",
              model.routed.map(value => {
                render_routed_execution(dispatch, model, value)
              }),
            )
          },
        ]),
      ])
  }
}

///|
fn render_asset_factory(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.project {
    None => render_create_project(dispatch, model)
    Some(project) => {
      let workspace = model.asset_factory
      let plan_count = workspace.map(value => value.plans.length()).unwrap_or(0)
      let variant_count = workspace.map(value => value.variants.length()).unwrap_or(0)
      let approved_count = workspace.map(value => value.approved_assets.length()).unwrap_or(0)
      let binding_count = workspace.map(value => value.shot_bindings.length()).unwrap_or(0)
      div(class="surface-stack", [
        section(class="panel", [
          div(class="panel-heading", [
            div([
              small("Reusable assets before dependent shots"),
              h2("Multimodal Asset Factory"),
            ]),
            p(
              "Create immutable character, location, prop, voice, music, text, image and motion references. Every attempt is provider-, cost-, evidence- and rights-bound; this surface grants no publication authority.",
            ),
          ]),
          div(class="metrics", [
            metric("Plans", "\{plan_count}", "Exact project revision"),
            metric("Variants", "\{variant_count}", "Bounded attempts"),
            metric("Approved", "\{approved_count}", "Immutable references"),
            metric("Shot bindings", "\{binding_count}", "Exact versions"),
          ]),
          text_field(
            "Asset factory plan JSON",
            model.asset_plan_draft,
            "MoonWiki-backed reusable asset specifications",
            18,
            fn(value) { dispatch(SetAssetPlanDraft(value)) },
          ),
          div(class="form-actions", [
            button(
              class="secondary",
              disabled=model.busy || !model.operator.human_confirmed,
              on_click=dispatch(RecordAssetPlan),
              "Record exact plan",
            ),
            button(
              class="secondary",
              disabled=model.busy || !model.operator.human_confirmed || plan_count == 0,
              on_click=dispatch(DecideAssetPlan("approve")),
              "Approve plan",
            ),
            button(
              class="primary",
              disabled=model.busy || !model.operator.human_confirmed || plan_count == 0,
              on_click=dispatch(RunAssetFactory),
              "Authorize and run bounded variants",
            ),
            button(
              class="secondary",
              disabled=model.busy ||
                !model.operator.human_confirmed ||
                approved_count == 0,
              on_click=dispatch(BindAssetFactoryShots),
              "Bind approved versions to shots",
            ),
          ]),
        ]),
        section(class="panel", [
          div(class="panel-heading", [
            div([small("Technical · identity · continuity · rights · safety"), h2("Variant QC and immutable approval")]),
            p(
              "A named reviewer records all five dimensions before selecting one reusable version. Validation fixtures are not commercial media.",
            ),
          ]),
          match workspace {
            None => p(class="empty", "Load an asset factory workspace.")
            Some(value) if value.variants.is_empty() =>
              p(class="empty", "Approve a plan and run bounded variants.")
            Some(value) =>
              div(
                class="resource-list",
                value.variants.map(variant => {
                  let approved = value.approved_assets.any(asset => {
                    asset.variant_id == variant.variant_id
                  })
                  article(class="resource-card", [
                    div([
                      strong(variant.asset_id + " · " + variant.modality),
                      status_chip(if approved { "approved" } else { variant.state }),
                    ]),
                    code(variant.variant_id),
                    small(
                      "Version \{variant.asset_version} · variant \{variant.variant} · CNY \{variant.cost_cny}",
                    ),
                    div(class="form-actions", [
                      button(
                        class="secondary",
                        disabled=model.busy ||
                          !model.operator.human_confirmed ||
                          variant.state != "completed",
                        on_click=dispatch(RecordAssetVariantQc(variant.variant_id)),
                        "Record five-dimension QC",
                      ),
                      button(
                        class="primary",
                        disabled=model.busy ||
                          !model.operator.human_confirmed ||
                          variant.state != "completed" ||
                          approved,
                        on_click=dispatch(ApproveAssetVariant(variant.variant_id)),
                        if approved { "Approved immutable" } else { "Approve selected output" },
                      ),
                    ]),
                  ])
                }),
              )
          },
        ]),
      ])
    }
  }
}

///|
fn render_storyboard_animatic(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  match model.project {
    None => render_create_project(dispatch, model)
    Some(project) => {
      let workspace = model.animatic_workspace
      let attempts = workspace.map(value => value.attempts.length()).unwrap_or(0)
      let renders = workspace.map(value => value.renders.length()).unwrap_or(0)
      let approvals = workspace.map(value => value.approvals.length()).unwrap_or(0)
      let latest : AnimaticRenderProjection? = match workspace {
        Some(value) if !value.renders.is_empty() =>
          Some(value.renders[value.renders.length() - 1])
        _ => None
      }
      div(class="surface-stack", [
        section(class="panel", [
          div(class="panel-heading", [
            div([small("G3 real-media approval"), h2("Rendered storyboard and timed animatic")]),
            p(
              "Bind the approved bible, script, storyboard, exact reusable asset versions, temporary voice/music, captions, transitions, provider evidence and budget before expensive shot generation.",
            ),
          ]),
          div(class="metrics", [
            metric("Panels", "\{project.shots.length()}", "Exact shot timing"),
            metric("Attempts", "\{attempts}", "Retry/resume ledger"),
            metric("Renders", "\{renders}", "Immutable native media"),
            metric("Approvals", "\{approvals}", "Named-human exact digest"),
          ]),
          text_field(
            "Storyboard / animatic plan JSON",
            model.animatic_plan_draft,
            "Complete G3 animatic plan",
            18,
            fn(value) { dispatch(SetAnimaticPlanDraft(value)) },
          ),
          div(class="form-actions", [
            button(
              class="secondary",
              disabled=model.busy || !model.operator.human_confirmed,
              on_click=dispatch(RecordAnimaticPlan),
              "Record exact plan",
            ),
            button(
              class="primary",
              disabled=model.busy || !model.operator.human_confirmed ||
                workspace.map(value => value.plans.is_empty()).unwrap_or(true),
              on_click=dispatch(RenderAnimatic),
              if attempts > 0 && renders == 0 { "Resume / retry render" } else { "Render sheet + timed MP4" },
            ),
            button(
              class="primary",
              disabled=model.busy || !model.operator.human_confirmed || latest is None,
              on_click=dispatch(ApproveRenderedAnimatic),
              "Approve exact rendered version",
            ),
          ]),
          p(
            class="boundary-note",
            "Local rendering is an explicit process effect only. It performs no provider network call and grants no publication authority.",
          ),
        ]),
        match latest {
          None =>
            section(class="panel", [
              h3("Render gaps"),
              p(
                if model.asset_factory.map(value => value.approved_assets.is_empty()).unwrap_or(true) {
                  "Approve reusable visual, voice, and music assets first."
                } else {
                  "Record the exact plan, then render the production-length approval media."
                },
              ),
            ])
          Some(render) => {
            let base = "/api/v2/projects/" + project.id + "/animatic-workspace/renders/" + render.reference.version.to_string()
            section(class="panel", [
              div(class="panel-heading", [
                div([small("Immutable render v\{render.reference.version}"), h2("Review actual timing before G3")]),
                status_chip(if approvals > 0 { "approved" } else { "review-required" }),
              ]),
              @html.img(
                class="animatic-sheet",
                src=base + "/sheet",
                alt="Rendered storyboard contact sheet",
                loading="lazy",
              ),
              @html.video(
                class="animatic-player",
                src=base + "/video",
                controls=true,
                preload="metadata",
                @html.nothing,
              ),
              div(class="metrics", [
                metric("Duration", "\{render.duration_seconds}s", "\{render.panel_count} timed panels"),
                metric("Actual cost", "CNY \{render.budget.actual_cny}", "Ceiling CNY \{render.budget.planned_cny}"),
                metric("Provider", render.provider, render.model),
                metric("Provenance", "Immutable", render.video_digest),
              ]),
              div(class="form-actions", [
                a(class="secondary", href=base + "/sheet", "Download storyboard sheet"),
                a(class="secondary", href=base + "/video", "Download timed animatic"),
              ]),
            ])
          }
        },
      ])
    }
  }
}

///|
fn render_shot_board(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection?,
) -> @rabbita.Html {
  match project {
    None => div(class="empty-large", [h2("No project open")])
    Some(project) =>
      div(class="surface-stack", [
        section(class="panel", [
          div(class="panel-heading", [
            div([small("G4 production floor"), h2("Scene and shot board")]),
            p(
              "Each shot carries identity, timing, provider attempt, five-dimensional QC and asset lineage.",
            ),
          ]),
          div(
            class="shot-grid",
            project.shots.map(shot => {
              article(
                class=if shot.id == model.qc_form.shot_id {
                  "shot-card selected"
                } else {
                  "shot-card"
                },
                [
                  div(class="shot-card-head", [
                    div([
                      small("\{shot.scene_id} · #\{shot.order}"),
                      h3(shot.id),
                    ]),
                    status_chip(shot.status),
                  ]),
                  div(class="shot-placeholder", [
                    span("SHOT"),
                    strong("\{shot.duration_seconds}s"),
                  ]),
                  p(shot.prompt),
                  ul(class="shot-facts", [
                    li([span("Framing"), strong(shot.framing)]),
                    li([span("Location"), strong(shot.location)]),
                    li([span("QC"), status_chip(shot.qc.status)]),
                    li([
                      span("Attempt"),
                      code(shot.provider_attempt_id.unwrap_or("not generated")),
                    ]),
                  ]),
                  button(
                    class="secondary",
                    on_click=dispatch(SelectQcShot(shot.id)),
                    "Open evidence workbench",
                  ),
                ],
              )
            }),
          ),
        ]),
        render_qc_workbench(dispatch, model, project),
      ])
  }
}

///|
fn render_qc_workbench(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  let form = model.qc_form
  section(class="panel", [
    div(class="panel-heading", [
      div([small("Independent evidence"), h2("Generation and QC workbench")]),
      p(
        "Record the provider result once, then create and independently decide each technical, continuity, safety, claims and rights finding.",
      ),
    ]),
    div(class="metrics", [
      metric(
        "Selected shot",
        if form.shot_id == "" {
          "None"
        } else {
          form.shot_id
        },
        "\{project.shots.length()} shots in project",
      ),
      metric("Output binding", form.output_digest, "Successful attempt digest"),
      metric("QC dimension", form.dimension, "All five dimensions must pass"),
      metric(
        "Finding binding",
        if form.finding_digest == "" {
          "new finding"
        } else {
          "v" + form.finding_version
        },
        form.finding_digest,
      ),
    ]),
    div(class="qc-divider", ([] : Array[@rabbita.Html])),
    div(class="panel-heading", [
      div([small("Machine evidence, human decision"), h2("Automated analyzer jobs")]),
      p(
        "Run codec, duration, blank-frame, audio, subtitle, flicker, lip-sync, identity and continuity analyzers against the exact output. Receipts create evidence-bound findings but never approve them.",
      ),
    ]),
    div(class="metrics", [
      metric(
        "Analyzer tasks",
        "\{model.analyzer_workspace.map(value => value.tasks.length()).unwrap_or(0)}",
        "Local technical or external semantic",
      ),
      metric(
        "Receipts",
        "\{model.analyzer_workspace.map(value => value.receipts.length()).unwrap_or(0)}",
        "Immutable measurements",
      ),
      metric(
        "Findings",
        "\{model.analyzer_workspace.map(value => value.findings.length()).unwrap_or(0)}",
        "Still require human decisions",
      ),
      metric(
        "Human decisions",
        "\{model.analyzer_workspace.map(value => value.human_decisions).unwrap_or(0)}",
        "Never performed by analyzers",
      ),
    ]),
    text_field(
      "Analyzer task JSON",
      model.analyzer_task_draft,
      "Choose one exact technical or semantic analyzer",
      16,
      fn(value) { dispatch(SetAnalyzerTaskDraft(value)) },
    ),
    div(class="form-actions", [
      button(
        class="secondary",
        disabled=model.busy || !model.operator.human_confirmed,
        on_click=dispatch(RecordAnalyzerTask),
        "Record analyzer task",
      ),
      button(
        class="primary",
        disabled=model.busy || !model.operator.human_confirmed ||
          model.analyzer_workspace.map(value => value.tasks.is_empty()).unwrap_or(true),
        on_click=dispatch(RunAnalyzerTask),
        "Run / resume analyzer",
      ),
    ]),
    div(class="form-grid", [
      form_field("Shot id", form.shot_id, "select a shot above", fn(value) {
        dispatch(SetQcField("shot_id", value))
      }),
      form_field("Attempt id", form.attempt_id, "attempt-001", fn(value) {
        dispatch(SetQcField("attempt_id", value))
      }),
      form_field("Route id", form.route_id, "approved route", fn(value) {
        dispatch(SetQcField("route_id", value))
      }),
      form_field("Prompt digest", form.prompt_digest, "sha256:…", fn(value) {
        dispatch(SetQcField("prompt_digest", value))
      }),
      form_field(
        "Source asset digests",
        form.source_asset_digests,
        "comma-separated",
        fn(value) { dispatch(SetQcField("sources", value)) },
      ),
      form_field("Attempt cost CNY", form.cost_cny, "0", fn(value) {
        dispatch(SetQcField("cost", value))
      }),
      form_field("Output digest", form.output_digest, "sha256:…", fn(value) {
        dispatch(SetQcField("output", value))
      }),
      form_field("Attempt status", form.attempt_status, "succeeded", fn(value) {
        dispatch(SetQcField("attempt_status", value))
      }),
    ]),
    div(class="form-actions", [
      button(
        class="secondary",
        disabled=model.busy || form.shot_id == "",
        on_click=dispatch(RecordGenerationAttempt),
        "Record attempt evidence",
      ),
    ]),
    div(class="qc-divider", ([] : Array[@rabbita.Html])),
    div(class="form-grid", [
      form_field(
        "QC dimension",
        form.dimension,
        "technical / continuity / safety / claims / rights",
        fn(value) { dispatch(SetQcField("dimension", value)) },
      ),
      form_field("Finding status", form.finding_status, "pass / fail", fn(
        value,
      ) {
        dispatch(SetQcField("finding_status", value))
      }),
      form_field("Evidence digest", form.evidence_digest, "sha256:…", fn(
        value,
      ) {
        dispatch(SetQcField("evidence", value))
      }),
      form_field("Current finding version", form.finding_version, "1", fn(
        value,
      ) {
        dispatch(SetQcField("finding_version", value))
      }),
      form_field(
        "Current finding digest",
        form.finding_digest,
        "paste refreshed exact digest before decision",
        fn(value) { dispatch(SetQcField("finding_digest", value)) },
      ),
      text_field(
        "Finding / decision note",
        form.note,
        "Observed evidence and independent rationale",
        3,
        fn(value) { dispatch(SetQcField("note", value)) },
      ),
    ]),
    div(class="review-actions", [
      button(
        class="primary",
        disabled=model.busy ||
          !model.operator.human_confirmed ||
          model.operator.actor.trim() == "" ||
          model.operator.role.trim() == "" ||
          form.evidence_digest.trim() == "" ||
          form.evidence_digest.contains("required") ||
          !project.shots.all(shot => {
            shot.status == "generated" && shot.asset_id is Some(_)
          }),
        on_click=dispatch(ConfirmBatchQc),
        "Production coordinator: confirm batch QC",
      ),
      button(
        class="secondary",
        disabled=model.busy || form.shot_id == "",
        on_click=dispatch(RecordQcFinding),
        "Record finding",
      ),
      button(
        class="danger",
        disabled=model.busy ||
          !model.operator.human_confirmed ||
          form.finding_digest == "",
        on_click=dispatch(DecideQc("reject")),
        "Reject finding",
      ),
      button(
        class="primary",
        disabled=model.busy ||
          !model.operator.human_confirmed ||
          form.finding_digest == "",
        on_click=dispatch(DecideQc("approve")),
        "Approve exact finding",
      ),
    ]),
    p(
      class="boundary-note",
      "Batch QC binds the complete current shot/output set and expands one explicit named confirmation into separate Technical, Continuity, Safety, Claims and Rights findings plus decisions. It rejects stale, partial, failing or already-rejected evidence; G4 opens only after every exact receipt exists.",
    ),
  ])
}

///|
fn render_delivery_build(
  dispatch : Dispatch[Msg],
  model : Model,
  build : DeliveryBuildProjection,
) -> @rabbita.Html {
  article(class="delivery-card", [
    div(class="route-heading", [
      div([small(build.build_id), h3("Delivery package")]),
      status_chip(build.state),
    ]),
    div(class="delivery-facts", [
      span([small("Attempts"), strong("\{build.attempt_count}")]),
      span([small("Recoveries"), strong("\{build.recovery_count}")]),
      span([small("Publication"), strong("not granted")]),
    ]),
    div(class="digest-row", [span("Build digest"), code(build.build_digest)]),
    match build.last_error {
      Some(value) => p(class="inline-error", value)
      None => @html.nothing
    },
    div(class="review-actions", [
      button(
        class="secondary",
        disabled=model.busy,
        on_click=dispatch(RunDeliveryAction(build.build_id, "build")),
        "Build / resume",
      ),
      button(
        class="secondary",
        disabled=model.busy,
        on_click=dispatch(RunDeliveryAction(build.build_id, "retry")),
        "Retry",
      ),
      button(
        class="danger",
        disabled=model.busy,
        on_click=dispatch(RunDeliveryAction(build.build_id, "cancel")),
        "Cancel",
      ),
      button(
        class="primary",
        disabled=model.busy ||
          build.state != "completed" ||
          !model.operator.human_confirmed,
        on_click=dispatch(AcceptDelivery(build.build_id)),
        "Accept exact build",
      ),
      match build.download_url {
        Some(url) => a(class="primary-link", href=url, "Download package")
        None => @html.nothing
      },
    ]),
  ])
}

///|
fn render_delivery(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection?,
) -> @rabbita.Html {
  match project {
    None => div(class="empty-large", [h2("No project open")])
    Some(project) =>
      div(class="surface-stack", [
        section(class="panel", [
          div(class="panel-heading", [
            div([
              small("G5 delivery factory"),
              h2("Masters, variants, cuts and provenance"),
            ]),
            button(
              class="primary",
              disabled=model.busy ||
                project.master is None ||
                project.delivery_package is None,
              on_click=dispatch(CreateDeliveryBuild),
              "Create delivery build",
            ),
          ]),
          div(class="metrics", [
            metric(
              "Reviewed master",
              if project.master is Some(_) {
                "Ready"
              } else {
                "Missing"
              },
              "Promoted only from an exact editor export",
            ),
            metric(
              "Delivery intent",
              if project.delivery_package is Some(_) {
                "Versioned"
              } else {
                "Missing"
              },
              "Horizontal, vertical, cuts, covers, subtitles and metadata",
            ),
            metric(
              "AI labels", "Required", "Explicit and implicit labels included in manifest",
            ),
            metric(
              "Publication", "Separately authorized", "Delivery acceptance cannot publish",
            ),
          ]),
        ]),
        render_delivery_governance(dispatch, model, project),
        if model.delivery_builds.is_empty() {
          div(class="panel empty-large", [
            h3("No build yet"),
            p(
              "Promote a reviewed master and record delivery intent before packaging.",
            ),
          ])
        } else {
          div(
            class="delivery-grid",
            model.delivery_builds.map(build => {
              render_delivery_build(dispatch, model, build)
            }),
          )
        },
        render_client_operations(dispatch, model, project),
      ])
  }
}

///|
fn render_client_operations(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  let form = model.client_ops_form
  div(class="surface-stack", [
    section(class="panel", [
      div(class="panel-heading", [
        div([
          small("Client acceptance workspace"),
          h2("Expiring review portals"),
        ]),
        p(
          "A token is returned once and binds one accepted build. Portal access never exposes provider secrets or grants publication authority.",
        ),
      ]),
      div(class="form-grid", [
        form_field("Client name", form.client_name, "Named client reviewer", fn(
          value,
        ) {
          dispatch(SetClientOpsField("client_name", value))
        }),
        form_field("Brand name", form.brand_name, "Client-facing brand", fn(
          value,
        ) {
          dispatch(SetClientOpsField("brand_name", value))
        }),
        form_field("Brand accent", form.brand_accent, "#b8ff61", fn(value) {
          dispatch(SetClientOpsField("brand_accent", value))
        }),
        form_field("Expires at", form.expires_at, "ISO-8601", fn(value) {
          dispatch(SetClientOpsField("expires_at", value))
        }),
      ]),
      div(class="form-actions", [
        button(
          class="primary",
          disabled=model.busy || !model.operator.human_confirmed,
          on_click=dispatch(CreateClientPortal),
          "Create one-time client URL",
        ),
      ]),
      match model.latest_client_url {
        Some(url) =>
          div(class="one-time-url", [
            strong("Copy this URL now"),
            code(url),
            a(class="primary-link", href=url, "Open Client Review"),
          ])
        None => @html.nothing
      },
      if model.client_portals.is_empty() {
        p(class="empty", "No client portal recorded.")
      } else {
        div(
          class="portal-list",
          model.client_portals.map(portal => {
            article(class="portal-card", [
              div(class="route-heading", [
                div([small(portal.portal_id), h3(portal.client_name)]),
                status_chip(portal.status),
              ]),
              p(portal.brand.name + " · expires " + portal.expires_at),
              div(class="digest-row", [span("Build"), code(portal.build_digest)]),
              div(class="review-actions", [
                button(
                  class="danger",
                  disabled=model.busy ||
                    !model.operator.human_confirmed ||
                    portal.status != "active",
                  on_click=dispatch(
                    ControlClientPortal(portal.portal_id, "revoke"),
                  ),
                  "Revoke",
                ),
                button(
                  class="secondary",
                  disabled=model.busy ||
                    !model.operator.human_confirmed ||
                    portal.status != "active",
                  on_click=dispatch(
                    ControlClientPortal(portal.portal_id, "expire"),
                  ),
                  "Expire now",
                ),
              ]),
            ])
          }),
        )
      },
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Milestone economics"), h2("Billing evidence, not payments")]),
        p(
          "Deposit, approved animatic and accepted-master states are recorded locally. No control executes or confirms a payment without an external reference.",
        ),
      ]),
      div(class="form-grid", [
        form_field(
          "Milestone kind",
          form.billing_kind,
          "deposit / approved-animatic / accepted-master",
          fn(value) { dispatch(SetClientOpsField("billing_kind", value)) },
        ),
        form_field(
          "Initial state",
          form.billing_state,
          "quoted / due / paid / waived",
          fn(value) { dispatch(SetClientOpsField("billing_state", value)) },
        ),
        form_field("Currency", form.billing_currency, "CNY", fn(value) {
          dispatch(SetClientOpsField("billing_currency", value))
        }),
        form_field("Amount", form.billing_amount, "0", fn(value) {
          dispatch(SetClientOpsField("billing_amount", value))
        }),
        form_field("Due at", form.billing_due_at, "ISO-8601", fn(value) {
          dispatch(SetClientOpsField("billing_due_at", value))
        }),
        form_field(
          "External reference",
          form.billing_reference,
          "contract/invoice/payment receipt ref",
          fn(value) { dispatch(SetClientOpsField("billing_reference", value)) },
        ),
      ]),
      div(class="form-actions", [
        button(
          class="secondary",
          disabled=model.busy || !model.operator.human_confirmed,
          on_click=dispatch(CreateBillingEntry),
          "Record milestone",
        ),
      ]),
      div(
        class="billing-list",
        model.billing_entries.map(entry => {
          article(class="billing-card", [
            div(class="route-heading", [
              div([small(entry.billing_id), h3(entry.kind)]),
              status_chip(entry.state),
            ]),
            strong("\{entry.currency} \{entry.amount}"),
            small(entry.reference),
            div(class="review-actions", [
              button(
                class="secondary compact",
                disabled=model.busy || !model.operator.human_confirmed,
                on_click=dispatch(TransitionBilling(entry.billing_id, "due")),
                "Due",
              ),
              button(
                class="secondary compact",
                disabled=model.busy || !model.operator.human_confirmed,
                on_click=dispatch(TransitionBilling(entry.billing_id, "paid")),
                "Paid + receipt",
              ),
              button(
                class="danger compact",
                disabled=model.busy || !model.operator.human_confirmed,
                on_click=dispatch(TransitionBilling(entry.billing_id, "waived")),
                "Waive",
              ),
            ]),
            p(
              class="boundary-note",
              if entry.payment_effect_performed {
                "External payment effect recorded"
              } else {
                "No payment effect performed by Mooncast"
              },
            ),
          ])
        }),
      ),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Repeat revenue"), h2("Create a fresh repeat-order draft")]),
        p(
          "Only explicitly reusable bible/assets may carry forward. Client and publication approvals always reset.",
        ),
      ]),
      div(class="form-grid", [
        form_field(
          "New project id",
          form.repeat_project_id,
          "repeat-episode-002",
          fn(value) { dispatch(SetClientOpsField("repeat_project_id", value)) },
        ),
        form_field("Title", form.repeat_title, "Repeat episode", fn(value) {
          dispatch(SetClientOpsField("repeat_title", value))
        }),
        text_field(
          "Objective",
          form.repeat_objective,
          "Next accepted customer outcome",
          3,
          fn(value) { dispatch(SetClientOpsField("repeat_objective", value)) },
        ),
        form_field("Audience", form.repeat_audience, project.audience, fn(
          value,
        ) {
          dispatch(SetClientOpsField("repeat_audience", value))
        }),
        form_field(
          "Rights owner",
          form.repeat_rights_owner,
          "Reconfirmed rights owner",
          fn(value) {
            dispatch(SetClientOpsField("repeat_rights_owner", value))
          },
        ),
        form_field(
          "Duration seconds",
          form.repeat_duration_seconds,
          "180–480",
          fn(value) { dispatch(SetClientOpsField("repeat_duration", value)) },
        ),
        form_field("Maximum budget CNY", form.repeat_budget_cny, "20000", fn(
          value,
        ) {
          dispatch(SetClientOpsField("repeat_budget", value))
        }),
      ]),
      div(class="form-actions", [
        button(
          class="primary",
          disabled=model.busy || !model.operator.human_confirmed,
          on_click=dispatch(CreateRepeatOrder),
          "Create repeat-order draft",
        ),
      ]),
      p(
        class="boundary-note",
        "The new project starts with draft creative artifacts, fresh rights confirmation, no client approval and no publication authority.",
      ),
    ]),
  ])
}

///|
fn render_delivery_governance(
  dispatch : Dispatch[Msg],
  model : Model,
  project : ProjectProjection,
) -> @rabbita.Html {
  let form = model.delivery_governance_form
  div(class="surface-stack", [
    section(class="panel", [
      div(class="panel-heading", [
        div([
          small("G5 exact master"),
          h2("Master lineage and four-role review"),
        ]),
        p(
          "Technical QC, creative direction and rights/compliance clear the promoted editor master for client review. Client approval can only come from the exact client portal.",
        ),
      ]),
      div(class="form-grid", [
        form_field("Video digest", form.video_digest, "sha256:…", fn(value) {
          dispatch(SetDeliveryGovernanceField("video", value))
        }),
        form_field("Audio digest", form.audio_digest, "sha256:…", fn(value) {
          dispatch(SetDeliveryGovernanceField("audio", value))
        }),
        form_field("Subtitle digest", form.subtitle_digest, "sha256:…", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("subtitle", value))
        }),
        form_field("Provenance digest", form.provenance_digest, "sha256:…", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("provenance", value))
        }),
        form_field("AI label", form.ai_label, "ai-assisted-production", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("ai_label", value))
        }),
      ]),
      div(class="form-actions", [
        button(
          class="secondary",
          disabled=model.busy || !model.operator.human_confirmed,
          on_click=dispatch(RecordMaster),
          if project.master is Some(_) {
            "Record master revision"
          } else {
            "Record exact master"
          },
        ),
      ]),
      div(class="master-review-grid", [
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.master is None,
          on_click=dispatch(DecideMaster("technical-qc", "approve")),
          "Technical QC approve",
        ),
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.master is None,
          on_click=dispatch(DecideMaster("creative-director", "approve")),
          "Creative director approve",
        ),
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.master is None,
          on_click=dispatch(DecideMaster("rights-compliance", "approve")),
          "Rights/compliance approve",
        ),
        p(
          class="boundary-note",
          "Client authority is unavailable in Studio. Create the bound review portal and let the named client accept or request revisions there.",
        ),
      ]),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([
          small("G5 delivery intent"),
          h2("Destination package and milestone acceptance"),
        ]),
        p(
          "This is the canonical delivery intent. The delivery factory below materializes its exact variants, cuts, covers, subtitles and manifests.",
        ),
      ]),
      div(class="form-grid", [
        form_field("Destination ids", form.destination_ids, "comma-separated", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("destinations", value))
        }),
        form_field("Manifest digest", form.manifest_digest, "sha256:…", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("manifest", value))
        }),
        form_field(
          "Rights ledger digest",
          form.rights_ledger_digest,
          "sha256:…",
          fn(value) { dispatch(SetDeliveryGovernanceField("rights", value)) },
        ),
      ]),
      div(class="review-actions", [
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.master is None,
          on_click=dispatch(RecordDeliveryPackage),
          if project.delivery_package is Some(_) {
            "Record delivery revision"
          } else {
            "Record delivery package"
          },
        ),
        button(
          class="danger",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.delivery_package is None,
          on_click=dispatch(RecordDeliveryMilestone("request-revision")),
          "Request delivery revision",
        ),
        p(
          class="boundary-note",
          "Exact-package acceptance is reconciled automatically from the real client portal decision.",
        ),
      ]),
    ]),
    section(class="panel publication-panel", [
      div(class="panel-heading", [
        div([
          small("G6 destination authority"),
          h2("Authorize separately; observe only after host effect"),
        ]),
        p(
          "These controls do not publish. Authorization is inert. Observation requires a receipt from a separately authorized publishing host.",
        ),
      ]),
      div(class="form-grid", [
        form_field(
          "Destination",
          form.destination_id,
          "douyin / wechat / client-delivery",
          fn(value) {
            dispatch(SetDeliveryGovernanceField("destination", value))
          },
        ),
        form_field(
          "Exact scope",
          form.publication_scope,
          "exact accepted delivery package only",
          fn(value) { dispatch(SetDeliveryGovernanceField("scope", value)) },
        ),
        form_field(
          "Authorization expiry",
          form.publication_expires_at,
          "optional ISO-8601",
          fn(value) { dispatch(SetDeliveryGovernanceField("expires", value)) },
        ),
      ]),
      div(class="review-actions", [
        button(
          class="danger",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.delivery_package is None,
          on_click=dispatch(AuthorizePublication("deny")),
          "Deny destination",
        ),
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.delivery_package is None,
          on_click=dispatch(AuthorizePublication("authorize")),
          "Record inert authorization",
        ),
      ]),
      div(class="form-grid observation-fields", [
        form_field(
          "External publication receipt digest",
          form.publication_receipt_digest,
          "from separately controlled host",
          fn(value) { dispatch(SetDeliveryGovernanceField("receipt", value)) },
        ),
        form_field(
          "External authority reference",
          form.publication_authority_ref,
          "authority:…",
          fn(value) {
            dispatch(SetDeliveryGovernanceField("authority_ref", value))
          },
        ),
      ]),
      div(class="form-actions", [
        button(
          class="secondary",
          disabled=model.busy ||
            form.publication_receipt_digest == "" ||
            !form.publication_authority_ref.has_prefix("authority:"),
          on_click=dispatch(RecordPublicationObservation),
          "Record already-performed publication",
        ),
      ]),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([
          small("G7 operating evidence"),
          h2("Performance, economics and repeat purchase"),
        ]),
        p(
          "First record customer and channel outcomes against the exact delivery. Then explicitly prepare an immutable MoonFlow/Bookkeeper outbox bundle for independent Three-Gap review; Studio does not transmit it.",
        ),
      ]),
      div(class="form-grid", [
        form_field("Review status", form.performance_status, "observed", fn(
          value,
        ) {
          dispatch(SetDeliveryGovernanceField("performance_status", value))
        }),
        form_field(
          "Evidence digest",
          form.performance_evidence_digest,
          "optional; generated if blank",
          fn(value) {
            dispatch(SetDeliveryGovernanceField("performance_evidence", value))
          },
        ),
        form_field("Reach", form.reach, "0", fn(value) {
          dispatch(SetDeliveryGovernanceField("reach", value))
        }),
        form_field("Completion rate", form.completion_rate, "0–1", fn(value) {
          dispatch(SetDeliveryGovernanceField("completion", value))
        }),
        form_field("Conversion rate", form.conversion_rate, "0–1", fn(value) {
          dispatch(SetDeliveryGovernanceField("conversion", value))
        }),
        form_field("Recognized revenue CNY", form.revenue_cny, "0", fn(value) {
          dispatch(SetDeliveryGovernanceField("revenue", value))
        }),
        form_field("Provider cost CNY", form.provider_cost_cny, "0", fn(value) {
          dispatch(SetDeliveryGovernanceField("provider_cost", value))
        }),
        form_field("Founder hours", form.founder_hours, "0", fn(value) {
          dispatch(SetDeliveryGovernanceField("founder_hours", value))
        }),
        form_field(
          "Repeat purchase",
          form.repeat_purchase_status,
          "not-yet-observed / paid-repeat",
          fn(value) { dispatch(SetDeliveryGovernanceField("repeat", value)) },
        ),
      ]),
      div(class="form-actions", [
        button(
          class="primary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            project.delivery_package is None,
          on_click=dispatch(RecordPerformanceReview),
          "Record G7 review",
        ),
      ]),
      if project.outcome_handoff.eligible_final_deliverables.is_empty() {
        p(
          class="empty",
          "No accepted final-deliverable evidence is available yet. Complete the editor export, real client-portal acceptance, and final-deliverable handoff first.",
        )
      } else {
        div(
          class="portal-list",
          project.outcome_handoff.eligible_final_deliverables.map(candidate => {
            article(class="portal-card", [
              div(class="route-heading", [
                div([
                  small("Accepted final deliverable"),
                  h3(candidate.episode_id),
                ]),
                status_chip(
                  if project.outcome_handoff.production_outcomes.any(value => {
                      match value {
                        Object(fields) =>
                          match fields.get("final_deliverable_ref") {
                            Some(Object(reference)) =>
                              reference.get("record_id") ==
                              Some(candidate.record.record_id.to_json())
                            _ => false
                          }
                        _ => false
                      }
                    }) {
                    "completed"
                  } else {
                    "ready"
                  },
                ),
              ]),
              div(class="digest-row", [
                span("Evidence"),
                code(candidate.record.record_id),
              ]),
              div(class="digest-row", [
                span("Export"),
                code(candidate.export_job_id),
              ]),
              div(class="form-actions", [
                button(
                  class="secondary",
                  disabled=model.busy ||
                    !model.operator.human_confirmed ||
                    project.performance_reviews.is_empty(),
                  on_click=dispatch(
                    PrepareOutcomeHandoff(candidate.record.record_id),
                  ),
                  "Prepare immutable outcome outbox",
                ),
              ]),
            ])
          }),
        )
      },
      p(
        class="boundary-note",
        "Prepared outcomes: \{project.outcome_handoff.production_outcomes.length()} · inert handoff requests: \{project.outcome_handoff.external_handoff_requests.length()} · publication false · payment false · external effect false",
      ),
    ]),
  ])
}

///|
fn render_commercial(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  let form = model.commercial_form
  let counts = match model.commercial {
    Some(value) =>
      (
        value.leads.length(),
        value.quotes.length(),
        value.resources.length(),
        value.reservations.length(),
      )
    None => (0, 0, 0, 0)
  }
  div(class="surface-stack", [
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Before G0"), h2("Qualified paid scenario")]),
        p(
          "Reject work without measurable acceptance, a payment path, baseline economics, or a plausible repeat order.",
        ),
      ]),
      div(class="metrics", [
        metric("Leads", "\{counts.0}", "Draft payable problems"),
        metric(
          "Quotes",
          "\{counts.1}",
          "Immutable versions with margin forecasts",
        ),
        metric("Resources", "\{counts.2}", "Finite production capacity"),
        metric(
          "Reservations",
          "\{counts.3}",
          "Dependency-aware capacity bindings",
        ),
      ]),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Design partner intake"), h2("Record a lead")]),
        p(
          "This creates a local ledger entry only—no CRM message, contract, invoice or payment.",
        ),
      ]),
      div(class="form-grid", [
        form_field("Customer", form.customer, "Named customer", fn(value) {
          dispatch(SetCommercialField("customer", value))
        }),
        form_field("Contact reference", form.contact_ref, "crm:contact:…", fn(
          value,
        ) {
          dispatch(SetCommercialField("contact", value))
        }),
        text_field(
          "Payable problem",
          form.payable_problem,
          "What costly or slow production problem will Mooncast solve?",
          3,
          fn(value) { dispatch(SetCommercialField("problem", value)) },
        ),
        form_field(
          "Baseline cost CNY",
          form.baseline_cost_cny,
          "Current production cost",
          fn(value) { dispatch(SetCommercialField("baseline_cost", value)) },
        ),
        form_field(
          "Baseline hours",
          form.baseline_hours,
          "Current production time",
          fn(value) { dispatch(SetCommercialField("baseline_hours", value)) },
        ),
        text_field(
          "Measurable acceptance",
          form.measurable_acceptance,
          "One criterion per line",
          4,
          fn(value) { dispatch(SetCommercialField("acceptance", value)) },
        ),
        text_field(
          "Repeat hypothesis",
          form.repeat_hypothesis,
          "Why would the buyer return?",
          3,
          fn(value) { dispatch(SetCommercialField("repeat", value)) },
        ),
      ]),
      div(class="form-actions", [
        button(
          class="primary",
          disabled=model.busy,
          on_click=dispatch(CreateLead),
          "Record lead draft",
        ),
      ]),
    ]),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Human qualification"), h2("Lead ledger")]),
        p(
          "Qualification binds the payable problem, acceptance definition, baseline and repeat hypothesis.",
        ),
      ]),
      match model.commercial {
        None => p(class="empty", "Commercial ledger unavailable.")
        Some(value) =>
          if value.leads.is_empty() {
            p(class="empty", "Record a lead before qualification.")
          } else {
            div(
              class="commercial-list",
              value.leads.map(lead => {
                article(
                  class=if lead.lead_id == model.selected_lead_id {
                    "commercial-card selected"
                  } else {
                    "commercial-card"
                  },
                  [
                    div(class="route-heading", [
                      div([small(lead.lead_id), h3(lead.customer)]),
                      status_chip(lead.status),
                    ]),
                    p(lead.payable_problem),
                    div(class="commercial-baseline", [
                      span([
                        small("Baseline cost"),
                        strong("CNY \{lead.baseline_cost_cny}"),
                      ]),
                      span([
                        small("Baseline time"),
                        strong("\{lead.baseline_time_hours} h"),
                      ]),
                    ]),
                    small("Repeat: " + lead.repeat_hypothesis),
                    div(class="review-actions", [
                      button(
                        class="secondary",
                        on_click=dispatch(SelectLead(lead.lead_id)),
                        "Select",
                      ),
                      button(
                        class="danger",
                        disabled=model.busy || !model.operator.human_confirmed,
                        on_click=dispatch(QualifyLead("disqualify")),
                        "Disqualify",
                      ),
                      button(
                        class="primary",
                        disabled=model.busy || !model.operator.human_confirmed,
                        on_click=dispatch(QualifyLead("qualify")),
                        "Qualify exact lead",
                      ),
                    ]),
                  ],
                )
              }),
            )
          }
      },
    ]),
    render_quote_workspace(dispatch, model),
    render_capacity_workspace(dispatch, model),
    section(class="panel", [
      div(class="panel-heading", [
        div([small("Closed-loop economics"), h2("Commercial progression")]),
      ]),
      div(class="process-strip", [
        span("Lead"),
        span("Human qualification"),
        span("Scoped quote"),
        span("Margin review"),
        span("Capacity"),
        span("Client acceptance"),
        span("Draft project"),
        span("Repeat order"),
      ]),
      p(
        class="boundary-note",
        "Every conversion creates a fresh draft project. Rights, creative, provider, client and publication approvals never carry forward implicitly.",
      ),
    ]),
  ])
}

///|
fn render_quote_workspace(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let form = model.quote_form
  section(class="panel", [
    div(class="panel-heading", [
      div([small("Immutable scope and economics"), h2("Quote workbench")]),
      p(
        "Milestones, revision limits, provider overage, restrictions and founder-hours are explicit before conversion.",
      ),
    ]),
    div(class="form-grid quote-grid", [
      form_field("Project id", form.project_id, "design-partner-episode-001", fn(
        value,
      ) {
        dispatch(SetQuoteField("project_id", value))
      }),
      form_field("Title", form.title, "Episode title", fn(value) {
        dispatch(SetQuoteField("title", value))
      }),
      text_field("Objective", form.objective, "Accepted customer outcome", 3, fn(
        value,
      ) {
        dispatch(SetQuoteField("objective", value))
      }),
      form_field("Audience", form.audience, "Audience", fn(value) {
        dispatch(SetQuoteField("audience", value))
      }),
      form_field("Rights owner", form.rights_owner, "Contract rights owner", fn(
        value,
      ) {
        dispatch(SetQuoteField("rights_owner", value))
      }),
      form_field("Duration seconds", form.duration_seconds, "180–480", fn(
        value,
      ) {
        dispatch(SetQuoteField("duration", value))
      }),
      form_field("Production budget CNY", form.production_budget_cny, "20000", fn(
        value,
      ) {
        dispatch(SetQuoteField("budget", value))
      }),
      form_field("Start date", form.start_date, "YYYY-MM-DD", fn(value) {
        dispatch(SetQuoteField("start", value))
      }),
      form_field("Delivery date", form.delivery_date, "YYYY-MM-DD", fn(value) {
        dispatch(SetQuoteField("delivery", value))
      }),
      text_field("Deliverables", form.deliverables, "One per line", 5, fn(
        value,
      ) {
        dispatch(SetQuoteField("deliverables", value))
      }),
      form_field("Quoted revenue CNY", form.quoted_revenue_cny, "40000", fn(
        value,
      ) {
        dispatch(SetQuoteField("revenue", value))
      }),
      form_field("Provider cost CNY", form.provider_cost_cny, "6000", fn(
        value,
      ) {
        dispatch(SetQuoteField("provider_cost", value))
      }),
      form_field("Labor cost CNY", form.labor_cost_cny, "10000", fn(value) {
        dispatch(SetQuoteField("labor_cost", value))
      }),
      form_field("Other cost CNY", form.other_cost_cny, "2000", fn(value) {
        dispatch(SetQuoteField("other_cost", value))
      }),
      form_field("Founder hours", form.founder_hours, "30", fn(value) {
        dispatch(SetQuoteField("founder_hours", value))
      }),
      form_field("Contingency %", form.contingency_percent, "15", fn(value) {
        dispatch(SetQuoteField("contingency", value))
      }),
      form_field("Deposit CNY", form.deposit_cny, "16000", fn(value) {
        dispatch(SetQuoteField("deposit", value))
      }),
      form_field("Approved animatic CNY", form.animatic_cny, "12000", fn(
        value,
      ) {
        dispatch(SetQuoteField("animatic", value))
      }),
      form_field("Accepted master CNY", form.master_cny, "12000", fn(value) {
        dispatch(SetQuoteField("master", value))
      }),
    ]),
    div(class="form-actions", [
      button(
        class="primary",
        disabled=model.busy || model.selected_lead_id == "",
        on_click=dispatch(CreateOrReviseQuote),
        if model.selected_quote_id == "" {
          "Create scoped quote"
        } else {
          "Record new quote version"
        },
      ),
    ]),
    match model.commercial {
      Some(value) if !value.quotes.is_empty() =>
        div(
          class="quote-list",
          value.quotes.map(quote => {
            article(
              class=if quote.quote_id == model.selected_quote_id {
                "quote-card selected"
              } else {
                "quote-card"
              },
              [
                div(class="route-heading", [
                  div([
                    small("\{quote.quote_id} · v\{quote.version}"),
                    h3(quote.project.title),
                  ]),
                  status_chip(quote.status),
                ]),
                p(quote.project.objective),
                div(class="metrics quote-metrics", [
                  metric(
                    "Revenue",
                    "CNY \{quote.forecast.quoted_revenue_cny}",
                    "Exact quoted revenue",
                  ),
                  metric(
                    "Direct cost",
                    "CNY \{quote.forecast.direct_cost_cny}",
                    "Provider + labor + other",
                  ),
                  metric(
                    "Contribution",
                    "CNY \{quote.forecast.contribution_margin_cny}",
                    "After contingency",
                  ),
                  metric(
                    "Founder hours",
                    "\{quote.forecast.founder_hours}",
                    "Must fall with repeatability",
                  ),
                ]),
                div(class="review-actions", [
                  button(
                    class="secondary",
                    on_click=dispatch(SelectQuote(quote.quote_id)),
                    "Select exact quote",
                  ),
                  button(
                    class="secondary",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(DecideQuote("commercial")),
                    "Commercial approve",
                  ),
                  button(
                    class="secondary",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(DecideQuote("production")),
                    "Production approve",
                  ),
                  button(
                    class="primary",
                    disabled=model.busy || !model.operator.human_confirmed,
                    on_click=dispatch(DecideQuote("client")),
                    "Record client acceptance",
                  ),
                ]),
              ],
            )
          }),
        )
      _ => p(class="empty", "No quote versions recorded.")
    },
  ])
}

///|
fn render_capacity_workspace(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let form = model.capacity_form
  section(class="panel", [
    div(class="panel-heading", [
      div([small("Finite capacity"), h2("Resource and reservation board")]),
      div(class="inline-actions", [
        button(
          class="secondary",
          disabled=model.selected_quote_id == "",
          on_click=dispatch(LoadCapacity),
          "Refresh board",
        ),
        button(
          class="primary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            model.capacity_board.map(value => value.ready) != Some(true),
          on_click=dispatch(ConvertQuote),
          "Convert accepted quote to draft project",
        ),
      ]),
    ]),
    match model.capacity_board {
      Some(board) =>
        div(class="capacity-banner", [
          status_chip(if board.ready { "ready" } else { "conflicts" }),
          div([strong("Quote v\{board.quote_version}"), small(board.digest)]),
          span(
            "\{board.reservations.length()} reservations · \{board.conflicts.length()} conflicts",
          ),
        ])
      None => p(class="empty", "Select a quote to calculate capacity.")
    },
    div(class="capacity-columns", [
      div(class="subpanel", [
        h3("Add studio resource"),
        form_field(
          "Name",
          form.resource_name,
          "Named person or finite machine slot",
          fn(value) { dispatch(SetCapacityField("name", value)) },
        ),
        form_field("Role", form.resource_role, "creative-director", fn(value) {
          dispatch(SetCapacityField("role", value))
        }),
        form_field("Skills", form.resource_skills, "comma-separated", fn(
          value,
        ) {
          dispatch(SetCapacityField("skills", value))
        }),
        form_field("Weekly hours", form.weekly_hours, "20", fn(value) {
          dispatch(SetCapacityField("weekly_hours", value))
        }),
        form_field("Available from", form.available_from, "YYYY-MM-DD", fn(
          value,
        ) {
          dispatch(SetCapacityField("available_from", value))
        }),
        form_field("Available to", form.available_to, "YYYY-MM-DD", fn(value) {
          dispatch(SetCapacityField("available_to", value))
        }),
        button(
          class="secondary",
          disabled=model.busy || !model.operator.human_confirmed,
          on_click=dispatch(CreateResource),
          "Record finite resource",
        ),
      ]),
      div(class="subpanel", [
        h3("Reserve against exact quote"),
        form_field("Resource id", form.resource_id, "resource-…", fn(value) {
          dispatch(SetCapacityField("resource_id", value))
        }),
        form_field(
          "Required skills",
          form.reservation_skills,
          "comma-separated",
          fn(value) { dispatch(SetCapacityField("reservation_skills", value)) },
        ),
        form_field(
          "Depends on reservations",
          form.depends_on,
          "comma-separated ids",
          fn(value) { dispatch(SetCapacityField("depends_on", value)) },
        ),
        form_field("Start", form.reservation_start, "YYYY-MM-DD", fn(value) {
          dispatch(SetCapacityField("reservation_start", value))
        }),
        form_field("End", form.reservation_end, "YYYY-MM-DD", fn(value) {
          dispatch(SetCapacityField("reservation_end", value))
        }),
        form_field("Hours", form.reservation_hours, "20", fn(value) {
          dispatch(SetCapacityField("reservation_hours", value))
        }),
        button(
          class="secondary",
          disabled=model.busy ||
            !model.operator.human_confirmed ||
            model.selected_quote_id == "",
          on_click=dispatch(CreateReservation),
          "Record reservation",
        ),
      ]),
    ]),
    match model.commercial {
      Some(value) if !value.resources.is_empty() =>
        div(
          class="resource-list",
          value.resources.map(resource => {
            article(class="resource-card", [
              div([strong(resource.name), status_chip(resource.role)]),
              code(resource.resource_id),
              small(
                "\{resource.weekly_hours} h/week · " +
                resource.skills.join(", "),
              ),
            ])
          }),
        )
      _ => @html.nothing
    },
  ])
}

///|
fn render_status(model : Model) -> @rabbita.Html {
  div(class="global-status", [
    span(
      class=if model.busy || model.loading { "pulse" } else { "dot" },
      @html.nothing,
    ),
    p(model.status),
    match model.error {
      Some(value) => p(class="global-error", value)
      None => @html.nothing
    },
  ])
}

///|
fn render_surface(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  match model.tab {
    Overview => render_overview(dispatch, model, model.project)
    NeedsStrategy => render_needs_strategy(dispatch, model)
    Creative => render_creative(dispatch, model, model.project)
    AssetFactory => render_asset_factory(dispatch, model)
    StoryboardAnimatic => render_storyboard_animatic(dispatch, model)
    Routing => render_routing(dispatch, model, model.project)
    ShotBoard => render_shot_board(dispatch, model, model.project)
    Delivery => render_delivery(dispatch, model, model.project)
    Commercial => render_commercial(dispatch, model)
  }
}

///|
/// Rabbita normally refreshes event slots while diffing positional children.
/// Studio surfaces are intentionally keyed as whole workspaces as well: every
/// tab has a different command vocabulary, so reusing a same-shaped button or
/// input from another tab must never retain that tab's event identity.
fn render_keyed_surface(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let project_identity = match model.project {
    Some(project) => project.id + "-revision-" + project.revision.to_string()
    None => "no-project"
  }
  div(
    class="studio-surface",
    Map::from_array([
      (
        "studio-surface-" + tab_label(model.tab) + "-" + project_identity,
        render_surface(dispatch, model),
      ),
    ]),
  )
}

///|
fn render_app(dispatch : Dispatch[Msg], model : Model) -> @rabbita.Html {
  div(class="mooncast-studio", [
    render_header(dispatch, model),
    div(class="studio-shell", [
      render_project_rail(dispatch, model),
      main_(class="studio-main", [
        render_operator_bar(dispatch, model),
        render_status(model),
        render_keyed_surface(dispatch, model),
      ]),
    ]),
  ])
}
