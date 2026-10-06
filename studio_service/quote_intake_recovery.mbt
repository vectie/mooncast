///|
/// Frozen before the first conversion write. Canonical records are reconciled
/// before each checkpoint, so a lost acknowledgement never repeats a seed.
struct QuoteIntakePlan {
  contract : String
  conversion : @commerce.QuoteConversion
  graph : @project.ProjectGraph
  metadata : ProjectExperienceMetadata
  qualification : @governance.ClientQualification
  drafts : Array[@creative.CreativeArtifact]
  adopt_existing : Bool
  completed_steps : Array[String]
  complete : Bool
} derive(ToJson, FromJson)

///|
let quote_intake_locks : Map[String, @semaphore.Semaphore] = Map([])

///|
fn quote_intake_key(project_id : String) -> String {
  "quote-intake-" + sha256_text(project_id) + ".json"
}

///|
async fn[T] StudioService::with_quote_intake_lock(
  self : StudioService,
  work : async () -> T,
) -> T {
  // One lock per store in this process, plus a crash-released OS file lock for
  // another process. Do not nest the project mutation semaphore here.
  let path = self.store.prepare_owned_path("quote-intake.lock")
  let root = @fs.realpath(self.root)
  let lock = match quote_intake_locks.get(root) {
    Some(value) => value
    None => {
      let value = @semaphore.Semaphore(1)
      quote_intake_locks[root] = value
      value
    }
  }
  lock.acquire()
  defer lock.release()
  let file = @fs.open(path, mode=ReadWrite, create_mode=OpenOrCreate)
  defer file.close()
  @fsx.lock_file(file) catch {
    _ =>
      raise Conflict(
        code="intake_in_progress",
        message="Another intake attempt is active. Retry Resume draft initialization when it finishes.",
      )
  }
  work()
}

///|
async fn StudioService::conversion_with_initialization(
  self : StudioService,
  conversion : @commerce.QuoteConversion,
) -> ConversionProjection {
  let plan : QuoteIntakePlan? = load_value(
    self.store,
    quote_intake_key(conversion.project_id),
  )
  {
    ..conversion_projection(conversion),
    initialization_status: Some(
      match plan {
        Some(value) =>
          if !value.complete {
            "pending"
          } else if value.adopt_existing {
            "preserved-existing"
          } else {
            "completed"
          }
        None => "legacy"
      },
    ),
  }
}

///|
async fn StudioService::checkpoint_quote_intake(
  self : StudioService,
  plan : QuoteIntakePlan,
  step : String,
  checkpoint : async (String) -> Unit,
) -> QuoteIntakePlan {
  // Injection brackets the persisted acknowledgement as well as the effect.
  checkpoint(step + ":effect")
  let steps = plan.completed_steps.copy()
  if !steps.contains(step) {
    steps.push(step)
  }
  let updated = { ..plan, completed_steps: steps, }
  save_value(self.store, quote_intake_key(plan.conversion.project_id), updated)
  checkpoint(step + ":checkpoint")
  updated
}

