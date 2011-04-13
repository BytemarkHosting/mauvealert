// rather simple first stab at automating image rollovers - any image with
// a class of auto_hover will set its source to be the original name + _hover.png
// when rolled over, and back again when the mouse moves away.
//
// need to initialise by calling addAutoHover() after document has loaded.
//
function addAutoHover() {
  $$('img.auto_hover').each(function(image) {
    image.observe('mouseover', function(event) { 
      image.src = image.src.gsub(".png", "_hover.png");
    });
    image.observe('mouseout', function(event) {
      image.src = image.src.gsub("_hover.png", ".png");
    });
    preload = new Image();
    preload.src = image.src.gsub(".png", "_hover.png");
  });
};

function addRefresh() {
  updater1 = new Ajax.PeriodicalUpdater("alert_summary", "/_alert_summary",  
    { method: 'get', frequency: 120 });
  updater2 = new Ajax.PeriodicalUpdater("alert_counts", "/_alert_counts",  
    { method: 'get', frequency: 120 });
}

// Pop up the big white box at the top when something goes wrong, scroll so 
// user can see it.
//
function reportError(message) {
  $('errors_list').insert('<li>'+message+'</li>');
  $('errors').show();
  $('errors').scrollTo();
}
// Hide the big white box again
//
function clearErrors() { $('errors').hide(); }

// Wrapper around reportError to report an error in updating a particular
// alert.
//
function acknowledgeFailed(id, message) {
  if (message) 
    reportError("<strong>Couldn't update alert "+id+":</strong> "+message);
  else
    reportError("<strong>Couldn't update alert "+id+"</strong>");
}

// Updates the page from a JSON representation of a particular alert.
//
function updateAlert(alert) {
  var strip = $('alert_'+alert.id);
  if (!strip) {
    reportError("Alert "+id+" not rendered - bug?");
    return;
  }
  
  image = strip.down(".acknowledge img");
  image.src = alert.acknowledged_at ? 
    "/images/acknowledge_acknowledged.png" :
    "/images/acknowledge_unacknowledged.png"
  
  if (strip.down(".source"))
    strip.down(".source").update(alert.source);
  if (strip.down(".subject"))
    strip.down(".subject").update(alert.subject);
  if (strip.down(".summary") && strip.down(".summary").down())
    strip.down(".summary").down().update(alert.summary);
  strip.next().update(alert.detail);
  
  if (alert.acknowledged_at)
    strip.next().hide();
}

// called when user hits the acknowledge button for an alert - makes a callback
// to the server to communicate the change, and updates the button 
// appropriately.
//
function toggleAcknowledge(id) {
  updater = new Ajax.Request('/alert/'+id+'/acknowledge', { 
  
    method: 'post',
    
    // ignored by server, see http://www.ruby-forum.com/topic/162976 for why
    postBody: 'x',
    
    onFailure: function(xhr) { acknowledgeFailed(id, "Failure - "+xhr.statusText); },
    
    onException: function(xhr, ex) { acknowledgeFailed(id, Dumper(ex)); },
    
    onSuccess: function(xhr) {
      if (xhr.status == 200) {
        content_type = xhr.getResponseHeader("Content-Type");
        if (content_type != "application/json") {
          acknowledgeFailed(id, "Got "+content_type+" not application/json from server");
        } else {
          updateAlert(xhr.responseText.evalJSON());
        }
      } else {
        acknowledgeFailed(id, "Connection problem");
      }
    }
  });
};


// Controls the showing of details on alerts.
function toggleDetailView(id) {
  updater = new Ajax.Request('/alert/'+id+'/toggleDetailView', {
    method: 'post',
    postBody: 'x',
    onFailure: function(xhr) { acknowledgeFailed(id, "Failure - "+xhr.statusText); },
    onException: function(xhr, ex) { acknowledgeFailed(id, Dumper(ex)); },
    onSuccess: function(xhr) {
      if (xhr.status == 200) {
        content_type = xhr.getResponseHeader("Content-Type");
        if (content_type != "application/json") {
          acknowledgeFailed(id, "Got "+content_type+" not application/json from server");
        } else {
          //updateAlert(xhr.responseText.evalJSON());
        }
      } else {
        acknowledgeFailed(id, "Connection problem");
      }
    }
  });
}


// Controls the showing of folding on alerts.
function toggleFoldingView(subject) {
  updater = new Ajax.Request('/alert/fold/'+subject, {
    method: 'post',
    postBody: 'x',
    onFailure: function(xhr) { acknowledgeFailed(subject, "Failure - "+xhr.statusText); },
    onException: function(xhr, ex) { acknowledgeFailed(subject, Dumper(ex)); },
    onSuccess: function(xhr) {
      if (xhr.status == 200) {
        content_type = xhr.getResponseHeader("Content-Type");
        if (content_type != "application/json") {
          acknowledgeFailed(subject, "Got "+content_type+" not application/json from server");
        } else {
          //updateAlert(xhr.responseText.evalJSON());
        }
      } else {
        acknowledgeFailed(subject, "Connection problem");
      }
    }
  });
}
