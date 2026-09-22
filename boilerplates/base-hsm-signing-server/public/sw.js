self.addEventListener("push", event => {
  let data={title:"SignZone approval required",body:"Open SignZone to review a signing request."};
  try { data={...data,...event.data.json()}; } catch (_) {}
  event.waitUntil(self.registration.showNotification(data.title,{body:data.body,tag:data.tag||"signzone-approval",data:{url:data.url||"/signing"}}));
});
self.addEventListener("notificationclick", event => { event.notification.close(); event.waitUntil(clients.openWindow(event.notification.data?.url || "/signing")); });
