///|
struct StudioJourney {
  gate : String
  position : Int
  title : String
  detail : String
  action : String
  tab : StudioTab
} derive(Eq)

///|
fn studio_journey_for(
  gate : String?,
  ready : Bool,
  has_project : Bool,
) -> StudioJourney {
  if !has_project {
    return {
      gate: "G0",
      position: 0,
      title: "Define the episode customers will accept",
      detail: "Set the payable outcome, audience, rights owner, duration, and budget.",
      action: "Start episode",
      tab: Overview,
    }
  }
  match gate {
    None =>
      {
        gate: "Done",
        position: 8,
        title: "Episode workflow complete",
        detail: "Inspect delivery evidence, customer acceptance, and measured economics.",
        action: "Review delivery",
        tab: Delivery,
      }
    Some("G0") =>
      {
        gate: "G0",
        position: 0,
        title: "Confirm the paid production boundary",
        detail: if ready {
          "All G0 evidence is ready for the named human receipt."
        } else {
          "Complete qualification, scope, rights owner, duration, and budget."
        },
        action: if ready {
          "Record G0"
        } else {
          "Finish qualification"
        },
        tab: Overview,
      }
    Some("G1") =>
      {
        gate: "G1",
        position: 1,
        title: "Clear brief and rights",
        detail: if ready {
          "The exact brief and rights ledger are ready for the named receipt."
        } else {
          "Review the brief and resolve every rights or data-use blocker."
        },
        action: if ready {
          "Record G1"
        } else {
          "Open creative review"
        },
        tab: Creative,
      }
    Some("G2") =>
      {
        gate: "G2",
        position: 2,
        title: "Lock the story system",
        detail: if ready {
          "Bible, script, and claims are ready for the named receipt."
        } else {
          "Approve the IP bible, script, and bounded claims ledger."
        },
        action: if ready {
          "Record G2"
        } else {
          "Review story"
        },
        tab: Creative,
      }
    Some("G3") =>
      {
        gate: "G3",
        position: 3,
        title: "Approve the animatic and spend plan",
        detail: if ready {
          "Storyboard, rendered animatic, route, and budget are aligned."
        } else {
          "Resolve timing, route coverage, and producer/finance approval."
        },
        action: if ready {
          "Record G3"
        } else {
          "Open animatic"
        },
        tab: StoryboardAnimatic,
      }
    Some("G4") =>
      {
        gate: "G4",
        position: 4,
        title: "Resolve every shot finding",
        detail: "Inspect technical, continuity, safety, rights, and claim QC before the master cut.",
        action: "Open shot QC",
        tab: ShotBoard,
      }
    Some("G5") =>
      {
        gate: "G5",
        position: 5,
        title: "Accept the exact master",
        detail: "Bind creative-director, compliance, and client acceptance to one immutable master.",
        action: "Review master",
        tab: Delivery,
      }
    Some("G6") =>
      {
        gate: "G6",
        position: 6,
        title: "Authorize a destination",
        detail: "Prepare the delivery package; publication remains a separate destination-specific effect.",
        action: "Open delivery",
        tab: Delivery,
      }
    Some("G7") =>
      {
        gate: "G7",
        position: 7,
        title: "Close the operating loop",
        detail: "Record reach, retention, cost, margin, founder-hours, and repeat-order evidence.",
        action: "Review outcomes",
        tab: Commercial,
      }
    Some(other) =>
      {
        gate: other,
        position: 0,
        title: "Inspect the next production gate",
        detail: "The project returned an unfamiliar gate. Refresh the exact revision before continuing.",
        action: "Inspect project",
        tab: Overview,
      }
  }
}

///|
fn next_gate_ready(project : ProjectProjection) -> Bool {
  match next_gate(project) {
    Some(gate) =>
      project.gates.get(gate).map(value => value.ready).unwrap_or(false)
    None => false
  }
}

///|
fn journey_action(
  dispatch : Dispatch[Msg],
  model : Model,
  journey : StudioJourney,
  ready : Bool,
) -> @rabbita.Cmd {
  if ready &&
    gate_controlled_here(journey.gate) &&
    model.operator.human_confirmed {
    dispatch(AdvanceGate(journey.gate))
  } else {
    dispatch(SelectTab(journey.tab))
  }
}

///|
fn render_journey_compass(
  dispatch : Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let project = model.project
  let ready = project.map(next_gate_ready).unwrap_or(false)
  let journey = studio_journey_for(
    project.bind(next_gate),
    ready,
    project is Some(_),
  )
  let passed = project
    .map(value => {
      gate_sequence().filter(gate => gate_passed(value, gate)).length()
    })
    .unwrap_or(0)
  let recovery_action = if model.selected_project_id == "" {
    "Retry workspace"
  } else {
    "Retry revision"
  }
  section(
    class="journey-compass",
    attrs=@html.Attrs::build()
      .data_set("testid", "production-compass")
      .aria_label("Production progress and next action"),
    [
      div(class="journey-copy", [
        small("NEXT · " + journey.gate),
        strong(journey.title),
        p(
          match model.error {
            Some(error) => "Recovery: " + error
            None => journey.detail
          },
        ),
      ]),
      div(
        class="journey-steps",
        attrs=@html.Attrs::build()
          .role("progressbar")
          .aria_valuemin("0")
          .aria_valuemax("8")
          .aria_valuenow(passed.to_string())
          .aria_valuetext("\{passed} of 8 production gates passed"),
        gate_sequence().mapi((index, gate) => {
          let state = if index < passed {
            "done"
          } else if index == journey.position {
            "current"
          } else {
            "pending"
          }
          span(
            class="journey-step " + state,
            title="\{gate} · \{state}",
            attrs=@html.Attrs::build().aria_label("\{gate} \{state}"),
            if state == "done" {
              [studio_action_icon("check"), span(gate)]
            } else {
              [span(gate)]
            },
          )
        }),
      ),
      button(
        class="primary journey-action",
        disabled=model.busy || model.loading,
        on_click=if model.error is Some(_) {
          if model.selected_project_id == "" {
            dispatch(Bootstrap)
          } else {
            dispatch(RefreshProject)
          }
        } else {
          journey_action(dispatch, model, journey, ready)
        },
        attrs=@html.Attrs::build()
          .data_set("testid", "production-next-action")
          .aria_label(
            if model.error is Some(_) {
              recovery_action
            } else {
              journey.action
            },
          ),
        if model.error is Some(_) {
          recovery_action
        } else {
          journey.action
        },
      ),
    ],
  )
}
