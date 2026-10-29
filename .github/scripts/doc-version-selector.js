(function () {
  "use strict";

  const script = document.currentScript;
  const versions = script.dataset.versions.split(" ");
  const assets = new URL(".", script.src);
  const root = new URL(script.dataset.prefix ? "../../" : "./", assets);
  const label = document.createElement("label");
  label.id = "c2pa-doc-version-selector";
  label.textContent = "Version: ";
  const select = document.createElement("select");
  select.setAttribute("aria-label", "API documentation version");
  for (const tag of versions) {
    const option = document.createElement("option");
    option.value = new URL("versions/" + tag + "/", root).href;
    option.textContent = tag;
    option.selected = tag === script.dataset.version;
    select.appendChild(option);
  }
  select.addEventListener("change", function () {
    const landing = new URL("documentation/c2pa/", select.value).href;
    const path = window.location.pathname;
    if (path.indexOf(assets.pathname + "documentation/") !== 0) {
      window.location.assign(landing);
      return;
    }
    // DocC page paths match across releases, so open the same page in the chosen
    // release when it exists there and its landing page when it does not.
    const page = new URL(path.slice(assets.pathname.length), select.value).href;
    fetch(page, { method: "HEAD" }).then(function (response) {
      window.location.assign(response.ok ? page + window.location.hash : landing);
    }, function () {
      window.location.assign(landing);
    });
  });
  label.appendChild(select);
  // Keep the selector outside DocC's application root so SPA navigation preserves it.
  document.body.appendChild(label);
})();
