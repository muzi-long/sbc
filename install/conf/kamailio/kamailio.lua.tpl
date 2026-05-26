FLT_INTERNAL = 20
FLT_EXTERNAL = 21
FLB_INTERNAL = 22
FLB_EXTERNAL = 23
FLT_NATS = 5
FLB_NATB = 6
FLB_NATSIPPING = 7
WEBRTC_UAC = 25
WEBRTC_UAS = 26
MEDIA_EXTERNAL_TO_INTERNAL = " direction=pub direction=priv"
MEDIA_INTERNAL_TO_EXTERNAL = " direction=priv direction=pub"
MEDIA_INTERNAL_TO_INTERNAL = " direction=priv direction=priv"
USER_AGENT_LIST = {
    "JsSIP",
    "Telephone",
    "MicroSIP"
}

-- SIP request routing
-- equivalent of request_route{}
function ksr_request_route()
    ksr_route_reqinit();
    ksr_route_natdetect();

    if KSR.siputils.has_totag() > 0 then
        KSR.rr.loose_route()
    end

    -- CANCEL processing
    if KSR.is_CANCEL() then
        if KSR.tm.t_check_trans() > 0 then
            ksr_route_relay();
        end
        KSR.x.exit()
    end

    if KSR.is_REGISTER() then
        ksr_route_registrar();
    end

    -- 处理二次invite，区分来自fs还是外部
    if KSR.is_INVITE() and KSR.siputils.has_totag() > 0 then
        if KSR.dispatcher.ds_is_from_list("1", 3) > 0 then
            if KSR.is_myself_turi() then
                if KSR.htable.sht_gete("sips", KSR.pv.gete("$tU")) == "webrtc" then
                    KSR.setflag(WEBRTC_UAS);
                end
            end
            KSR.setflag(FLT_INTERNAL);
        else
            KSR.setflag(FLT_EXTERNAL);
        end
        ksr_rtp_offer()
        KSR.tm.t_on_branch("ksr_branch_manage");
        KSR.tm.t_on_reply("ksr_onreply_manage");
        ksr_route_relay();
        KSR.x.exit();
    end

    if KSR.is_INVITE() then
        local ua = KSR.kx.gete_ua();
        if KSR.dispatcher.ds_is_from_list("2", 3) > 0 then
            KSR.info("来自网关呼入:" .. KSR.pv.gete("$fU") .. " => " .. KSR.pv.gete("$tU").."\n")
            if KSR.dispatcher.ds_select_dst(1, "6") < 0 then
                KSR.sl.sl_send_reply(503, "unavailable");
                KSR.x.exit()
            end
            KSR.setflag(FLT_EXTERNAL);
            ksr_rtp_offer()
            if KSR.tm.t_is_set("onreply_route") < 0 then
                KSR.tm.t_on_reply("ksr_onreply_manage");
            end
            if KSR.tm.t_is_set("branch_route") < 0 then
                KSR.tm.t_on_branch("ksr_branch_manage");
            end
            KSR.tm.t_on_failure("ksr_failure_manage");
            if KSR.tm.t_relay() < 0 then
                KSR.sl.sl_reply_error();
            end
        elseif ksr_check_user_agent() == true then
            KSR.info("来自客户端的呼叫，" .. KSR.pv.gete("$fU") .. " => " .. KSR.pv.gete("$tU") .. "\n")
            if KSR.registrar.registered_uri("location", KSR.pv.gete("$fu")) < 0 then
                KSR.info("User " .. KSR.pv.gete("$fu") .. " is not registered.\n")
                KSR.sl.send_reply(403, "Forbidden")
                KSR.x.exit()
            end
            if KSR.dispatcher.ds_select_dst(1, "6") < 0 then
                KSR.sl.sl_send_reply(503, "unavailable");
                KSR.x.exit()
            end
            if KSR.pv.gete('$proto') == "ws" or KSR.pv.gete('$proto') == "wss" then
                KSR.setflag(WEBRTC_UAC);
            end
            KSR.setflag(FLT_EXTERNAL);
            ksr_rtp_offer()
            if KSR.tm.t_is_set("onreply_route") < 0 then
                KSR.tm.t_on_reply("ksr_onreply_manage");
            end
            if KSR.tm.t_is_set("branch_route") < 0 then
                KSR.tm.t_on_branch("ksr_branch_manage");
            end
            KSR.tm.t_on_failure("ksr_failure_manage");
            if KSR.tm.t_relay() < 0 then
                KSR.sl.sl_reply_error();
            end
            KSR.x.exit();
        elseif KSR.dispatcher.ds_is_from_list("1", 3) > 0 then
            if KSR.is_myself_turi() then
                KSR.info("来自FreeSWITCH的呼叫,转发给本地" .. KSR.pv.gete("$fU") .. " => " .. KSR.pv.gete("$tU") .. "\n")
                KSR.setflag(FLT_INTERNAL);
                if KSR.htable.sht_gete("sips", KSR.pv.gete("$tU")) == "webrtc" then
                    KSR.setflag(WEBRTC_UAS);
                end
                ksr_rtp_offer()
                if KSR.tm.t_is_set("onreply_route") < 0 then
                    KSR.tm.t_on_reply("ksr_onreply_manage");
                end
                if KSR.tm.t_is_set("branch_route") < 0 then
                    KSR.tm.t_on_branch("ksr_branch_manage");
                end
                KSR.tm.t_on_failure("ksr_failure_manage");
                ksr_route_location();
            else
                KSR.info("来自FreeSWITCH的人工呼叫,转发给线路" .. KSR.pv.gete("$fU") .. " => " .. KSR.pv.gete("$tU") .. "\n")
                KSR.setflag(FLT_INTERNAL);
                ksr_rtp_offer()
                if KSR.tm.t_is_set("onreply_route") < 0 then
                    KSR.tm.t_on_reply("ksr_onreply_manage");
                end
                if KSR.tm.t_is_set("branch_route") < 0 then
                    KSR.tm.t_on_branch("ksr_branch_manage");
                end
                KSR.tm.t_on_failure("ksr_failure_manage");
                if KSR.tm.t_relay() < 0 then
                    KSR.sl.sl_reply_error();
                end
                KSR.x.exit();
            end
        else
            KSR.x.exit()
        end
    end

    if KSR.is_ACK() or KSR.is_BYE() then
        ksr_route_relay()
    end

    if KSR.is_INFO() then
        KSR.sl.sl_send_reply(200, "OK");
        KSR.x.exit();
    end

    if KSR.is_UPDATE() then
        if KSR.dispatcher.ds_is_from_list("1", 3) > 0 then
            if KSR.is_myself_turi() then
                if KSR.htable.sht_gete("sips", KSR.pv.gete("$tU")) == "webrtc" then
                    KSR.setflag(WEBRTC_UAS);
                end
            end
            KSR.setflag(FLT_INTERNAL);
        else
            KSR.setflag(FLT_EXTERNAL);
        end
        ksr_rtp_offer()
        KSR.tm.t_on_branch("ksr_branch_manage");
        KSR.tm.t_on_reply("ksr_onreply_manage");
        ksr_route_relay();
    end

    return 1;
