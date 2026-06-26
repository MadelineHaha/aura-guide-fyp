const fs = require('fs');

let code = fs.readFileSync('admin-web/js/dashboard.js', 'utf8');

code = code.replace(/pending_chat_user/g, "auraOpenCommunicationPatientId");

fs.writeFileSync('admin-web/js/dashboard.js', code);
console.log("Successfully updated chat key in dashboard.js");
