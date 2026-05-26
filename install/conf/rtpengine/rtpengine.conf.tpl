[rtpengine]
table = -1
interface = priv/__PRIVATE_IP__;pub/__PRIVATE_IP__!__PUBLIC_IP__
listen-ng = 0.0.0.0:__RTPE_NG_PORT__
port-min = __RTPE_PORT_MIN__
port-max = __RTPE_PORT_MAX__
log-stderr = true
log-level = 6
offer-timeout = 120