///|
async fn StudioService::resume_quote_intake(
  self : StudioService,
  initial : QuoteIntakePlan,
  checkpoint : async (String) -> Unit,
) -> ProjectRecord {
  let project_id = initial.conversion.project_id
  guard initial.contract == "mooncast.quote-intake-plan.v1" &&
    initial.graph.project_id == project_id else {
    raise Conflict(
      code="intake_plan_conflict",
      message="Stored intake plan does not match this project",
    )
  }
  if initial.complete {
    return self.get_project(project_id)
  }
  let mut plan = initial
  let current = self.load_project_record(project_id)
  match current {
    Some(record) if record.deleted =>
      raise Conflict(
        code="project_tombstoned",
        message="An interrupted intake cannot restore a deleted project",
      )
    None => {
      guard !plan.completed_steps.contains("project") else {
        raise Conflict(
          code="intake_project_missing",
          message="Previously initialized project is missing; retry cannot recreate deleted work",
        )
      }
      ignore(
        self.create_project_with_initialization(
          plan.graph,
          plan.conversion.converted_at,
          Some(plan.conversion.digest),
        ),
      )
    }
    Some(record) => {
      guard plan.adopt_existing ||
        record.initialization_digest == Some(plan.conversion.digest) else {
        raise Conflict(
          code="intake_project_conflict",
          message="Project was created by different work after this intake started; existing work was preserved",
        )
      }
    }
  }
  plan = self.checkpoint_quote_intake(plan, "project", checkpoint)
  if !plan.adopt_existing {
    self.with_mutation_lock(() => {
      let metadata : ProjectExperienceMetadata? = load_value(
        self.store,
        project_experience_key(project_id),
      )
      if metadata is None {
        guard !plan.completed_steps.contains("metadata") else {
          raise Conflict(
            code="intake_metadata_missing",
            message="Previously initialized project details are missing; retry cannot replace later work",
          )
        }
        save_value(
          self.store,
          project_experience_key(project_id),
          plan.metadata,
        )
      }
    })
    plan = self.checkpoint_quote_intake(plan, "metadata", checkpoint)
    let project = self.get_project(project_id)
    if project.snapshot.qualification is None {
      guard !plan.completed_steps.contains("qualification") else {
        raise Conflict(
          code="intake_qualification_missing",
          message="Previously initialized qualification is missing",
        )
      }
      let response = self.record_planned_qualification(
        project_id,
        plan.qualification,
        plan.conversion.converted_at,
      )
      guard response.result.ok else {
        raise Conflict(
          code="intake_qualification_conflict",
          message="Initial qualification was rejected; current work was preserved",
        )
      }
    }
    plan = self.checkpoint_quote_intake(plan, "qualification", checkpoint)
    for artifact in plan.drafts {
      let step = artifact.kind.to_string()
      let project = self.get_project(project_id)
      let history = project.snapshot.creative_artifacts
      let exact = history.filter(item => item.reference == artifact.reference)
      if exact.is_empty() {
        guard !plan.completed_steps.contains(step) &&
          !history.any(item => item.kind == artifact.kind) else {
          raise Conflict(
            code="intake_seed_conflict",
            message="Initial " +
              step +
              " has changed or is missing. Existing creative history was preserved; retry cannot overwrite it.",
          )
        }
        self.record_planned_initial_draft(
          project_id,
          artifact,
          plan.conversion.converted_at,
        )
      } else {
        guard exact.length() == 1 && exact[0] == artifact else {
          raise Conflict(
            code="intake_seed_conflict",
            message="Initial " +
              step +
              " identity is bound to different content; existing work was preserved",
          )
        }
      }
      plan = self.checkpoint_quote_intake(plan, step, checkpoint)
    }
  }
  // Repairs a crash after canonical persistence but before the projection was
  // synchronized, without replaying commands or touching delivery/approval.
  let current = self.with_mutation_lock(() => {
    let current = self.get_project(project_id)
    ignore(
      self.production_repository.synchronize_canonical(
        current.snapshot,
        "sha256:" + sha256_text(current.snapshot.to_json().stringify()),
        current.updated_at,
      ),
    )
    current
  })
  plan = self.checkpoint_quote_intake(plan, "projection", checkpoint)
  save_value(self.store, quote_intake_key(project_id), {
    ..plan,
    complete: true,
  })
  checkpoint("complete")
  current
}

