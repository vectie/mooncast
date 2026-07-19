# Native source cutover ledger

Status: source cutover complete. The retired runtime, its tests, the boundary
script, and the vanilla static controllers have been removed. Release, CI,
install, runtime, and UI behavior are owned by MoonBit and Rabbita. The rows
below remain a historical coverage inventory for the final all-at-once release
validation; they are not executable dependencies.

Legend: **covered** means an equivalent MoonBit test already exists;
**specified** means the behavior is now explicitly retained here but its
package owner must finish or confirm the native test before promotion;
**native-boundary** means this migration added the replacement test source in
`release/boundary`.

## `tests/test_bookkeeper.py`

These tests describe the retired MC-7 pack-local authority and are retained as
migration evidence, not as requirements to recreate Bookkeeper in Mooncast.
Canonical finalization, Three-Gap, learning, capability, and ability tests belong
to MoonBook. Mooncast replacement coverage is limited to exact production
evidence, an opaque MoonFlow handoff destined for MoonBook, immutable external
receipt references, and read-only preservation of accepted MC-7 bytes/digests.
The old same-origin mutation routes must remain absent. See ADR MC-8 and
`migrations/mc7-bookkeeper-read-only.md`.

## `tests/test_editor_http.py`

- `test_open_fixture_contains_complete_read_model` — editor open returns the complete canonical read model; specified for editor HTTP tests.
- `test_take_variant_enrichment_template_add_and_reopen` — enriched take variants add through server templates and survive reopen; specified.
- `test_sequential_commands_replay_conflicts_and_restart` — sequential command revisions, replay, conflicts, and restart are deterministic; specified.
- `test_validation_paths_preview_and_jobs`, `test_preview_invalid_attempts_and_ceiling_http_codes`, `test_preview_duplicate_retry_while_queued_is_denied` — preview/job validation, typed HTTP failures, attempt ceilings, and queued duplicate denial are preserved; specified.
- `test_preview_head_and_get_deny_media_after_revalidation_failure` — HEAD and GET both deny invalidated media; specified.
- `test_require_relative_path_rejects_unsafe_locators` — media locators remain safe pack-relative paths; specified.

## `tests/test_editor_kernel.py`

- `test_all_schemas_and_fixture_parse_and_have_versioned_contracts`, `test_fixture_identity_and_reference_integrity`, `test_schema_subset_validates_fixture_commands_and_lifecycle_documents` — versioned editor contracts, identity graph, references, commands, and lifecycle documents validate; specified.
- `test_preview_and_export_never_grant_publication_authority` — editor preview/export never grants publication authority; specified.
- `test_add_and_original_input_not_mutated`, `test_move`, `test_trim`, `test_split`, `test_delete_and_unknown_delete_failure` — canonical add/move/trim/split/delete semantics and input immutability are preserved; specified.
- `test_overlap_and_invalid_trim_fail_closed`, `test_stale_revision`, `test_invalid_references_and_command_envelopes_fail_closed`, `test_invalid_ids_and_ticks` — invalid ranges, stale revisions, bad references/envelopes, identifiers, and ticks fail closed; specified.
- `test_idempotency_and_conflicting_command_id_reuse` — command replay is idempotent and conflicting reuse is denied; specified.
- `test_linear_undo_redo_lifo_branching_atomicity_and_validation`, `test_undo_redo_are_auditable_and_replay_deterministically` — undo/redo is linear, atomic, auditable, branch-safe, and replayable; specified.
- `test_malformed_declared_identity_and_intent_fail_initialization` — malformed identity/intent cannot initialize a workspace; specified.
- `test_new_files_have_no_forbidden_boundaries_or_terms` — domain isolation is native-boundary.

## `tests/test_editor_preview_export.py`

