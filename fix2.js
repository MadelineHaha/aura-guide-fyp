const fs = require('fs');
let c = fs.readFileSync('admin-web/js/appointments-service.js', 'utf8');
c = c.replace(`export {
  combineDateAndTime,
  dateToInputValue,
  formatErdDatetime,
  timeToInputValue,
  todayDateString,
} from "./clinic-date-utils.js";`, `export {
  combineDateAndTime,
  dateToInputValue,
  formatErdDatetime,
  timeToInputValue,
  todayDateString,
};`);
fs.writeFileSync('admin-web/js/appointments-service.js', c);
