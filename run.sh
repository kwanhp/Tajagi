#!/bin/bash
# 실행 중인 Tajagi를 끝내고(완전히 종료될 때까지 기다림) 새로 연다
cd "$(dirname "$0")"
pkill -x Tajagi || true
while pgrep -x Tajagi >/dev/null; do sleep 0.2; done
open build/Tajagi.app
