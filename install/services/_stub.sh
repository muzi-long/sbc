#!/usr/bin/env bash
# 仅用于测试:把调用记录到 $STUB_LOG
do_install()     { echo "stub:install" >> "$STUB_LOG"; }
do_reconfigure() { echo "stub:reconfigure" >> "$STUB_LOG"; }
do_health()      { echo "stub:health" >> "$STUB_LOG"; }