end

function ksr_route_reqinit()
    if KSR.is_REGISTER() then
        if ksr_check_user_agent() == false then
            KSR.x.exit();
        end
    end
    if KSR.is_OPTIONS() then
        KSR.sl.sl_send_reply(200, "Keepalive");
        KSR.x.exit();
    end
    -- if KSR.is_method("KDMQ") then
    --     KSR.dmq.handle_message();
    --     KSR.x.exit()
    -- end
    -- KSR.hdr.remove("Route");

    --if KSR.is_method_in("IS") then
    --	KSR.rr.record_route();
    --end

    -- no connect for sending replies
    KSR.set_reply_no_connect();
    -- enforce symmetric signaling
    -- send back replies to the source address of request
    KSR.force_rport();

    if KSR.maxfwd.process_maxfwd(10) < 0 then
        KSR.sl.sl_send_reply(483, "Too Many Hops");
        KSR.x.exit();
    end

    if KSR.is_OPTIONS() and KSR.is_myself_ruri() and KSR.corex.has_ruri_user() < 0 then
        KSR.sl.sl_send_reply(200, "Keepalive");
        KSR.x.exit();
    end

    return 1
end

function ksr_route_natdetect()
    if KSR.nathelper.nat_uac_test(19) > 0 then
        if KSR.is_REGISTER() then
            KSR.nathelper.fix_nated_register();
        elseif KSR.siputils.is_first_hop() > 0 then
            KSR.nathelper.set_contact_alias();
        end
        KSR.setflag(FLT_NATS);
    end
    KSR.nathelper.handle_ruri_alias();
    return 1;
