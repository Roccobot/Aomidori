"use strict";
// Neutral configuration for a page opened outside the Worker (a local file, the
// checks in `tools/`): the page then works without the cloud. The private Worker
// replaces this response with its same-origin API configuration, without secrets.
// Since 2026-10-03 GitHub Pages leaves the feedback document out (`pages.yml`).
window.feedbackCloudConfig = null;
