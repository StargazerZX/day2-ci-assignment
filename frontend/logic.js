/*
 * PodPoll UI logic: pure functions only (no DOM), so they can be unit-tested with
 * `node --test frontend/tests/` and loaded unchanged by the browser (window.PodPollLogic).
 */
(function (root) {
  "use strict";

  // Environment badge colours. The value comes from the API's answer, not the frontend's,
  // so a dev frontend wired to a prod API shows red.
  function envColour(env) {
    switch (env) {
      case "prod": return "#b91c1c";      // red
      case "staging": return "#c2410c";   // orange
      case "dev": return "#15803d";       // green
      case "preview": return "#0f766e";   // teal
      case "default": return "#1d4ed8";   // blue
      default: return "#7e22ce";          // purple: anything else
    }
  }

  // "2.3.1-abc123" -> "2", "v3.0" -> "3", "dev" -> "". Only the major picks the theme.
  function majorOf(version) {
    const m = /^v?(\d+)/.exec(String(version ?? ""));
    return m ? String(Number(m[1])) : "";
  }

  function isKnownSha(sha) {
    return /^[0-9a-f]{7,40}$/.test(String(sha ?? ""));
  }

  function shortSha(sha) {
    return isKnownSha(sha) ? String(sha).slice(0, 7) : "unknown";
  }

  // Only flag a mixed release when BOTH sides know their commit and they differ.
  function isMixedRelease(frontendSha, apiSha) {
    return isKnownSha(frontendSha) && isKnownSha(apiSha) && frontendSha !== apiSha;
  }

  function isSafeUrl(url) {
    return /^https?:\/\/[0-9A-Za-z._~:/?#@!$&()*+,;=%-]+$/.test(String(url ?? ""));
  }

  function commitUrl(sourceUrl, sha) {
    return isSafeUrl(sourceUrl) && isKnownSha(sha) ? `${sourceUrl}/commit/${sha}` : "";
  }

  // "2026-10-11T09:30:00Z" -> "5 min ago"
  function ageText(iso, nowMs) {
    if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(String(iso ?? ""))) return "unknown";
    const seconds = Math.round((nowMs - Date.parse(iso)) / 1000);
    if (Number.isNaN(seconds)) return "unknown";
    if (seconds < 0) return "in the future?";
    if (seconds < 10) return "just now";
    if (seconds < 90) return `${seconds} s ago`;
    if (seconds < 90 * 60) return `${Math.round(seconds / 60)} min ago`;
    if (seconds < 36 * 3600) return `${Math.round(seconds / 3600)} h ago`;
    return `${Math.round(seconds / 86400)} days ago`;
  }

  function chaosSummary(chaos) {
    if (!chaos) return "";
    const parts = [];
    if (chaos.ready_fail) parts.push("readiness failing");
    if (chaos.start_delay_seconds > 0) parts.push(`slow start ${chaos.start_delay_seconds}s`);
    if (chaos.error_rate > 0) parts.push(`${Math.round(chaos.error_rate * 100)}% vote errors`);
    return parts.join(", ");
  }

  // All platform-specific copy lives here, in ONE object.
  const HINTS = {
    kubernetes: {
      envLabel: "namespace",
      instance: "pod",
      whoSub: "(Services & Deployments)",
      whoHint: "Refreshes every 1.5 s. Shows which frontend and API pod answered.",
      debug: ["kubectl get endpoints api", "kubectl get pods", "kubectl describe svc api"],
    },
    ecs: {
      envLabel: "env",
      instance: "task",
      whoSub: "(ECS services)",
      whoHint: "Refreshes every 1.5 s. Shows which frontend and API task answered.",
      debug: ["aws ecs describe-services --cluster <cluster> --services <api-service>",
              "aws logs tail <log-group> --follow"],
    },
    docker: {
      envLabel: "env",
      instance: "container",
      whoSub: "(Compose services)",
      whoHint: "Refreshes every 1.5 s. Shows which frontend and API container answered.",
      debug: ["docker compose ps", "docker compose logs api",
              "docker compose exec frontend wget -qO- http://api:5000/readyz"],
    },
  };

  // Before the API has ever answered we don't know the platform: offer one hint per platform.
  const UNKNOWN_PLATFORM_DEBUG = ["docker compose ps", "kubectl get endpoints api",
                                  "aws ecs describe-services --cluster <cluster> --services <api-service>"];

  function hintsFor(platform) {
    return HINTS[platform] || null;
  }

  const api = { envColour, majorOf, isKnownSha, shortSha, isMixedRelease, isSafeUrl, commitUrl,
                ageText, chaosSummary, hintsFor, HINTS, UNKNOWN_PLATFORM_DEBUG };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.PodPollLogic = api;
})(typeof self !== "undefined" ? self : this);
