///|
pub fn render_plan_to_json(value : RenderPlan) -> String {
  value.to_json().stringify()
}

///|
pub fn render_plan_from_json(input : StringView) -> RenderPlan raise {
  let value : RenderPlan = @json.from_json(@json.parse(input))
  if value.contract != "mooncast.editor-render-plan.v1" {
    fail("unsupported editor render-plan contract")
  }
  value
}

///|
pub fn cache_projection_to_json(value : CacheKeyProjection) -> String {
  value.to_json().stringify()
}

///|
pub fn cache_projection_from_json(
  input : StringView,
) -> CacheKeyProjection raise {
  let value : CacheKeyProjection = @json.from_json(@json.parse(input))
  if value.contract != "mooncast.editor-preview-cache-key.v1" {
    fail("unsupported editor cache-key contract")
  }
  value
}

///|
pub fn cache_report_to_json(value : PreviewCacheReport) -> String {
  value.to_json().stringify()
}

///|
pub fn cache_report_from_json(input : StringView) -> PreviewCacheReport raise {
  let value : PreviewCacheReport = @json.from_json(@json.parse(input))
  if value.contract != "mooncast.editor-preview-cache-report.v1" {
    fail("unsupported editor cache-report contract")
  }
  value
}
