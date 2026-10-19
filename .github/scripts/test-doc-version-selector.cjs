const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "doc-version-selector.js"), "utf8");
const versions = ["v0.0.15", "v0.0.14"];

for (const prefix of ["", ...versions.map(tag => "versions/" + tag)]) {
  test("DocC selector links, selection and SPA persistence: " + (prefix || "default"), function () {
    const base = "https://contentauth.github.io/c2pa-swift/";
    const tag = prefix ? prefix.split("/").pop() : versions[0];
    function element() {
      return {
        children: [],
        appendChild(child) { this.children.push(child); },
        setAttribute(name, value) { this[name] = value; },
        addEventListener(event, listener) { this[event] = listener; }
      };
    }
    const body = element();
    const app = element();
    body.appendChild(app);
    let destination;
    vm.runInNewContext(source, {
      URL,
      document: {
        currentScript: {
          src: new URL((prefix ? prefix + "/" : "") + "doc-version-selector.js", base).href,
          dataset: { versions: JSON.stringify(versions), version: tag, prefix }
        },
        body,
        createElement: element
      },
      window: { location: { assign(url) { destination = url; } } }
    });
    const label = body.children[1];
    const select = label.children[0];
    assert.equal(label.id, "c2pa-doc-version-selector");
    assert.equal(select["aria-label"], "API documentation version");
    assert.equal(select.children.length, 2);
    for (const [index, option] of select.children.entries()) {
      assert.equal(option.value, base + "versions/" + versions[index] + "/documentation/c2pa/");
      assert.equal(option.selected, versions[index] === tag);
      assert.equal(option.textContent, versions[index]);
    }
    // DocC can replace its own content without removing the sibling control.
    app.children = [element()];
    assert.equal(body.children[1], label);
    select.value = select.children[1].value;
    select.change();
    assert.equal(destination, base + "versions/v0.0.14/documentation/c2pa/");
  });
}