- `test_ingest_idempotency_metadata_and_conflict`, `test_missing_and_corrupt_findings_do_not_drop_record` — ingest metadata is idempotent, conflicts are typed, and findings never erase records; specified.
- `test_proxy_original_selection_and_deterministic_replay`, `test_missing_media_is_explicit_and_not_ready` — original/proxy selection replays deterministically and missing media remains explicit; specified.
- `test_stale_project_or_timeline_revision`, `test_timebase_and_range_errors`, `test_invalid_media_metadata_and_proxy_missing_original` — stale revisions, invalid timebases/ranges/metadata, and invalid proxy ancestry fail closed; specified.
- `test_successful_preview_session`, `test_preview_ephemeral_and_error_validation` — successful and failed preview sessions retain bounded ephemeral semantics; specified.
- `test_export_success_and_provenance_retention`, `test_unsupported_codec_and_budget_rejected_before_provider`, `test_transitions_and_idempotent_cancellation`, `test_failure_retry_restart_attempt_ceiling_and_terminal_rejection`, `test_provider_mismatch_rejected` — export preserves provenance while codec, budget, transition, cancellation, retry, restart, ceiling, terminal, and provider constraints hold; specified.
- `test_schemas_fixture_and_strict_boundaries` — schema fixtures and strict ownership are native-boundary plus editor contract tests.

## `tests/test_editor_preview_worker.py`

- `test_idempotency_failure_retry_and_no_authority`, `test_restart_running_no_new_attempt_and_tamper_fails_closed`, `test_unsafe_ids_invalid_range_and_unknown_media` — worker replay/retry/restart has no external authority and rejects tamper, unsafe IDs, ranges, and media; specified.
- `test_invalid_attempt_limits_and_default_are_exposed`, `test_ceiling_one_failure_is_denied`, `test_ceiling_two_retry_success_and_double_failure`, `test_restart_running_and_resume_at_ceiling_do_not_increment`, `test_restart_before_and_after_provider_reservation_does_not_double_count` — attempt defaults and ceilings remain exact across failure, restart, resume, and provider reservation; specified.
- `test_concurrent_duplicate_retry_has_one_winner`, `test_duplicate_submit_is_stable_and_changed_max_conflicts`, `test_max_attempt_tampering_is_inert_before_provider`, `test_succeeded_and_cancelled_are_not_retryable` — concurrency has one winner, duplicate submission is stable, changed ceilings conflict, tampering is inert, and terminal jobs cannot retry; specified.
- `test_parseable_tampering_is_replaced_inertly`, `test_duplicate_corrupt_and_non_utf8_records_are_quarantined_unchanged`, `test_tampered_queued_live_scan_never_renders`, `test_tampered_running_restart_never_renders` — parseable/corrupt/non-UTF8/queued/running tamper is quarantined without rendering; specified.
- `test_symlink_boundaries_do_not_follow_or_modify_targets`, `test_preview_media_symlink_is_denied_without_target_change` — worker and media symlinks cannot escape or modify targets; specified, with repository-level symlink behavior native-boundary.
- `test_legitimate_failed_and_succeeded_transitions_remain_valid`, `test_running_state_persist_authority_failure_is_inert`, `test_immediate_pre_provider_authority_mismatch_is_inert`, `test_fully_redigested_job_still_mismatches_unchanged_anchor_once` — valid transitions remain valid and all authority-anchor mismatches are inert; specified.
- `test_missing_changed_corrupt_and_exception_authority_fail_closed`, `test_restart_unchanged_anchor_and_changed_anchor`, `test_live_scan_missing_or_mismatched_anchor_never_renders`, `test_retry_after_anchor_removed_or_changed_is_inert`, `test_authority_file_and_directory_symlink_preserve_external_bytes`, `test_exact_duplicate_valid_conflicting_duplicate_keeps_anchor` — authority files/anchors survive missing, change, corruption, exceptions, retry, restart, symlinks, and duplicates without unauthorized render; specified.
- `test_valid_probe_metadata_is_exact_persisted_and_returned`, `test_probe_process_failures_are_typed_bounded_and_do_not_kill_worker`, `test_probe_json_shape_and_media_contract_adversaries` — probe metadata is exact while process and adversarial media failures remain typed and bounded; specified.
- `test_validation_failure_consumes_attempt_and_normal_retry_ceiling_applies`, `test_restart_rejects_missing_incomplete_or_tampered_validation_metadata`, `test_get_and_media_revalidation_deny_content_metadata_and_symlink_replacement`, `test_descriptor_identity_races_before_during_and_after_probe_fail_closed` — validation consumes attempts, restart requires sealed validation metadata, reads revalidate content, and descriptor races fail closed; specified.
- `test_real_resolved_ffmpeg_and_ffprobe_integration` — an explicit host-provided ffmpeg/ffprobe integration produces validated media; specified as an opt-in native integration gate.

