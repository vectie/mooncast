///|
pub(all) struct ClientPortalAccess {
  contract : String
  portal_id : String
  token_digest : String
  created_at : String
  raw_token_persisted : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientPortalCreation {
  contract : String
  portal : @commerce_domain.ClientPortal
  raw_token : String
  client_path : String
  raw_token_returned_once : Bool
  external_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientSafeProjection {
  contract : String
  portal_id : String
  project_id : String
  client_name : String
  brand : @commerce_domain.ClientBrand
  expires_at : String
  scopes : Array[String]
  master_sha256 : String
  delivery_digest : String
  build_id : String
  build_digest : String
  annotations : Array[@commerce_domain.ClientAnnotation]
  decisions : Array[@commerce_domain.ClientDecisionReceipt]
  accepted_download_available : Bool
  provider_data_included : Bool
  publication_authority : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientPortalObservation {
  contract : String
  observation_id : String
  project_id : String
  portal_id : String
  action : String
  master_sha256 : String
  build_digest : String
  evidence_digest : String
  observed_at : String
  response_effect_observed : Bool
  payment_effect_performed : Bool
  publication_effect_performed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
fn token_digest(raw : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(raw)))
}

///|
fn access_key(portal_id : String) -> String {
  "client-access-" + portal_id + ".json"
}

///|
fn portal_observation_key(observation_id : String) -> String {
  "client-observation-" + observation_id + ".json"
}

///|
pub async fn CommercialApplicationService::record_client_observation(
  self : CommercialApplicationService,
  portal : @commerce_domain.ClientPortal,
  action : String,
  evidence_digest : String,
  observed_at : String,
) -> ClientPortalObservation {
  if (
      action != "portal.accessed" &&
      action != "master.streamed" &&
      action != "annotation.created" &&
      action != "delivery.decided" &&
      action != "delivery.downloaded"
    ) ||
    evidence_digest == "" ||
    observed_at == "" {
    raise CommercialCommandRejected("client_observation_invalid")
  }
  let observation : ClientPortalObservation = {
    contract: "mooncast.client-portal-observation.v1",
    observation_id: @runtime.new_id(prefix="client-observation"),
    project_id: portal.project_id,
    portal_id: portal.portal_id,
    action,
    master_sha256: portal.master_sha256,
    build_digest: portal.build_digest,
    evidence_digest,
    observed_at,
    response_effect_observed: action == "master.streamed" ||
    action == "delivery.downloaded",
    payment_effect_performed: false,
    publication_effect_performed: false,
  }
  ignore(
    self.store.put_json(
      portal_observation_key(observation.observation_id),
      observation.to_json(),
    ),
  )
  observation
}

///|
pub async fn CommercialApplicationService::client_observations(
  self : CommercialApplicationService,
  project_id : String,
) -> Array[ClientPortalObservation] {
  let observations : Array[ClientPortalObservation] = []
  for key in self.store.list_keys(prefix="client-observation-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let observation : ClientPortalObservation = @json.from_json(value) catch {
          _ => continue
        }
        if observation.project_id == project_id {
          observations.push(observation)
        }
      }
      None => ()
    }
  }
  observations
}

///|
pub async fn CommercialApplicationService::create_client_portal(
  self : CommercialApplicationService,
  command : @commerce_domain.CommercialCommand,
) -> ClientPortalCreation {
  let portal = match command.portal {
    Some(value) => value
    None => raise CommercialCommandRejected("client_portal_required")
  }
  ignore(self.submit(command))
  let raw_token = @runtime.new_id(prefix="client") +
    @runtime.new_id(prefix="token")
  let access : ClientPortalAccess = {
    contract: "mooncast.client-portal-access.v1",
    portal_id: portal.portal_id,
    token_digest: token_digest(raw_token),
    created_at: portal.created_at,
    raw_token_persisted: false,
  }
  ignore(self.store.put_json(access_key(portal.portal_id), access.to_json()))
  {
    contract: "mooncast.client-portal-create-result.v1",
    portal,
    raw_token,
    client_path: "/client/" + raw_token,
    raw_token_returned_once: true,
    external_effect_performed: false,
  }
}

