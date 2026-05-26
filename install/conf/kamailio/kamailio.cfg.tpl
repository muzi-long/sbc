#!KAMAILIO


####### Defined Values #########
# 部署前替换为真实值,不要把密码 commit 到仓库
#!define DBURL "mysql://__DB_USER__:__DB_PASS__@__DB_HOST__:__DB_PORT__/__DB_NAME__"
#!define REDISURL "name=srvN;addr=__REDIS_HOST__;port=__REDIS_PORT__;pass=__REDIS_PASS__;db=0"
#!define DBGLEVEL 2
#!define MULTIDOMAIN 0
#!define FLT_ACC 1
#!define FLT_ACCMISSED 2
#!define FLT_ACCFAILED 3
#!define FLT_NATS 5
#!define FLB_NATB 6
#!define FLB_NATSIPPING 7
#!define FLT_INTERNAL 20
#!define FLT_EXTERNAL 21
#!define FLB_INTERNAL 22
#!define FLB_EXTERNAL 23
#!define WEBRTC_UAC 25
#!define WEBRTC_UAS 26


####### Global Parameters #########
debug=DBGLEVEL
log_stderror=yes
memdbg=5
memlog=5
children=20
alias="__KAM_ALIAS_1__"
alias="__KAM_ALIAS_2__"
listen=udp:__LISTEN_IFACE__:__SIP_UDP_PORT__ advertise __PUBLIC_IP__:__SIP_UDP_PORT__
listen=tcp:__LISTEN_IFACE__:__SIP_TCP_PORT__
# 同时绑 loopback,让 caddy(本机反代)可以走 127.0.0.1:port,无需知道 PRIVATE_IP
listen=tcp:127.0.0.1:__SIP_TCP_PORT__
tcp_connection_lifetime=3605
tcp_max_connections=2048
tcp_accept_no_cl=yes
enable_sctp=no
http_reply_parse=yes
ip_free_bind=1
user_agent_header="User-Agent: kam-cc"
server_signature=no
server_header="Server: kam-cc"


####### Modules Section ########
# mpath="/usr/lib/x86_64-linux-gnu/kamailio/modules/"

loadmodule "db_mysql.so"
loadmodule "xhttp.so"
loadmodule "jsonrpcs.so"
loadmodule "kex.so"
loadmodule "corex.so"
loadmodule "tm.so"
loadmodule "tmx.so"
loadmodule "sl.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "maxfwd.so"
loadmodule "usrloc.so"
loadmodule "registrar.so"
loadmodule "textops.so"
loadmodule "textopsx.so"
loadmodule "siputils.so"
loadmodule "xlog.so"
loadmodule "sanity.so"
loadmodule "ctl.so"
loadmodule "cfg_rpc.so"
loadmodule "acc.so"
loadmodule "counters.so"
loadmodule "auth.so"
loadmodule "auth_db.so"
loadmodule "permissions.so"
loadmodule "nathelper.so"
loadmodule "rtpengine.so"
loadmodule "htable.so"
loadmodule "dispatcher.so"
loadmodule "websocket.so"
loadmodule "kemix.so"
loadmodule "http_client.so"
loadmodule "app_lua.so"

#!ifdef REDISURL
loadmodule "ndb_redis.so"
modparam("ndb_redis", "server", REDISURL)
modparam("ndb_redis", "cluster", 0)
#!endif

# ----------------- setting module-specific parameters ---------------
modparam("sanity", "autodrop", 0)

modparam("tm", "failure_reply_mode", 3)
modparam("tm", "fr_timer", 30000)
modparam("tm", "fr_inv_timer", 120000)


modparam("rr", "enable_full_lr", 0)
modparam("rr", "append_fromtag", 0)

modparam("registrar", "default_expires", 15)
modparam("registrar", "min_expires", 10)
modparam("registrar", "max_expires", 120)

modparam("usrloc", "preload", "location")
modparam("usrloc", "timer_interval", 60)
modparam("usrloc", "timer_procs", 1)
modparam("usrloc", "use_domain", MULTIDOMAIN)
modparam("usrloc", "db_mode", 0)
modparam("usrloc", "nat_bflag", FLB_NATB)
modparam("usrloc", "handle_lost_tcp", 1)

modparam("auth_db", "db_url", DBURL)
modparam("auth_db", "calculate_ha1", yes)
modparam("auth_db", "user_column", "sip_id")
modparam("auth_db", "password_column", "sip_password")
modparam("auth_db", "load_credentials", "")
modparam("auth_db", "use_domain", MULTIDOMAIN)


modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:__RTPE_NG_PORT__")


modparam("nathelper", "natping_interval", 30)
modparam("nathelper", "ping_nated_only", 1)
modparam("nathelper", "sipping_bflag", FLB_NATSIPPING)
modparam("nathelper", "sipping_from", "sip:pinger@kamailio.org")
modparam("nathelper|registrar", "received_avp", "$avp(received_avp)")

modparam("htable", "htable", "sips=>size=10000;")
modparam("htable", "key_name_column", "sip")
modparam("htable", "key_type_column", "string")
modparam("htable", "value_type_column", "string")
modparam("htable", "key_value_column", "regType")

modparam("dispatcher", "list_file", "/etc/kamailio/dispatcher.list")
modparam("dispatcher", "ds_ping_from", "sip:proxy@kamailio.org")
modparam("dispatcher", "ds_ping_interval", 30)
modparam("dispatcher", "ds_probing_mode", 1)

modparam("http_client", "connection_timeout", 5)
modparam("http_client", "keep_connections", 1)

loadmodule "xhttp_prom.so"
modparam("xhttp_prom", "xhttp_prom_stats", "all")

modparam("xhttp", "event_callback", "ksr_xhttp_event")
modparam("app_lua", "load", "/etc/kamailio/kamailio.lua")
cfgengine "lua"