## `tests/test_editor_production_adapter.py`

- `test_success_registry_roles_and_command_only_placement`, `test_variant_choice_and_deterministic_replay`, `test_idempotent_existing_snapshot` — production imports preserve registry roles, place only through commands, choose variants deterministically, and reuse exact snapshots; specified.
- `test_fail_closed`, `test_existing_snapshot_contract_drift_rejected`, `test_typed_intent_fail_closed`, `test_selected_unplaced_take_requires_passed_qc` — malformed input, contract drift, typed-intent failures, and failed QC deny import; specified.
- `test_draft_2020_12_fixture_and_snapshot_round_trip`, `test_schema_json_and_boundary` — Draft 2020-12 schemas and snapshot round trips remain valid; specified plus native-boundary.

## `tests/test_editor_store.py`

- `test_create_save_load_and_replay_after_restart`, `test_restart_preserves_edit_undo_redo_history_and_canonical_snapshot`, `test_restart_and_historical_replay` — create/save/load, history, canonical snapshots, and historical replay survive restart; specified.
- `test_conflict_and_nonprefix_fail_atomically`, `test_identical_retry_is_idempotent`, `test_traversal_digest_replay_and_revision_failures` — conflicts/non-prefix journals are atomic, identical retry is stable, and traversal/digest/revision errors fail closed; specified.
- `test_tampered_current_uses_validated_base_backup`, `test_interruption_after_journal_fsync_recovers`, `test_temp_and_partial_journal_recovery`, `test_corrupt_final_falls_back_to_validated_backup` — backups and journal recovery are validated and deterministic; specified.
- `test_v0_migration_exact_receipt_and_unknown` — v0 migration emits an exact receipt and rejects unknown formats; specified.
- `test_missing_and_mismatched_media_are_findings_only` — media mismatch is visible without silently mutating the project; specified.
- `test_contracts_parse_validate_and_boundary`, `test_lifecycle_and_schema`, `test_contract_boundary` — store/lifecycle contracts and schemas validate within pack boundaries; specified plus native-boundary.
- `test_inputs_missing_and_no_lookup_side_effect`, `test_corrupt_records_fail_without_repair`, `test_canonical_binding_tamper`, `test_symlinks` — missing input has no lookup mutation and corrupt/binding/symlink attacks remain untouched and denied; specified.

## `tests/test_editor_ui.py`

- `test_editor_controller_is_separate_and_production_bundle_is_preserved`, `test_safe_dom_construction_and_same_origin_editor_boundary` — editor remains isolated, uses safe DOM construction, and stays same-origin; specified for Rabbita UI tests.
- `test_exact_editor_endpoints_and_canonical_controller_markers`, `test_timeline_is_rendered_from_server_state_without_direct_clip_array_mutation` — exact native endpoints and server-owned timeline state drive the controller; specified.
- `test_editor_controls_accessibility_keyboard_and_real_preview_contract`, `test_asset_filters_preview_states_and_visible_trim_handles`, `test_live_regions_responsive_overflow_and_reduced_motion_contracts` — accessibility, keyboard control, preview, filters, trim handles, live regions, responsive overflow, and reduced motion remain observable; specified.
- `test_editor_has_no_publication_control_or_external_authority` — editor exposes no publication or external-effect authority; specified.
- browser controller journey — covers the complete controller interaction path; specified as a Rabbita UI-to-UI gate.

## `tests/test_manifest_contract.py`

