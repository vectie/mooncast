///|
fn animatic_artifact(
  id : String,
  kind : @creative.ArtifactKind,
) -> @creative.CreativeArtifact {
  {
    reference: {
      id,
      version: 1,
      digest: "sha256:" + id.pad_end(64, '0')[:64].to_owned(),
    },
    kind,
    dependency_digests: [],
    duration_seconds: Some(3),
    expected_cost_cny: Some(10.0),
    rights_cleared: true,
    content: "{\"approved\":true}",
  }
}

///|
async test "rendered animatic produces immutable sheet video cost and approval evidence" {
  let root = "/tmp/mooncast-rendered-animatic-" + @async.now().to_string()
  let service = AnimaticService::new(root + "/state", root + "/media")
  let bible = animatic_artifact("bible", @creative.IpBible)
  let script = animatic_artifact("script", @creative.Script)
  let storyboard = animatic_artifact("storyboard", @creative.Storyboard)
  let artifacts = [bible, script, storyboard]
  let asset = fn(id : String, kind : String) -> @project.Asset {
    {
      asset_id: id,
      kind,
      version: 1,
      digest: "sha256:" + (id + kind).pad_end(64, '1')[:64].to_owned(),
      uri: "provider-artifact:" + id,
      rights_record_id: "rights:" + id,
      immutable: true,
    }
  }
  let hero = asset("hero", "character")
  let voice = asset("voice", "voice")
  let music = asset("music", "music")
  let graph : @project.ProjectGraph = {
    project_id: "animatic-project",
    revision: 4,
    title: "Animatic fixture",
    target_duration_seconds: 3,
    maximum_budget_cny: 100.0,
    episodes: [
      {
        episode_id: "episode",
        order: 1,
        title: "Episode",
        scenes: [
          {
            scene_id: "scene",
            order: 1,
            title: "Scene",
            shots: [
              {
                shot_id: "shot",
                order: 1,
                duration_ms: 3000,
                character_ids: ["hero"],
                location_id: "world",
                source_asset_ids: [],
              },
            ],
          },
        ],
      },
    ],
    assets: [],
  }
  let base : @animatic_domain.AnimaticPlan = {
    contract: "mooncast.animatic-plan.v1",
    reference: { id: "animatic-plan", version: 1, digest: "" },
    project_id: graph.project_id,
    project_revision: 4,
    bible: bible.reference,
    script: script.reference,
    storyboard: storyboard.reference,
    panels: [
      {
        panel_id: "panel",
        scene_id: "scene",
        shot_id: "shot",
        order: 1,
        duration_ms: 3000,
        caption: "A governed opening panel",
        visual_asset_ids: [hero.asset_id],
        transition: "cut",
      },
    ],
    approved_assets: [hero, voice, music],
    temporary_voice_asset_ids: [voice.asset_id],
    temporary_music_asset_ids: [music.asset_id],
    caption_language: "zh-CN",
    provider: "mooncast-native-storyboard",
    model: "deterministic-animatic-v1",
    cost_ceiling_cny: 10.0,
    retry_limit: 2,
    created_at: "2026-07-19T12:00:00+08:00",
    process_authority: false,
    publication_authority: false,
  }
  let plan = {
    ..base,
    reference: { ..base.reference, digest: @animatic_domain.plan_digest(base) },
  }
  ignore(service.record_plan(plan, graph, artifacts))
  let rendered = service.render(graph.project_id, {
    expected_plan_version: 1,
    expected_plan_digest: plan.reference.digest,
    actor: "creative-director",
    rendered_at: "2026-07-19T12:01:00+08:00",
    human_confirmed: true,
    process_authority: true,
  })
  assert_true(rendered.process_effect_performed)
  assert_false(rendered.network_effect_performed)
  assert_false(rendered.publication_authority)
  assert_true(rendered.immutable)
  assert_eq(rendered.duration_seconds, 3)
  assert_true(rendered.video_digest.has_prefix("sha256:"))
  assert_true(rendered.storyboard_sheet_digest.has_prefix("sha256:"))
  assert_true(rendered.budget.within_ceiling)
  assert_true(service.media(graph.project_id, 1, "sheet").bytes.length() > 0)
  assert_true(service.media(graph.project_id, 1, "video").bytes.length() > 0)
  let approval = service.approve(graph.project_id, {
    expected_render_version: 1,
    expected_render_digest: rendered.reference.digest,
    actor: "creative-director",
    actor_role: "creative-director",
    note: "Timing, temp audio, captions, transitions, rights and cost reviewed",
    approved_at: "2026-07-19T12:02:00+08:00",
    human_confirmed: true,
  })
  let canonical_animatic : @creative.CreativeArtifact = {
    reference: {
      id: "animatic",
      version: 2,
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
    kind: @creative.Animatic,
    dependency_digests: [
      bible.reference.digest,
      script.reference.digest,
      storyboard.reference.digest,
    ],
    duration_seconds: Some(3),
    expected_cost_cny: Some(rendered.budget.actual_cny),
    rights_cleared: true,
    content: approval.to_json().stringify(),
  }
  let decision : @creative.CreativeDecision = {
    artifact: canonical_animatic.reference,
    decision: "approved",
    actor: "creative-director",
    role: "creative-director",
    decided_at: "2026-07-19T12:02:00+08:00",
    note: "exact render approved",
  }
  assert_true(
    @animatic_domain.exact_approved_render(
      Some(canonical_animatic),
      [decision],
      [bible, script, storyboard, canonical_animatic],
      graph,
    )
    is Some(_),
  )
}
