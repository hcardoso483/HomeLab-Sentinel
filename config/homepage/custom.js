(() => {
  "use strict";

  const SERVICE_ID = "sentinel-service-discovery";
  const STATUS_PROXY =
    "/api/services/proxy" +
    "?group=Service%20Discovery" +
    "&service=Service%20Discovery%20Engine" +
    "&index=0" +
    "&query=%7B%22refreshInterval%22%3A10000%7D";

  const DETAIL_PROXY =
    "/api/services/proxy" +
    "?group=Service%20Discovery" +
    "&service=Service%20Discovery%20Engine" +
    "&index=1" +
    "&query=%7B%22refreshInterval%22%3A10000%7D";

  const PANEL_ID = "sentinel-service-discovery-results";

  function ipv4Value(address) {
    const parts = address.split(".").map(Number);

    if (
      parts.length !== 4 ||
      parts.some(part => !Number.isInteger(part) || part < 0 || part > 255)
    ) {
      return Number.MAX_SAFE_INTEGER;
    }

    return (
      parts[0] * 16777216 +
      parts[1] * 65536 +
      parts[2] * 256 +
      parts[3]
    );
  }

  function text(value, fallback = "—") {
    return value === null || value === undefined || value === ""
      ? fallback
      : String(value);
  }

  function createEndpoint(endpoint) {
    const row = document.createElement("div");
    row.className = "sentinel-sd-endpoint";

    const identity = document.createElement("span");
    identity.className = "sentinel-sd-endpoint-identity";

    const service = endpoint.service ? ` (${endpoint.service})` : "";
    identity.textContent =
      `${text(endpoint.protocol).toUpperCase()} ${text(endpoint.port)}${service}`;

    const state = document.createElement("span");
    state.className =
      `sentinel-sd-state sentinel-sd-state-${String(
        endpoint.endpoint_state || "unknown"
      ).toLowerCase()}`;
    state.textContent = text(endpoint.endpoint_state, "UNKNOWN");

    row.append(identity, state);

    if (endpoint.last_observed_at) {
      const lastSeen = document.createElement("div");
      lastSeen.className = "sentinel-sd-last-seen";
      lastSeen.textContent = `Last seen: ${endpoint.last_observed_at}`;
      row.append(lastSeen);
    }

    return row;
  }

  function createTarget(target) {
    const details = document.createElement("details");
    details.className = "sentinel-sd-target";

    const summary = document.createElement("summary");
    summary.className = "sentinel-sd-target-summary";

    const address = document.createElement("span");
    address.className = "sentinel-sd-address";
    address.textContent = text(target.address, "Unknown address");

    const counts = document.createElement("span");
    counts.className = "sentinel-sd-counts";
    counts.textContent =
      `${target.observed ?? 0} observed · ${target.stale ?? 0} stale`;

    summary.append(address, counts);
    details.append(summary);

    const body = document.createElement("div");
    body.className = "sentinel-sd-target-body";

    const metadata = document.createElement("div");
    metadata.className = "sentinel-sd-metadata";

    const inspection = target.latest_inspection || {};

    metadata.textContent =
      `Entity: ${text(target.entity_id)} · ` +
      `Inspection: ${text(inspection.outcome, "none")}`;

    body.append(metadata);

    const endpoints = Array.isArray(target.endpoints)
      ? [...target.endpoints]
      : [];

    endpoints.sort((a, b) => {
      const protocolCompare = text(a.protocol).localeCompare(text(b.protocol));
      if (protocolCompare !== 0) return protocolCompare;
      return Number(a.port || 0) - Number(b.port || 0);
    });

    if (endpoints.length === 0) {
      const empty = document.createElement("div");
      empty.className = "sentinel-sd-empty";
      empty.textContent = "No current or stale endpoints.";
      body.append(empty);
    } else {
      endpoints.forEach(endpoint => body.append(createEndpoint(endpoint)));
    }

    details.append(body);
    return details;
  }

  function timerText(timer) {
    if (!timer || typeof timer !== "object") return "Unavailable";

    const runtime = text(timer.runtime, "UNKNOWN");
    const schedule = timer.schedule;

    return schedule
      ? `${runtime} · every ${schedule}`
      : runtime;
  }

  function createOperationalItem(label, value) {
    const item = document.createElement("div");
    item.className = "sentinel-sd-operation";

    const labelElement = document.createElement("span");
    labelElement.className = "sentinel-sd-operation-label";
    labelElement.textContent = label;

    const valueElement = document.createElement("span");
    valueElement.className = "sentinel-sd-operation-value";
    valueElement.textContent = text(value, "Unavailable");

    item.append(labelElement, valueElement);
    return item;
  }

  function renderPanel(panel, payload, statusPayload) {
    const items = Array.isArray(payload.items) ? [...payload.items] : [];

    items.sort((a, b) => {
      const addressCompare = ipv4Value(a.address) - ipv4Value(b.address);
      if (addressCompare !== 0) return addressCompare;

      return text(a.entity_id).localeCompare(text(b.entity_id));
    });

    const openTargets = new Set(
      [...panel.querySelectorAll(".sentinel-sd-target[open]")]
        .map(element => element.dataset.entityId)
        .filter(Boolean)
    );

    panel.replaceChildren();

    const summary = document.createElement("summary");
    summary.className = "sentinel-sd-panel-summary";

    const title = document.createElement("span");
    title.textContent = "IP Scan Results";

    const totals = document.createElement("span");
    totals.className = "sentinel-sd-panel-totals";

    const observed = items.reduce(
      (total, item) => total + Number(item.observed || 0),
      0
    );
    const stale = items.reduce(
      (total, item) => total + Number(item.stale || 0),
      0
    );

    totals.textContent =
      `${payload.targets ?? items.length} targets · ` +
      `${observed} observed · ${stale} stale`;

    summary.append(title, totals);
    panel.append(summary);

    const serviceStatus =
      statusPayload &&
      typeof statusPayload.service_discovery === "object"
        ? statusPayload.service_discovery
        : null;

    const operations = document.createElement("div");
    operations.className = "sentinel-sd-operations";

    operations.append(
      createOperationalItem(
        "Sweep",
        serviceStatus ? timerText(serviceStatus.normal_timer) : "Unavailable"
      ),
      createOperationalItem(
        "Retry",
        serviceStatus ? timerText(serviceStatus.retry_timer) : "Unavailable"
      ),
      createOperationalItem(
        "Retry Pool",
        serviceStatus ? serviceStatus.retry_pool : "Unavailable"
      ),
      createOperationalItem(
        "Provider",
        serviceStatus ? serviceStatus.provider : "Unavailable"
      )
    );

    panel.append(operations);

    const content = document.createElement("div");
    content.className = "sentinel-sd-panel-content";

    items.forEach(target => {
      const targetElement = createTarget(target);
      targetElement.dataset.entityId = text(target.entity_id, "");

      if (openTargets.has(targetElement.dataset.entityId)) {
        targetElement.open = true;
      }

      content.append(targetElement);
    });

    panel.append(content);
  }

  function renderError(panel, error) {
    panel.replaceChildren();

    const summary = document.createElement("summary");
    summary.textContent = "IP Scan Results — unavailable";
    panel.append(summary);

    const message = document.createElement("div");
    message.className = "sentinel-sd-error";
    message.textContent = `Unable to load discovery results: ${error.message}`;
    panel.append(message);
  }

  async function fetchJson(url) {
    const response = await fetch(url, {
      method: "GET",
      credentials: "same-origin",
      cache: "no-cache"
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    return response.json();
  }

  async function refresh(panel) {
    const [detailResult, statusResult] = await Promise.allSettled([
      fetchJson(DETAIL_PROXY),
      fetchJson(STATUS_PROXY)
    ]);

    if (detailResult.status === "rejected") {
      console.error(
        "HomeLab Sentinel Service Discovery:",
        detailResult.reason
      );
      renderError(panel, detailResult.reason);
      return;
    }

    if (statusResult.status === "rejected") {
      console.warn(
        "HomeLab Sentinel Service Discovery status:",
        statusResult.reason
      );
    }

    renderPanel(
      panel,
      detailResult.value,
      statusResult.status === "fulfilled" ? statusResult.value : null
    );
  }

  function install() {
    const service = document.getElementById(SERVICE_ID);
    if (!service) return false;

    if (document.getElementById(PANEL_ID)) return true;

    const card = service.querySelector(".service-card");
    if (!card) return false;

    const panel = document.createElement("details");
    panel.id = PANEL_ID;
    panel.className = "sentinel-sd-panel";

    card.append(panel);

    refresh(panel);
    window.setInterval(() => refresh(panel), 30000);

    return true;
  }

  if (!install()) {
    const observer = new MutationObserver(() => {
      if (install()) observer.disconnect();
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }
})();
