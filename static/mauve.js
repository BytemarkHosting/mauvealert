/*
 * This contains all the 'clever' javascript used on the page.
 */
var mouse_is_inside = false;

/*
try {
  $("#myselector").click (function () {});    //my jQuery code here
} catch (e) {
  //this executes if jQuery isn't loaded
  alert(e.message 
      + "\nCould be a network error leading to jquery not being loaded!\n"
      + "Reloading the page.");
  window.location.reload(true);
}
*/

////////////////////////////////////////////////////////////////////////////////
// Treeview data.
$(document).ready(function(){
	$("#blackAck").treeview({
		control: "#treecontrolAck",
		persist: "cookie",
		cookieId: "treeview-black"
	});

});
$(document).ready(function(){
	$("#blackNew").treeview({
		control: "#treecontrolNew",
		persist: "cookie",
		cookieId: "treeview-black"
	});
});

$(document).ready(function(){

  ////////////////////////////////////////////////////////////////////////////////
  // This allows pop! to do its thing, used for details.
  $.pop(); 

  ////////////////////////////////////////////////////////////////////////////////
  // Countdown code.
  
  /*
  // This binds to the timer that reloads the page every 300 seconds via callback.
  $('#reloadPage').countdown({until: +300, onExpiry: liftOff, format: 'MS'});

  // This is the callback that reloads the page.
  function liftOff() { 
    window.location.reload(true);
  }
  */


  ////////////////////////////////////////////////////////////////////////////////
  // Mouse outside of changeStatus form.
  // See url http://stackoverflow.com/questions/1403615/use-jquery-to-hide-div-when-click-outside-it
  $('.updateAlertStatus').hover(function(){ 
    mouse_is_inside=true; 
  }, function(){ 
    mouse_is_inside=false; 
  });
  $('body').mouseup(function(){ 
    if(! mouse_is_inside) 
    {
      //$(".updateAlertStatus").fadeOut(1000);
      //$('.darkMask').fadeOut(1000);
      $(".updateAlertStatus").hide();
      $('.darkMask').hide();
    }
  });
});

////////////////////////////////////////////////////////////////////////////////
// Acknowledge status functions.


////////////////////////////////////////////////////////////////////////////////
// Standards are there to be violated...
function mouseX(evt) {
  if (evt.pageX) return evt.pageX;
  else if (evt.clientX)
     return evt.clientX + (document.documentElement.scrollLeft ?
     document.documentElement.scrollLeft :
     document.body.scrollLeft);
  else return null;
}

////////////////////////////////////////////////////////////////////////////////
// Standards are there to be violated...
function mouseY(evt) {
  if (evt.pageY) return evt.pageY;
  else if (evt.clientY)
     return evt.clientY + (document.documentElement.scrollTop ?
     document.documentElement.scrollTop :
     document.body.scrollTop);
  else return null;
}

////////////////////////////////////////////////////////////////////////////////
// Shows the updateAlertStatus div where the mouse clicked and mask the rest of
// page.
function showAcknowledgeStatus (e, id, ackTime) {

  // Build the form.
  document.changeAlertStatusForm.AlertID.value = id;
  document.changeAlertStatusForm.AlertDefaultAcknowledgeTime.value = ackTime;
  var myselect=document.getElementById("sample");
  myselect.remove(0);
  str = returnTimeString(ackTime);
  myselect.add(new Option(str, ackTime, true, true), myselect.options[0])

  // Show the form.
  //leftVal = mouseX(e);
  leftVal = 2
  topVal = mouseY(e);
  $('.updateAlertStatus').css({left:leftVal,top:topVal}).fadeIn(500);
  $('.darkMask').css({height:$(document).height()}).show();
}

// Returns the default time. 
function returnTimeString (time) {
  hrs = time / 3600
  if (1 == hrs)
  {
    str = "1 hour"
  }
  else if (24 > hrs && 1 > hrs)
  {
    str = hrs + " hours"
  }
  else if (24 == hrs)
  {
    str = "1 day"
  }
  else if (24 < hrs && 168 > hrs)
  {
    str = hrs / 24 + " days"
  }
  else if (168 == hrs)
  {
    str = "1 week"
  }
  else 
  {
    str = hrs / 168 + " weeks"
  }
  return str + ", default."
}

////////////////////////////////////////////////////////////////////////////////
// Shows the updateAlertSatus div for group of alerts. 
function showBulkAcknowledgeStatus(e, ids, ackTime)
{
  for (i in ids) 
  {
    changeAcknowledgeStatusCall(ids[i], ackTime);
  }
  //window.location.reload(true);
  tmp = $('#firstAlert'+ids[0]);
  tmp.remove()
}

function changeAcknowledgeStatusCall (id, acknowledgedUntil) {
  $.post('/alert/acknowledge/'+id+'/'+acknowledgedUntil);
  tmp = $('#alert'+id)
  tmp.remove();
  tmp.appendTo('#blackAck');
}

////////////////////////////////////////////////////////////////////////////////
// Actually gets the alert updated and moves it to the right list.
// Note that id is a numberical ID of the alert.
// Note that acknowledgedUntil is a number of seconds. 
function changeAcknowledgeStatus (id, acknowledgedUntil) {
  if (-1 != id)
  {
    changeAcknowledgeStatusCall(id, acknowledgedUntil);
  }
  $(".updateAlertStatus").hide();
  $('.darkMask').hide();
}

////////////////////////////////////////////////////////////////////////////////
// Clears (aka trash aka delete) an alert.
// THIS IS NOT WHAT YOU WANT
// url http://stackoverflow.com/questions/95600/jquery-error-option-in-ajax-utility
// url http://stackoverflow.com/questions/377644/jquery-ajax-error-handling-show-custom-exception-messages
function clearAlert (id) {
  $.post('/alert/'+id+'/clear');
  $(".updateAlertStatus").hide();
  $('.darkMask').hide();
  tmp = $('#alert'+id)
  tmp.remove();
}

////////////////////////////////////////////////////////////////////////////////
// Raises (aka unacknowledge) an alert.
function raiseAlert (id) {
  $.post('/alert/'+id+'/raise');
  $(".updateAlertStatus").hide();
  $('.darkMask').hide();
  tmp = $('#alert'+id)
  tmp.remove();
  tmp.appendTo('#blackNew');
}


////////////////////////////////////////////////////////////////////////////////
// EOF
