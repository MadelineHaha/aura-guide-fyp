const fs = require('fs');

let html = fs.readFileSync('admin-web/html/patients.html', 'utf8');
html = html.replace(`<button type="button" class="patient-tab" data-filter="stable" role="tab" aria-selected="false" id="tab-stable">
            Stable <span class="tab-count" id="count-stable">0</span>
          </button>
          <button type="button" class="patient-tab" data-filter="monitoring" role="tab" aria-selected="false" id="tab-monitoring">
            Monitoring <span class="tab-count" id="count-monitoring">0</span>
          </button>
          <button type="button" class="patient-tab" data-filter="critical" role="tab" aria-selected="false" id="tab-critical">
            Critical <span class="tab-count" id="count-critical">0</span>
          </button>`, `<button type="button" class="patient-tab" data-filter="active" role="tab" aria-selected="false" id="tab-active">
            Active <span class="tab-count" id="count-active">0</span>
          </button>
          <button type="button" class="patient-tab" data-filter="inactive" role="tab" aria-selected="false" id="tab-inactive">
            Inactive <span class="tab-count" id="count-inactive">0</span>
          </button>`);
fs.writeFileSync('admin-web/html/patients.html', html);

let js = fs.readFileSync('admin-web/js/user-patients-service.js', 'utf8');
js = js.replace(`function displayStatus(data) {
  const clinical = (data.clinicalStatus || "").toLowerCase();
  if (["stable", "monitoring", "critical"].includes(clinical)) return clinical;
  const account = (data.status || "").toLowerCase();
  if (account === "inactive") return "monitoring";
  return "stable";
}`, `function displayStatus(data) {
  const account = (data.status || "").toLowerCase();
  if (account === "inactive") return "inactive";
  return "active";
}`);
fs.writeFileSync('admin-web/js/user-patients-service.js', js);