- `test_compiled_and_static_manifests_have_identical_canonical_json`, `test_every_reference_is_pack_owned_and_exists`, `test_every_tool_schema_is_declared_and_owner_is_pack_local` — compiled/static parity, pack ownership, and tool/schema declarations are native-boundary.
- `test_active_ci_runs_verified_moonbit_and_compiled_manifest_contract` — CI invokes MoonBit boundary, manifest, test, host build, and Rabbita build; native-boundary.
- `test_editor_and_bookkeeper_schema_sets_are_complete`, `test_editor_and_bookkeeper_tool_mappings_are_exact`, `test_authority_and_review_boundaries_are_narrow`, `test_current_production_graph_names_and_explicit_compatibility_aliases`, `test_canonical_three_gap_taxonomy_is_unchanged` — the Bookkeeper expectations are superseded by MC-8. New manifest coverage must assert the absence of Bookkeeper/MoonFlow-owned tools and the presence of only Mooncast evidence/handoff-reference tools; Three-Gap taxonomy is not interpreted in this pack.

## `tests/test_pack_boundary.py`

- `test_valid_pack_and_neutral_wire_names_pass`, `test_missing_and_escaping_manifest_references_fail`, `test_undeclared_tool_schema_and_non_pack_owner_fail` — valid neutral contracts pass while missing/escaping refs, undeclared schemas, and foreign owners fail; native-boundary.
- `test_absolute_sibling_and_external_local_dependency_fail`, `test_absolute_config_and_source_import_paths_fail`, `test_generic_core_import_and_embedded_moonfish_fail` — sibling paths, local dependency escapes, generic imports, and embedded foreign products fail; native-boundary.
- `test_symlinked_manifest_reference_outside_pack_fails`, `test_duplicate_manifest_key_fails_closed`, `test_checked_in_repository_passes` — symlink escape, decoded duplicate JSON keys, and full repository scanning are native-boundary.

## `tests/test_service.py`

- `test_health_and_both_ui_routes`, `test_editor_controller_static_get_and_head_at_both_mounts`, `test_head_supports_ui_health_and_media_smoke_checks` — native health, studio/editor/client routes, static GET/HEAD, and media HEAD remain available; partially covered by native HTTP tests, full host integration specified.
- `test_manifest_route_relative_assets_and_api_are_directly_usable`, `test_chunked_json_generation_matches_moondesk_proxy_framing` — manifest-relative assets and proxy-compatible request framing remain usable; specified.
- `test_generated_file_is_real_probeable_mp4`, `test_generation_exposes_complete_pending_provenance`, `test_media_supports_range_for_browser_playback` — generated MP4 is probeable, provenance is complete/pending, and browser range requests work; range covered, media integration specified.
- `test_human_review_only_marks_separate_publication_eligibility`, `test_duration_cost_rights_and_safety_are_bounded`, `test_duplicate_brief_reuses_immutable_output` — human review changes only eligibility, bounds fail closed, and duplicate generation reuses immutable output; specified for production application integration tests.

## `tests/test_v2_pipeline.py`

- `test_project_episode_scene_shot_shape_and_ordered_gates`, `test_rights_duration_and_budget_fail_closed`, `test_qc_editorial_client_and_delivery_gates_recover` — project graph, G0–G7 ordering, rights/duration/budget, review recovery, client acceptance, and delivery gates are covered by `production_v2_test.mbt` in part; remaining end-to-end assertions are specified.
- `test_checked_in_v2_schemas_are_valid_json` — all v2 schemas remain valid Draft 2020-12 JSON; specified for manifest/schema tests.
- `test_provider_failure_then_restart_retry_is_idempotent`, `test_store_recovers_valid_temporary_project_after_restart` — provider and store restart/retry behavior is idempotent and durable; specified.
- `test_three_minute_master_has_audio_subtitles_labels_and_lineage` — the native compositor produces a real 3–8 minute master with audio, subtitles, labels, and exact lineage; specified as release media integration gate.
- `test_ui_shaped_create_advance_generate_assemble_review_deliver`, `test_systematic_ui_exposes_stage_and_action_selectors` — UI-shaped native API and Rabbita surfaces complete create→gate→generate→assemble→review→deliver→analytics; specified as the final UI-to-UI gate.

## Final release gate

The source deletion is complete. Promotion still requires the native studio
and all Rabbita surfaces to build, the MoonBit boundary command to pass, real
media integration with explicitly supplied tools, and one UI-to-UI closed-loop
release validation. Missing release evidence must block promotion; it does not
restore the retired implementation.
