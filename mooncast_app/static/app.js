const form = document.querySelector("#brief-form");
const promptInput = document.querySelector("#prompt");
const durationInput = document.querySelector("#duration");
const durationLabel = document.querySelector("#duration-label");
const statusNode = document.querySelector("#status");
const video = document.querySelector("#result-video");
const placeholder = document.querySelector("#video-placeholder");
const provenance = document.querySelector("#provenance");
const generateButton = document.querySelector("#generate");
const approveButton = document.querySelector("#approve");
let currentAsset = null;

durationInput.addEventListener("input", () => {
  durationLabel.textContent = `${durationInput.value}s`;
});

function evidenceItem(label, value) {
  return `<div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(String(value))}</dd></div>`;
}

function renderEvidence(asset) {
  const review = asset.human_review || { status: "pending" };
  provenance.className = "provenance-grid";
  provenance.innerHTML = [
    evidenceItem("Asset", asset.asset_id),
    evidenceItem("SHA-256", asset.sha256),
    evidenceItem("Provider / model", `${asset.provider} / ${asset.model}`),
    evidenceItem("Cost", `${asset.cost.currency} ${asset.cost.amount.toFixed(2)} / ${asset.cost.maximum.toFixed(2)} max`),
    evidenceItem("Rights", `${asset.rights.owner} · ${asset.rights.scope}`),
    evidenceItem("Safety", asset.safety.status),
    evidenceItem("Labels", `explicit + implicit`),
    evidenceItem("Human review", review.status),
    evidenceItem("Publication", asset.publication.eligible ? "eligible, not published" : "blocked, not published"),
    `<div class="wide"><dt>Prompt</dt><dd>${escapeHtml(asset.prompt)}</dd></div>`,
  ].join("");
}

function escapeHtml(value) {
  const node = document.createElement("span");
  node.textContent = value;
  return node.innerHTML;
}

async function parseResponse(response) {
  const value = await response.json();
  if (!response.ok) throw new Error(value.error?.message || "Request failed");
  return value;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  generateButton.disabled = true;
  approveButton.disabled = true;
  statusNode.textContent = "Rendering a bounded local MP4…";
  try {
    const asset = await parseResponse(await fetch("api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prompt: promptInput.value,
        duration_seconds: Number(durationInput.value),
        rights_owner: document.querySelector("#rights-owner").value,
        rights_confirmed: document.querySelector("#rights-confirmed").checked,
        brand_name: document.querySelector("#brand").value,
        audience: document.querySelector("#audience").value,
      }),
    }));
    currentAsset = asset.asset_id;
    video.src = asset.video_url;
    video.hidden = false;
    placeholder.hidden = true;
    video.load();
    renderEvidence(asset);
    approveButton.disabled = false;
    statusNode.textContent = `Ready · ${asset.media.duration_seconds}s · ${asset.cost.currency} ${asset.cost.amount.toFixed(2)}`;
  } catch (error) {
    statusNode.textContent = error.message;
  } finally {
    generateButton.disabled = false;
  }
});

approveButton.addEventListener("click", async () => {
  if (!currentAsset) return;
  approveButton.disabled = true;
  statusNode.textContent = "Recording immutable human review…";
  try {
    const asset = await parseResponse(await fetch(`api/assets/${currentAsset}/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        reviewer_id: document.querySelector("#reviewer").value,
        decision: "approve",
        note: "Approved in Mooncast Studio",
      }),
    }));
    renderEvidence(asset);
    statusNode.textContent = "Approved for a separate publishing adapter · not published";
  } catch (error) {
    statusNode.textContent = error.message;
    approveButton.disabled = false;
  }
});
