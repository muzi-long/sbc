__CADDY_API_DOMAIN__ {
  reverse_proxy __CADDY_API_UPSTREAM__
}
__CADDY_APP_DOMAIN__ {
  reverse_proxy __CADDY_APP_UPSTREAM__
}
__CADDY_WEBRTC_DOMAIN__ {
  @ws {
    header Connection *Upgrade*
    header Upgrade websocket
  }
  handle @ws {
    reverse_proxy __CADDY_WEBRTC_UPSTREAM__
  }
  handle {
    respond "WebSocket Only" 400
  }
}
