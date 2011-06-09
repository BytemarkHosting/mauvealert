
// Controls the showing of details on alerts.

function next_date(n, d, when) {
  switch(when) {
    case "daytime"
      next_daytime_hour(d) + n;
    case "working"
      next_working_hour(d) + n;
    default
      d + n;
  }
}

function is_daytime_hour(d) { 
  return (d.getHours() => 8 and d.getHours() <= 17);
}


function next_working_hour(d) {


}