end

function ksr_route_registrar()
    if not KSR.auth then
        return 1;
    end

    if KSR.isflagset(FLT_NATS) then
        KSR.setbflag(FLB_NATB);
        KSR.setbflag(FLB_NATSIPPING);
    end

    -- authenticate requests
    if KSR.auth_db.auth_check(KSR.pv.gete("$fd"), "users", 1) < 0 then
        KSR.auth.auth_challenge(KSR.pv.gete("$fd"), 0);
        KSR.x.exit();
    end
    -- user authenticated - remove auth header
    if not KSR.is_method_in("RP") then
        KSR.auth.consume_credentials();
    end
    if (not KSR.is_myself_furi()) and (not KSR.is_myself_ruri()) then
        KSR.sl.sl_send_reply(403, "Not relaying");
        KSR.x.exit();
    end
    if KSR.registrar.save("location", 0, KSR.pv.gete("$fu")) < 0 then
        KSR.sl.sl_reply_error();
        KSR.x.exit();
    end

    -- 注册注销后的事件通知
    local client = "webrtc"
    if KSR.is_UDP() then
        client = "soft_switch"
    end
    KSR.htable.sht_setxs("sips", KSR.pv.gete("$fU"), client, 3600);

    local status = "register"
    local expires = tonumber(KSR.hdr.gete("Expires"));
    if expires == 0 then
        status = "unregister"
    end

    local regEventInfo = {
        sip = KSR.pv.gete("$fU"),
        status = status,
        client = client,
        expires = expires
    }
    local regEventVal = ksr_table_to_json(regEventInfo)
    KSR.ndb_redis.redis_cmd("srvN", "RPUSH acd:sip:register_event " .. regEventVal, "r");
    KSR.ndb_redis.redis_free("r")
    return 1;
end

function ksr_route_location()
    local rc = KSR.registrar.lookup("location");
    if rc < 0 then
        KSR.tm.t_newtran();
        if rc == -1 or rc == -3 then
            KSR.sl.send_reply(404, "Not Found");
            KSR.x.exit();
        elseif rc == -2 then
            KSR.sl.send_reply(405, "Method Not Allowed");
            KSR.x.exit();
        end
    end
    if KSR.tm.t_relay() < 0 then
        KSR.sl.sl_reply_error();
    end
    KSR.x.exit();
end

function ksr_route_relay()
    if KSR.is_BYE() then
        KSR.rtpengine.rtpengine_delete("")
        KSR.nathelper.handle_ruri_alias();
    end
    if KSR.tm.t_relay() < 0 then
        KSR.sl.sl_reply_error();
    end
    KSR.x.exit();
end

function ksr_xhttp_event(evname)
    KSR.set_reply_close()
    KSR.set_reply_no_connect()
    if KSR.hdr.gete("Upgrade") == "websocket" then
        if KSR.websocket.handle_handshake() > 0 then
            return 1
        end
    end
    if string.sub(KSR.pv.gete("$hu"), 0, 8) == "/metrics" then
        KSR.xhttp_prom.dispatch()
        return 1
    end
    KSR.xhttp.xhttp_reply("404", "Not Found", "text/plain", "Not Found")
    return 1
end

function ksr_onreply_manage()
    ksr_route_natmanage()
    ksr_rtp_answer()
end

function ksr_branch_manage()
    ksr_route_natmanage()
    if KSR.isflagset(FLT_EXTERNAL) then
        KSR.rr.record_route()
    else
        KSR.rr.record_route_advertised_address("__PRIVATE_IP__:__SIP_UDP_PORT__")
    end
end