///|
async fn CommercialApplicationService::portal_for_token(
  self : CommercialApplicationService,
  raw_token : String,
  observed_at : String,
) -> @commerce_domain.ClientPortal {
  let wanted = token_digest(raw_token)
  let mut portal_id : String? = None
  for key in self.store.list_keys(prefix="client-access-", suffix=".json") {
    match self.store.get_json(key) {
      Some(value) => {
        let access : ClientPortalAccess = @json.from_json(value) catch {
          _ => continue
        }
        if access.token_digest == wanted {
          portal_id = Some(access.portal_id)
        }
      }
      None => ()
    }
  }
  let id = match portal_id {
    Some(value) => value
    None => raise ClientPortalNotFound
  }
  let snapshot = self.load()
  let mut current : @commerce_domain.ClientPortal? = None
  for portal in snapshot.portals {
    if portal.portal_id == id {
      match current {
        None => current = Some(portal)
        Some(previous) =>
          if portal.revision > previous.revision {
            current = Some(portal)
          }
      }
    }
  }
  let portal = match current {
    Some(value) => value
    None => raise ClientPortalNotFound
  }
  if portal.status != "active" || portal.expires_at <= observed_at {
    raise ClientPortalUnavailable
  }
  portal
}

///|
/// Resolves the exact active portal bound to an opaque client token without
/// exposing the stored token digest. Native HTTP composition uses this to bind
/// the portal to its immutable delivery build before serving client media.
pub async fn CommercialApplicationService::client_portal_for_token(
  self : CommercialApplicationService,
  raw_token : String,
  observed_at : String,
) -> @commerce_domain.ClientPortal {
  self.portal_for_token(raw_token, observed_at)
}

///|
pub async fn CommercialApplicationService::client_projection(
  self : CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  current_master_sha256 : String,
  current_delivery_digest : String,
  build : @execution.DeliveryBuild,
) -> ClientSafeProjection {
  let portal = self.portal_for_token(raw_token, observed_at)
  if !@commerce_domain.portal_current(
      portal, current_master_sha256, current_delivery_digest, build,
    ) {
    raise ClientPortalStale
  }
  {
    contract: "mooncast.client-portal-projection.v1",
    portal_id: portal.portal_id,
    project_id: portal.project_id,
    client_name: portal.client_name,
    brand: portal.brand,
    expires_at: portal.expires_at,
    scopes: portal.scopes,
    master_sha256: portal.master_sha256,
    delivery_digest: portal.delivery_digest,
    build_id: portal.build_id,
    build_digest: portal.build_digest,
    annotations: portal.annotations,
    decisions: portal.decisions,
    accepted_download_available: portal.decisions.any(decision => {
      decision.decision == "accept"
    }),
    provider_data_included: false,
    publication_authority: false,
  }
}

///|
async fn CommercialApplicationService::replace_portal(
  self : CommercialApplicationService,
  updated : @commerce_domain.ClientPortal,
) -> Unit {
  let snapshot = self.load()
  let portals = snapshot.portals.filter(portal => {
    portal.portal_id != updated.portal_id
  })
  portals.push(updated)
  self.save({ ..snapshot, revision: snapshot.revision + 1, portals })
}

///|
pub async fn CommercialApplicationService::annotate(
  self : CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  annotation : @commerce_domain.ClientAnnotation,
  master_duration_seconds : Double,
  record_digest : String,
) -> @commerce_domain.ClientAnnotation {
  let portal = self.portal_for_token(raw_token, observed_at)
  if !portal.scopes.any(scope => scope == "annotation-write") {
    raise ClientProjectionDenied
  }
  let updated = match
    @commerce_domain.append_annotation(
      portal, annotation, master_duration_seconds, observed_at, record_digest,
    ) {
    Some(value) => value
    None => raise CommercialCommandRejected("client_annotation_invalid")
  }
  self.replace_portal(updated)
  ignore(
    self.record_client_observation(
      updated,
      "annotation.created",
      annotation.digest,
      observed_at,
    ),
  )
  annotation
}

///|
pub async fn CommercialApplicationService::record_client_decision(
  self : CommercialApplicationService,
  raw_token : String,
  observed_at : String,
  decision : @commerce_domain.ClientDecisionReceipt,
  record_digest : String,
) -> @commerce_domain.ClientDecisionReceipt {
  let portal = self.portal_for_token(raw_token, observed_at)
  if !portal.scopes.any(scope => scope == "delivery-decision") {
    raise ClientProjectionDenied
  }
  if decision.decision == "request-revision" {
    let snapshot = self.load()
    let mut rounds = 0
    for candidate in snapshot.portals {
      if candidate.project_id == portal.project_id {
        for recorded in candidate.decisions {
          if recorded.decision == "request-revision" {
            rounds = rounds + 1
          }
        }
      }
    }
    if rounds >= 2 {
      raise CommercialCommandRejected("client_revision_limit")
    }
  }
  let updated = match
    @commerce_domain.append_client_decision(
      portal, decision, observed_at, record_digest,
    ) {
    Some(value) => value
    None => raise CommercialCommandRejected("client_decision_invalid")
  }
  self.replace_portal(updated)
  ignore(
    self.record_client_observation(
      updated,
      "delivery.decided",
      decision.digest,
      observed_at,
    ),
  )
  decision
}