///|
async fn StudioService::convert_quote_intake(
  self : StudioService,
  quote_id : String,
  input : QuoteConversionInput,
  checkpoint : async (String) -> Unit,
) -> ConversionResultProjection {
  self.with_quote_intake_lock(() => {
    guard input.human_confirmed else {
      fail("named human confirmation is required")
    }
    let snapshot = self.commerce_application.load()
    let quotes = snapshot.quotes.filter(item => {
      item.quote.id == quote_id &&
      item.quote.version == input.expected_version &&
      normalized_digest(item.quote.digest) ==
      normalized_digest(input.expected_digest)
    })
    guard quotes.length() == 1 else { fail("accepted quote binding changed") }
    let quote = quotes[0]
    let prior = snapshot.conversions.filter(item => {
      item.project_id == quote.project.project_id || item.quote == quote.quote
    })
    guard prior.length() <= 1 &&
      prior.all(item => {
        item.quote == quote.quote &&
        item.project_id == quote.project.project_id &&
        normalized_digest(item.capacity_digest) ==
        normalized_digest(input.expected_capacity_digest)
      }) else {
      raise Conflict(
        code="quote_conversion_conflict",
        message="project or quote is already bound to different conversion evidence",
      )
    }
    let stored : QuoteIntakePlan? = load_value(
      self.store,
      quote_intake_key(quote.project.project_id),
    )
    let plan = match stored {
      Some(value) => {
        guard value.conversion.quote == quote.quote &&
          value.conversion.project_id == quote.project.project_id &&
          normalized_digest(value.conversion.capacity_digest) ==
          normalized_digest(input.expected_capacity_digest) &&
          prior.all(item => item == value.conversion) else {
          raise Conflict(
            code="intake_plan_conflict",
            message="Retry must use the original quote, project and capacity binding",
          )
        }
        value
      }
      None => {
        if prior.get(0) is Some(conversion) &&
          self.find_project(conversion.project_id) is Some(project) {
          return {
            conversion: self.conversion_with_initialization(conversion),
            project: self.studio_project_projection(project),
            external_effect_performed: false,
            payment_effect_performed: false,
            publication_authority: false,
          }
        }
        let conversion = match prior.get(0) {
          Some(value) => value
          None => {
            guard latest_quote(snapshot, quote_id) == Some(quote) &&
              self.commerce_application.capacity_board(quote_id~) is Some(board) &&
              board.ready &&
              normalized_digest(board.digest) ==
              normalized_digest(input.expected_capacity_digest) else {
              fail("accepted capacity binding changed")
            }
            let digest = "sha256:" +
              sha256_text(
                quote.quote.digest +
                ":" +
                board.digest +
                ":" +
                quote.project.project_id +
                ":" +
                input.actor,
              )
            {
              contract: "mooncast.quote-conversion.v1",
              quote: quote.quote,
              capacity_digest: board.digest,
              project_id: quote.project.project_id,
              actor: input.actor,
              actor_role: input.actor_role,
              converted_at: now_string(),
              digest,
              payment_effect_performed: false,
              publication_authority: false,
            }
          }
        }
        let graph = @production_app.episode_production_graph(
          quote.project.project_id,
          quote.project.title,
          quote.project.target_duration_seconds,
          quote.project.production_budget_cny,
        )
        let existing = self.load_project_record(quote.project.project_id)
        guard (match existing {
          None => true
          Some(item) => !item.deleted && item.snapshot.graph == graph
        }) else {
          raise Conflict(
            code="project_exists",
            message="Project id is already bound to different work",
          )
        }
        let metadata : ProjectExperienceMetadata = {
          objective: quote.project.objective,
          audience: quote.project.audience,
          channels: ["review-only"],
          rights_owner: quote.project.rights_owner,
          rights_confirmed: true,
        }
        let value : QuoteIntakePlan = {
          contract: "mooncast.quote-intake-plan.v1",
          conversion,
          graph,
          metadata,
          qualification: initial_project_qualification(
            graph.project_id,
            metadata,
          ),
          drafts: initial_creative_drafts(graph, metadata),
          adopt_existing: existing is Some(_),
          completed_steps: [],
          complete: false,
        }
        save_value(self.store, quote_intake_key(graph.project_id), value)
        checkpoint("plan")
        value
      }
    }
    if plan.complete {
      guard prior.length() == 1 else {
        raise Conflict(
          code="intake_conversion_missing",
          message="Completed intake conversion is missing; retry cannot recreate historical evidence",
        )
      }
      return {
        conversion: self.conversion_with_initialization(plan.conversion),
        project: self.studio_project_projection(
          self.get_project(plan.conversion.project_id),
        ),
        external_effect_performed: false,
        payment_effect_performed: false,
        publication_authority: false,
      }
    }
    if prior.is_empty() {
      guard !plan.completed_steps.contains("conversion") else {
        raise Conflict(
          code="intake_conversion_missing",
          message="Previously committed conversion is missing; retry cannot recreate historical evidence",
        )
      }
      // Ordinary project creation shares the intake lock, so unrelated work
      // cannot occupy this id between the check and the conversion commit.
      match self.load_project_record(plan.conversion.project_id) {
        Some(record) => {
          guard !record.deleted &&
            (
              plan.adopt_existing ||
              record.initialization_digest == Some(plan.conversion.digest)
            ) else {
            raise Conflict(
              code="intake_project_conflict",
              message="Project was created by different work after this intake started; no conversion was committed",
            )
          }
        }
        None => ()
      }
      ignore(
        self.commerce_application.submit(
          commercial_command(
            snapshot,
            "convert_quote",
            plan.conversion.digest,
            conversion=plan.conversion,
          ),
        ),
      )
    }
    let plan = self.checkpoint_quote_intake(plan, "conversion", checkpoint)
    let project = self.resume_quote_intake(plan, checkpoint)
    {
      conversion: self.conversion_with_initialization(plan.conversion),
      project: self.studio_project_projection(project),
      external_effect_performed: false,
      payment_effect_performed: false,
      publication_authority: false,
    }
  })
}