function ksr_rtp_offer()
    if KSR.hdr.gete("Content-Type") ~= "application/sdp" then
        return
    end

    local reflags
    if KSR.isflagset(WEBRTC_UAC) then
        reflags = "trust-address replace-origin replace-session-connection rtcp-mux-demux  DTLS=off SDES-off ICE=remove RTP/AVP"
    elseif KSR.isflagset(WEBRTC_UAS) then
        reflags = "trust-address replace-origin replace-session-connection rtcp-mux-offer generate-mid DTLS=passive SDES-off ICE=force RTP/SAVPF"
    else
        reflags = "trust-address replace-origin replace-session-connection"
    end

    local direction
    if KSR.isflagset(FLT_INTERNAL) then
        direction = MEDIA_INTERNAL_TO_EXTERNAL
    elseif KSR.isflagset(FLT_EXTERNAL) then
        direction = MEDIA_EXTERNAL_TO_INTERNAL
    else
        direction = MEDIA_INTERNAL_TO_INTERNAL
    end

    KSR.rtpengine.rtpengine_offer(reflags .. direction);
end

function ksr_rtp_answer()
    local scode = KSR.kx.get_status()
    if scode > 100 and scode < 299 and KSR.hdr.gete("Content-Type") == "application/sdp" then
        local reflags
        if KSR.isflagset(WEBRTC_UAC) then
            reflags = "trust-address replace-origin replace-session-connection rtcp-mux-offer generate-mid DTLS=passive SDES-off ICE=force RTP/SAVPF"
        elseif KSR.isflagset(WEBRTC_UAS) then
            reflags = "trust-address replace-origin replace-session-connection rtcp-mux-demux DTLS=off SDES-off ICE=remove RTP/AVP"
        else
            reflags = "trust-address replace-origin replace-session-connection"
        end

        local direction
        if KSR.isflagset(FLT_INTERNAL) then
            direction = MEDIA_EXTERNAL_TO_INTERNAL
        elseif KSR.isflagset(FLT_EXTERNAL) then
            direction = MEDIA_INTERNAL_TO_EXTERNAL
        else
            direction = MEDIA_INTERNAL_TO_INTERNAL
        end

        KSR.rtpengine.rtpengine_answer(reflags .. direction);
    end
end

function ksr_route_natmanage()
    if KSR.siputils.is_request() > 0 then
        if KSR.siputils.has_totag() > 0 then
            if KSR.rr.check_route_param("nat=yes") > 0 then
                KSR.setbflag(FLB_NATB);
            end
        end
    end
    if (not (KSR.isflagset(FLT_NATS) or KSR.isbflagset(FLB_NATB))) then
        return 1;
    end
    if KSR.siputils.is_request() > 0 then
        if KSR.siputils.has_totag() < 0 then
            if KSR.tmx.t_is_branch_route() > 0 then
                KSR.rr.add_rr_param(";nat=yes");
            end
        end
    end
    if KSR.siputils.is_reply() > 0 then
        if KSR.isbflagset(FLB_NATB) then
            KSR.nathelper.set_contact_alias();
        end
    end
    return 1;
end

-- 检测userAgent
function ksr_check_user_agent()
    local ua = KSR.kx.gete_ua();
    for idx, val in pairs(USER_AGENT_LIST) do
        if string.find(ua, val) then
            return true
        end
    end
    return false
end

function ksr_failure_manage()
    KSR.rtpengine.rtpengine_delete("")
end

function ksr_uuid()
    local seed = { 'e', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' }
    local tb = {}
    for i = 1, 32 do
        table.insert(tb, seed[math.random(1, 16)])
    end
    local sid = table.concat(tb)
    return string.format('%s-%s-%s-%s-%s',
        string.sub(sid, 1, 8),
        string.sub(sid, 9, 12),
        string.sub(sid, 13, 16),
        string.sub(sid, 17, 20),
        string.sub(sid, 21, 32)
    )
end

function ksr_table_to_json(tbl)
    local json = "{"
    local first = true
    for k, v in pairs(tbl) do
        if not first then
            json = json .. ","
        end
        first = false
        if type(k) == "number" then
            json = json .. "[" .. k .. "]"
        elseif type(k) == "string" then
            json = json .. '"' .. k .. '"'
        else
            error("Invalid key type: " .. type(k))
        end
        json = json .. ":"
        if type(v) == "number" or type(v) == "boolean" then
            json = json .. tostring(v)
        elseif type(v) == "string" then
            json = json .. '"' .. v .. '"'
        elseif type(v) == "table" then
            json = json .. table_to_json(v)
        else
            error("Invalid value type: " .. type(v))
        end
    end
    json = json .. "}"
    return json
end
