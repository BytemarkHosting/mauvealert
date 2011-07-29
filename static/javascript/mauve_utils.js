
function updateDate() {
  //
  //  Date.getTime() returns *milliseconds*
  //
  var this_date = workoutDate( $( '#n_hours' ).val(), $( '#type_hours' ).val() );
  $( '#ack_until' ).val( this_date.getTime()/1000 );

  // 
  // Use a asynchronous ajax convert a date to a human string.  NB Date.getTime()
  // returns *milliseconds*
  //
  $.ajax( {
    url:     '/ajax/time_to_s_human/'+this_date.getTime()/1000, 
    timeout: 1000,
    success: function( data )  { $( '#ack_until_text' ).html( "( until "+data+" )" ); },
    error:   function( a,b,c ) { $( '#ack_until_text' ).html( "( until "+this_date.toString()+" )" ); }
  } );

  return false;
}

function workoutDate( h, type ) {

  n = new Number( h );
  n *= 3600 * 1000;

  if ( type == null ) {
    type = "wallclock" ;
  }

  var step = 3600 * 1000;
  //
  // Get the time now, in milliseconds
  //
  var d    = new Date();
  var t    = d.getTime();
  //
  // Can't ack longer than a week
  //
  var maxDate = new Date( d.getTime() + 1000 * 86400 * 8 )


  //
  // Work out how much time to subtract now
  //
  while ( n >= 0 && t < maxDate.getTime() ) {
    //
    // If we're currently OK, and we won't be OK after the next step ( or
    // vice-versa ) decrease step size, and try again
    //
    if ( doTimeTest( t, type ) != doTimeTest( t+step, type ) ) {
      //
      // Unless we're on the smallest step, try a smaller one.
      //
      if ( step > 1000 ) {
        step /= 60;

      } else {
        if ( doTimeTest( t, type ) ) n -= step;
        t += step;

        //
        // Set the step size back to an hour
        //
        step = 3600*1000;
      }

      continue;
    } 

    //
    // Decrease the time by the step size if we're currently OK.
    //
    if ( doTimeTest( t, type ) ) n -= step;
    t += step;
  }

  //
  // Substract any overshoot.
  //
  if ( n < 0 ) t += n;

  //
  // Make sure we can't ack alerts too far in the future.
  //
  return ( t > maxDate.getTime() ? maxDate : new Date( t ) );
}

function fetchDetail( a ) {
  // Use a synchronous ajax request to fetch the date.
  $.get( '/ajax/alerts_table_alert_detail/'+a,
    function( data ) { 
      $( '#tr_summary_'+a ).after( data );
      // Only fetch the data once.
      $( '#a_detail_'+a ).attr( "onclick",null ).click( function() { $( '#tr_detail_'+a ).toggle(); return false; } );
  } );

  return false;
}

//
// This expects its arguments as a time in milliseconds, and a type of "working", "daytime", or something else.
//
function doTimeTest( t, type ) {
  
  var d = new Date( t );
  var r = false;

  switch ( type ) {
    case "working":
      r = ( d.getDay() > 0 && d.getDay() < 6 && 
          ( ( d.getHours() >= 9 && d.getHours() <= 16 ) || 
            ( d.getHours() == 8 && d.getMinutes() >= 30 ) 
          ) );
      break;

    case "daytime":
      r = ( d.getHours() >= 8 && d.getHours() <= 21 );
      break;

    default:
      r = true;
  } 

  return r;
}

