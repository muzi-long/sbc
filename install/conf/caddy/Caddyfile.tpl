__CADDY_API_DOMAIN__ {
  log {
    output file /var/log/caddy/api.log {
      roll_size 100mb
      roll_keep 7
      roll_keep_for 720h
    }
    format json
  }
  reverse_proxy __CADDY_API_UPSTREAM__
}
__CADDY_APP_DOMAIN__ {
  log {
    output file /var/log/caddy/app.log {
      roll_size 100mb
      roll_keep 7
      roll_keep_for 720h
    }
    format json
  }
  reverse_proxy __CADDY_APP_UPSTREAM__
}
__CADDY_WEBRTC_DOMAIN__ {
  log {
    output file /var/log/caddy/webrtc.log {
      roll_size 100mb
      roll_keep 7
      roll_keep_for 720h
    }
    format json
  }
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
