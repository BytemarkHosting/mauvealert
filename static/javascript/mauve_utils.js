
function updateDate() {
  //
  //  Date.getTime() returns *milliseconds*
  //
  var this_date = workoutDate( $('#n_hours').val(), $('#type_hours').val() );
  $('#ack_until_text').html("(until "+humanDate(this_date)+")");
  $('#ack_until').val(this_date.getTime()/1000);

  return false;
}

function workoutDate(h, t) {
  var new_date = null;

  h = new Number(h);
  h = ( h > 300 ? 300 : h );

  // 
  // Use a synchronous ajax request to fetch the date.  Note that
  // Date.getTime() returns milliseconds..
  //
  $.ajax({
    url: '/ajax/time_in_x_hours/'+h+"/"+t,
    async: false,
    success: function(data) { new_date = new Date ( new Number(data) * 1000 ); }
  });

  return new_date;
}


function humanDate(d) {
  var new_date = null;

  if ( d == null ) {
    d = new Date();
  }

  // 
  // Use a synchronous ajax convert a date to a human string.  NB Date.getTime()
  // returns *milliseconds*
  //
  $.ajax({
    url: '/ajax/time_to_s_human/'+d.getTime()/1000, 
    async: false,
    success: function(data) { new_date = data; }
  });

  return new_date;
}

function fetchDetail(a) {
  // Use a synchronous ajax request to fetch the date.
  $.get('/ajax/alerts_table_alert_detail/'+a,
    function(data) { 
      $('#tr_summary_'+a).after(data);
      // Only fetch the data once.
      $('#a_detail_'+a).attr("onclick",null).click(function() { $('#tr_detail_'+a).toggle(); return false; });
  });

  return false;
}

