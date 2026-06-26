const fs = require('fs');
let html = fs.readFileSync('admin-web/html/patients.html', 'utf8');

const oldThead = `        <thead>
          <tr>
            <th scope="col">Patient</th>
            <th scope="col">Age</th>
            <th scope="col">Condition</th>
            <th scope="col">Last Visit</th>
            <th scope="col">Status</th>
            <th scope="col">Health Records</th>
            <th scope="col">Medications</th>
            <th scope="col">Profile</th>
          </tr>
        </thead>`;

const newThead = `        <thead>
          <tr>
            <th scope="col" class="patients-col-patient">Patient</th>
            <th scope="col" class="patients-col-name">Name</th>
            <th scope="col" class="patients-col-age">Age</th>
            <th scope="col" class="patients-col-gender" hidden>Gender</th>
            <th scope="col" class="patients-col-contact" hidden>Contact Number</th>
            <th scope="col" class="patients-col-registered" hidden>Registration Date</th>
            <th scope="col" class="patients-col-condition">Condition</th>
            <th scope="col" class="patients-col-caregiver" hidden>Caregiver Connected</th>
            <th scope="col" class="patients-col-visit">Last Visit</th>
            <th scope="col" class="patients-col-status">Status</th>
            <th scope="col" class="patients-col-records">Health Records</th>
            <th scope="col" class="patients-col-meds">Medications</th>
            <th scope="col" class="patients-col-profile">Profile</th>
            <th scope="col" class="patients-col-actions" hidden>Actions</th>
          </tr>
        </thead>`;

html = html.replace(oldThead, newThead);
fs.writeFileSync('admin-web/html/patients.html', html);
